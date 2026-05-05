#!/usr/bin/env bash
# run-critic.sh — Adversarial pre-build architecture reviewer.
#
# Usage:
#   bash run-critic.sh --task "<description>" --done-when <file> [--repo <path>] [--checklist <file>]
#
# Exit codes: 0=APPROVE, 1=REVISE, 2=REJECT, 3=ERROR
# Verdicts saved to: <workspace>/specialists/critic-verdicts/YYYY-MM-DD-<slug>.md

set -euo pipefail

# ── Locate workspace ─────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Workspace: env override > openclaw default
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
if [[ ! -d "$WORKSPACE" ]]; then
  WORKSPACE="$(pwd)"
fi

DATE=$(date '+%Y-%m-%d')
TIME=$(date '+%H:%M')

# ── Parse args ────────────────────────────────────────
TASK=""
DONE_WHEN_FILE=""
REPO=""
CHECKLIST_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)       TASK="$2";           shift 2 ;;
    --done-when)  DONE_WHEN_FILE="$2"; shift 2 ;;
    --repo)       REPO="$2";           shift 2 ;;
    --checklist)  CHECKLIST_FILE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 3 ;;
  esac
done

if [[ -z "$TASK" || -z "$DONE_WHEN_FILE" ]]; then
  echo "Usage: run-critic.sh --task \"<description>\" --done-when <file> [--repo <path>] [--checklist <file>]"
  exit 3
fi

if [[ ! -f "$DONE_WHEN_FILE" ]]; then
  echo "ERROR: DONE_WHEN file not found: $DONE_WHEN_FILE"
  exit 3
fi

REPO="${REPO:-$(pwd)}"

# ── Resolve API key (any LLM provider) ───────────────
API_KEY=""
MODEL=""
PROVIDER=""

resolve_from_openclaw_config() {
  local config_file="$HOME/.openclaw/openclaw.json"
  [[ ! -f "$config_file" ]] && return
  python3 - "$config_file" << 'PYEOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    # Primary model
    model = (d.get('model') or
             d.get('models', {}).get('primary') or
             d.get('providers', {}).get('primary', ''))
    print(f"MODEL={model}")
    # API keys — try common provider locations
    anthropic_key = (d.get('anthropic', {}).get('apiKey') or
                     d.get('providers', {}).get('anthropic', {}).get('apiKey') or '')
    openai_key    = (d.get('openai', {}).get('apiKey') or
                     d.get('providers', {}).get('openai', {}).get('apiKey') or '')
    gemini_key    = (d.get('google', {}).get('apiKey') or
                     d.get('providers', {}).get('google', {}).get('apiKey') or '')
    if anthropic_key:
        print(f"PROVIDER=anthropic")
        print(f"API_KEY={anthropic_key}")
    elif openai_key:
        print(f"PROVIDER=openai")
        print(f"API_KEY={openai_key}")
    elif gemini_key:
        print(f"PROVIDER=google")
        print(f"API_KEY={gemini_key}")
except Exception as e:
    pass
PYEOF
}

# Load from OpenClaw config
if config_vals=$(resolve_from_openclaw_config 2>/dev/null); then
  eval "$config_vals" 2>/dev/null || true
fi

# Env overrides
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && { API_KEY="$ANTHROPIC_API_KEY"; PROVIDER="anthropic"; }
[[ -n "${OPENAI_API_KEY:-}"    ]] && { API_KEY="$OPENAI_API_KEY";    PROVIDER="openai"; }
[[ -n "${GEMINI_API_KEY:-}"    ]] && { API_KEY="$GEMINI_API_KEY";    PROVIDER="google"; }

if [[ -z "$API_KEY" ]]; then
  echo "ERROR: No API key found. Set ANTHROPIC_API_KEY, OPENAI_API_KEY, or GEMINI_API_KEY,"
  echo "       or configure a provider in openclaw.json."
  exit 3
fi

# Normalize model name per provider
if [[ -z "$MODEL" || "$MODEL" == "default" ]]; then
  case "$PROVIDER" in
    anthropic) MODEL="claude-sonnet-4-6" ;;
    openai)    MODEL="gpt-4o" ;;
    google)    MODEL="gemini-2.0-flash" ;;
    *)         MODEL="claude-sonnet-4-6" ;;
  esac
fi
# Strip provider prefix if present (e.g. "anthropic/claude-sonnet-4-6")
MODEL="${MODEL##*/}"

echo ""
echo "════════════════════════════════════════════════"
echo "  ARCHITECTURE CRITIC"
echo "  Task: $TASK  |  $DATE $TIME"
echo "  Model: $PROVIDER/$MODEL"
echo "════════════════════════════════════════════════"
echo ""

# ── Snapshot codebase ─────────────────────────────────
echo "── Snapshotting codebase..."
SNAPSHOT_FILE=$(mktemp /tmp/critic-snapshot-XXXXXX.txt)
PROMPT_FILE=$(mktemp /tmp/critic-prompt-XXXXXX.txt)

python3 - "$REPO" "$SNAPSHOT_FILE" << 'PYEOF'
import os, sys

