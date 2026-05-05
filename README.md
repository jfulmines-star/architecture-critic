# Architecture Critic

> Your AI won't tell you what's wrong. We will.

An adversarial pre-build review skill for [OpenClaw](https://openclaw.ai). Spawns a structurally independent agent that reviews your proposed build **before you write a single line of code**.

The critic sees only your spec and codebase state — never your conversation history, your enthusiasm, or your reasoning. Its sole job is to find what's wrong.

```
~$0.05 per review. One rework cycle avoided = hours saved.
```

---

## Quick Start

```bash
# Install
openclaw skills install architecture-critic

# Write a brief
cat > /tmp/brief.md << 'EOF'
Goal: Add Stripe checkout to the pricing page
Scope: app/api/checkout/route.ts, app/pricing/page.tsx, lib/stripe.ts
Done when: user can complete a subscription purchase end-to-end in staging
EOF

# Run the critic
bash ~/.openclaw/workspace/skills/architecture-critic/scripts/run-critic.sh \
  --task "Add Stripe checkout to pricing page" \
  --done-when /tmp/brief.md \
  --repo /path/to/your/repo
```

That's it. The critic runs, returns a verdict, and saves it to your workspace.

---

## How It Works

```
You write a brief
       │
       ▼
  Codebase snapshot
  (file tree + key files)
       │
       ▼
  ┌─────────────────────────────┐
  │   CRITIC AGENT (temp=0)     │
  │   No history. No context.   │
  │   No stake in the outcome.  │
  └─────────────────────────────┘
       │
       ▼
  ┌────────────┐  ┌────────────┐  ┌────────────┐
  │  APPROVE   │  │   REVISE   │  │   REJECT   │
  │            │  │            │  │            │
  │ Plan is    │  │ Specific   │  │ Fundament- │
  │ sound.     │  │ problems.  │  │ al flaw.   │
  │ Build it.  │  │ Fix them.  │  │ Stop.      │
  └────────────┘  └────────────┘  └────────────┘
```

---

## The Three Verdicts

**APPROVE** — No blocking issues found. The plan is architecturally sound against the applicable checklists. Proceed to build.

**REVISE** — Specific problems identified with enough detail to fix. Address each finding and re-run. Maximum 2 revision cycles before escalating to a human.

**REJECT** — Fundamental flaw in the approach. The plan should not be built as specified. Stop, redesign, and start a new brief.

---

## Example Verdict

```
VERDICT: REVISE

FINDING-1 [BLOCKING] — SCOPE VIOLATION
This endpoint touches the Stripe charge flow but the brief makes no mention of
webhook handling or idempotency. A charge can be initiated but if the webhook
fails, the subscription state will be inconsistent. Add webhook handler + 
idempotency keys to scope, or reduce scope to exclude charge creation entirely.

FINDING-2 [BLOCKING] — MISSING FALLBACK
The plan calls an external enrichment API on the hot path (user registration).
No mention of timeout, retry logic, or graceful degradation if the API is
unavailable. A 3rd-party outage will break user signup. Either move this call
async or add explicit fallback behavior to the brief.

FINDING-3 [WARN] — SACRED FILE RISK
vercel.json is referenced in scope. This file controls production routing.
Changes here have broken deployments before. Confirm the exact diff before
proceeding and smoke-test root route after every deploy.

ACTION: Fix FINDING-1 and FINDING-2 before proceeding. FINDING-3 is advisory.
```

---

## Agent Integration

Add to your `AGENTS.md`:

```markdown
## Architecture Critic — MANDATORY GATE
Before any build (new endpoint, schema change, payment/auth touch, >3 files):
1. Write DONE_WHEN brief to temp file
2. Run: bash ~/.openclaw/workspace/skills/architecture-critic/scripts/run-critic.sh \
        --task "<description>" --done-when <file>
3. APPROVE → proceed | REVISE → fix + re-run | REJECT → stop, escalate
Skip only: copy/style <3 files no logic, isolated bug fix no payment/auth
```

---

## LLM Compatibility

Works with any LLM in your OpenClaw config — Claude, GPT-4o, Gemini, or local Ollama models. No separate API key configuration required.

---

## Checklist Coverage

| Domain | File | Covers |
|---|---|---|
| Web/API | `references/checklist-web.md` | Routes, caching, deployment config, breaking changes |
| Security | `references/security.md` | Auth bypass, injection, secrets, CORS, OWASP Top 10 |
| Payments | `references/payment-flows.md` | Webhooks, idempotency, race conditions, PCI |
| AI Builds | `references/ai-builds.md` | Prompt injection, hot paths, token costs, fallback |
| General | `references/checklist-general.md` | Scope, dependencies, rollback, data migration |

---

## Why This Exists

AI agents are trained to be helpful. Helpful means agreeable. Agreeable means the agent will find reasons your bad idea is good — it will generate enthusiasm, suggest refinements, and start building.

The Critic has no stake in the outcome. No relationship to protect. No prior context that makes the plan feel reasonable. It reads the spec cold, runs it against a checklist, and returns findings.

The adversarial framing is the point.

---

## License

MIT — see [LICENSE](LICENSE)

Built in production by AxiomStream Group. Running since April 2026.
