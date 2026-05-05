---
name: architecture-critic
description: >
  Adversarial pre-build architecture review. Spawns a structurally independent agent
  that reviews proposed builds, features, or operational decisions BEFORE any code is
  written. The critic sees only the task spec and codebase state — never conversation
  history, enthusiasm, or the proposer's reasoning. Returns APPROVE, REVISE, or REJECT
  with specific, itemized findings. Use when: starting any new feature, endpoint, schema
  change, payment/auth touch, or any decision being recommended with confidence.
  Skip only for: copy/style-only changes under 3 files with no logic, or isolated bug
  fixes that don't touch payment or auth.
---

# Architecture Critic

An adversarial pre-build agent. Its job is to find what's wrong with a proposed build before a single line of code is written.

This is not a collaborator. It does not refine the plan or suggest alternatives. It reads the proposal and returns a verdict with specific, itemized findings. No stake in the outcome. No relationship to protect.

**Cost to run: ~$0.05. Cost of skipping: a rework cycle.**

---

## When to Run

| Condition | Action |
|---|---|
| New API endpoint or route | Run |
| Schema change (DB table, migration) | Run |
| Payment or charge flow touched | Run |
| Auth logic touched | Run |
| Feature touching >3 files | Run |
| New external API integration | Run |
| Any decision being pitched with confidence | Run |
| Copy/style-only change, <3 files, no logic | Skip |
| Isolated bug fix, no payment/auth touch | Skip |

**When in doubt: run it.** The gate costs a fraction of a rework cycle.

---

## How to Run

```bash
# 1. Write a DONE_WHEN brief
cat > /tmp/brief.md << 'EOF'
Goal: <what this build accomplishes>
Scope: <what files/systems are touched>
Done when: <specific acceptance criteria>
EOF

# 2. Run the critic
bash ~/.openclaw/workspace/skills/architecture-critic/scripts/run-critic.sh \
  --task "Brief description of the build" \
  --done-when /tmp/brief.md \
  --repo /path/to/your/repo
```

Or let your agent run it automatically — see the **Agent Integration** section below.

---

## Verdicts

| Verdict | Meaning | Action |
|---|---|---|
| `APPROVE` | Plan is sound. No blocking issues found. | Proceed to build. |
| `REVISE` | Specific problems identified. | Fix findings, re-run. Max 2 cycles, then escalate. |
| `REJECT` | Fundamental flaw in approach. | Stop. Redesign. Do not build. |

Verdicts are saved to `specialists/critic-verdicts/YYYY-MM-DD-<slug>.md` in your workspace.

---

## Agent Integration

Add this to your `AGENTS.md` or agent instructions:

```markdown
## Architecture Critic — MANDATORY GATE
Before any significant build (new endpoint, schema change, payment/auth touch, >3 files):
1. Write the DONE_WHEN brief to a temp file
2. Run: bash ~/.openclaw/workspace/skills/architecture-critic/scripts/run-critic.sh \
        --task "<description>" --done-when <file> [--repo <path>]
3. APPROVE → proceed
4. REVISE → fix findings, re-run (max 2 cycles)
5. REJECT → stop, escalate to human

Skip only for: copy/style-only changes <3 files no logic, isolated bug fixes no payment/auth.
```

---

## How It Works

The critic script:
1. Snapshots the relevant codebase state (file tree + key files)
2. Combines it with your DONE_WHEN brief into a structured prompt
3. Spawns an isolated agent at temperature 0 — no creativity, no encouragement
4. The agent runs the checklist against your plan
5. Returns a verdict with specific, itemized findings
6. Saves the verdict to your workspace

The critic agent never sees your conversation history, your enthusiasm, or the proposer's reasoning. It sees only the spec and the code.

---

## LLM Compatibility

Works with any LLM configured in your OpenClaw instance:
- Anthropic (Claude Sonnet, Haiku)
- OpenAI (GPT-4o, GPT-4 Turbo)
- Google (Gemini)
- Local models via Ollama

The script reads your OpenClaw config to find the active model and API key. No separate configuration required.

---

## Checklist Coverage

The critic reviews against domain-specific checklists:

- **Web** (`references/checklist-web.md`) — routes, caching, deployment config, breaking changes
- **Security** (`references/security.md`) — auth bypass, injection, secrets, CORS, OWASP Top 10
- **Payment flows** (`references/payment-flows.md`) — webhooks, idempotency, race conditions, PCI scope
- **AI builds** (`references/ai-builds.md`) — prompt injection, hot paths, token costs, fallback handling
- **General** (`references/checklist-general.md`) — scope creep, dependencies, rollback, data migration

Pass `--checklist references/security.md` to focus on a specific domain, or let the critic auto-select based on your brief.

---

## Files

```
architecture-critic/
├── SKILL.md                      # This file
├── README.md                     # GitHub-facing docs
├── LICENSE                       # MIT
├── scripts/
│   └── run-critic.sh             # Main runner script
└── references/
    ├── checklist-web.md          # Web/API checklist
    ├── checklist-general.md      # General architecture checklist
    ├── security.md               # Security checklist
    ├── payment-flows.md          # Payment/billing checklist
    └── ai-builds.md              # AI/LLM-specific checklist
```