repo   = sys.argv[1]
outf   = sys.argv[2]
lines  = []
MAX_FILES = 40
MAX_BYTES_PER_FILE = 8000
file_count = 0

# File tree
lines.append("=== FILE TREE ===")
for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in sorted(dirs)
               if d not in {'.git','node_modules','.next','.vercel','dist','build',
                            '__pycache__','.venv','venv','.pytest_cache','coverage'}]
    level = root.replace(repo, '').count(os.sep)
    indent = '  ' * level
    folder = os.path.basename(root)
    if level == 0:
        lines.append(f"{folder}/")
    else:
        lines.append(f"{indent}{folder}/")
    for f in sorted(files):
        lines.append(f"{'  '*(level+1)}{f}")

# Key source files
lines.append("\n=== KEY SOURCE FILES ===")
INCLUDE_EXTS = {'.ts','.tsx','.js','.jsx','.py','.go','.rs','.sql','.prisma','.graphql'}
PRIORITY_PATTERNS = ['/api/','/app/','/src/','/routes/','/models/','/schema','/db/','/lib/','/services/']
SKIP_PATTERNS    = ['node_modules','.git','.next','dist','build','__pycache__',
                    '.min.js','.min.css','package-lock','yarn.lock','bun.lock',
                    '.d.ts','migration','generated']

candidate_files = []
for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in dirs if d not in
               {'node_modules','.git','.next','dist','build','__pycache__','.venv','venv'}]
    for fname in files:
        if not any(fname.endswith(ext) for ext in INCLUDE_EXTS):
            continue
        fpath = os.path.join(root, fname)
        rel   = fpath.replace(repo, '')
        if any(p in rel for p in SKIP_PATTERNS):
            continue
        priority = 1 if any(p in rel for p in PRIORITY_PATTERNS) else 0
        candidate_files.append((priority, fpath, rel))

candidate_files.sort(key=lambda x: (-x[0], x[2]))

for _, fpath, rel in candidate_files:
    if file_count >= MAX_FILES:
        break
    try:
        with open(fpath, 'r', errors='replace') as f:
            content = f.read(MAX_BYTES_PER_FILE)
        lines.append(f"\n=== {rel} ===")
        lines.append(content[:MAX_BYTES_PER_FILE])
        if len(content) >= MAX_BYTES_PER_FILE:
            lines.append("[... truncated ...]")
        file_count += 1
    except Exception:
        pass

# vercel.json / config files
for cfg in ['vercel.json', 'next.config.ts', 'next.config.js', 'package.json']:
    cfgpath = os.path.join(repo, cfg)
    if os.path.exists(cfgpath):
        try:
            with open(cfgpath) as f:
                lines.append(f"\n=== {cfg} ===")
                lines.append(f.read(4000))
        except Exception:
            pass

with open(outf, 'w') as f:
    f.write('\n'.join(lines))
PYEOF

# ── Load checklists ───────────────────────────────────
CHECKLIST_CONTENT=""
if [[ -n "$CHECKLIST_FILE" && -f "$CHECKLIST_FILE" ]]; then
  CHECKLIST_CONTENT=$(cat "$CHECKLIST_FILE")
elif [[ -d "$SKILL_DIR/references" ]]; then
  for ref in "$SKILL_DIR/references"/*.md; do
    [[ -f "$ref" ]] && CHECKLIST_CONTENT+=$'\n\n'"$(cat "$ref")"
  done
fi

# ── Build prompt ──────────────────────────────────────
DONE_WHEN=$(cat "$DONE_WHEN_FILE")
SNAPSHOT=$(cat "$SNAPSHOT_FILE")

cat > "$PROMPT_FILE" << PROMPT
You are an adversarial architecture reviewer. Your job is to find what is wrong with the proposed build — NOT to be helpful, encouraging, or collaborative.

You have no prior context. You have not seen the conversation that led to this proposal. You have no stake in whether this build proceeds.

Read the proposal and codebase state. Run it against the checklists. Return a verdict.

## TASK
$TASK

## PROPOSAL (DONE_WHEN BRIEF)
$DONE_WHEN

## CODEBASE STATE
$SNAPSHOT

## REVIEW CHECKLISTS
$CHECKLIST_CONTENT

---

## YOUR JOB

Review the proposal against the checklists. Look for:
- Payment/charge flow risks (missing webhook handling, idempotency, race conditions)
- Auth and security gaps (bypass vectors, exposed secrets, injection risks)
- Sacred file risks (config files, deployment files that if broken kill production)
- Scope violations (plan touches more than stated, or is missing obvious required pieces)
- Architecture drift (new patterns when existing ones work, unnecessary dependencies)
- Missing rollback plan (if deploy fails, how do you get back?)
- Deployment risks (env vars, cold starts, CDN cache behavior)

## VERDICT FORMAT

Return ONLY this format — nothing else before or after:

VERDICT: [APPROVE | REVISE | REJECT]

[If APPROVE:]
The plan is sound. No blocking issues identified against the applicable checklists.
[Optional: 1-2 advisory notes marked WARN]

[If REVISE or REJECT:]
FINDING-1 [BLOCKING or WARN] — SHORT TITLE
Specific description of the problem. What is missing or wrong. What needs to change.

FINDING-2 [BLOCKING or WARN] — SHORT TITLE
...

ACTION: [What must happen before proceeding]

---

Be specific. Name the exact files, flows, or patterns at risk. Do not soften findings. Do not suggest that the plan is "generally good" — either it passes or it doesn't.
PROMPT

# ── Call LLM ──────────────────────────────────────────
echo "── Running critic ($PROVIDER/$MODEL, temp=0)..."

CRITIC_RESPONSE=""

call_anthropic() {
  python3 - "$PROMPT_FILE" "$API_KEY" "$MODEL" << 'PYEOF'
import sys, json, urllib.request, urllib.error

prompt_file = sys.argv[1]
api_key     = sys.argv[2]
model       = sys.argv[3]

with open(prompt_file) as f:
    prompt = f.read()

payload = json.dumps({
    "model": model,
    "max_tokens": 1500,
    "temperature": 0,
    "messages": [{"role": "user", "content": prompt}]
}).encode()

req = urllib.request.Request(
    "https://api.anthropic.com/v1/messages",
    data=payload,
    headers={
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }
)
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        d = json.loads(r.read())
        print(d["content"][0]["text"])
except urllib.error.HTTPError as e:
    print(f"HTTP ERROR {e.code}: {e.read().decode()}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

call_openai() {
  python3 - "$PROMPT_FILE" "$API_KEY" "$MODEL" << 'PYEOF'
import sys, json, urllib.request, urllib.error

prompt_file = sys.argv[1]
api_key     = sys.argv[2]
model       = sys.argv[3]

with open(prompt_file) as f:
    prompt = f.read()

payload = json.dumps({
    "model": model,
    "temperature": 0,
    "max_tokens": 1500,
    "messages": [{"role": "user", "content": prompt}]
}).encode()

req = urllib.request.Request(
    "https://api.openai.com/v1/chat/completions",
    data=payload,
    headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
)
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        d = json.loads(r.read())
        print(d["choices"][0]["message"]["content"])
except urllib.error.HTTPError as e:
    print(f"HTTP ERROR {e.code}: {e.read().decode()}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

call_google() {
  python3 - "$PROMPT_FILE" "$API_KEY" "$MODEL" << 'PYEOF'
import sys, json, urllib.request, urllib.error

prompt_file = sys.argv[1]
api_key     = sys.argv[2]
model       = sys.argv[3]

with open(prompt_file) as f:
    prompt = f.read()

payload = json.dumps({
    "contents": [{"parts": [{"text": prompt}]}],
    "generationConfig": {"temperature": 0, "maxOutputTokens": 1500}
}).encode()

url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        d = json.loads(r.read())
        print(d["candidates"][0]["content"]["parts"][0]["text"])
except urllib.error.HTTPError as e:
    print(f"HTTP ERROR {e.code}: {e.read().decode()}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

case "$PROVIDER" in
  anthropic) CRITIC_RESPONSE=$(call_anthropic) ;;
  openai)    CRITIC_RESPONSE=$(call_openai) ;;
  google)    CRITIC_RESPONSE=$(call_google) ;;
  *)         echo "ERROR: Unknown provider: $PROVIDER"; exit 3 ;;
esac

# ── Parse verdict ─────────────────────────────────────
VERDICT=""
if echo "$CRITIC_RESPONSE" | grep -q "VERDICT: APPROVE"; then
  VERDICT="APPROVE"
elif echo "$CRITIC_RESPONSE" | grep -q "VERDICT: REVISE"; then
  VERDICT="REVISE"
elif echo "$CRITIC_RESPONSE" | grep -q "VERDICT: REJECT"; then
  VERDICT="REJECT"
else
  VERDICT="UNKNOWN"
fi

# ── Save verdict ──────────────────────────────────────
VERDICTS_DIR="$WORKSPACE/specialists/critic-verdicts"
mkdir -p "$VERDICTS_DIR"

SLUG=$(echo "$TASK" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-60)
VERDICT_FILE="$VERDICTS_DIR/$DATE-$SLUG.md"

cat > "$VERDICT_FILE" << VEOF
# Critic Verdict — $DATE $TIME
**Task:** $TASK
**Verdict:** $VERDICT
**Model:** $PROVIDER/$MODEL

---

$CRITIC_RESPONSE
VEOF

echo "── Verdict: $VERDICT"
echo "── Saved:   $VERDICT_FILE"
echo ""
echo "════════════════════════════════════════════════"
echo "  CRITIC VERDICT: $VERDICT"
echo "════════════════════════════════════════════════"
echo ""
echo "$CRITIC_RESPONSE"
echo ""

# Cleanup
rm -f "$SNAPSHOT_FILE" "$PROMPT_FILE"

# Exit code maps to verdict
case "$VERDICT" in
  APPROVE) exit 0 ;;
  REVISE)  exit 1 ;;
  REJECT)  exit 2 ;;
  *)       exit 3 ;;
esac
