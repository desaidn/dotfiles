---
status: accepted
---

# Split the agent workflow into rules and skills

Keep `docs/agents/development-workflow.md` as the always-loaded global instruction file, but reduce it to rules that apply to every task: scope, communication, evidence, checkout safety, append-only WIP, review identity, explicit approval, landing, and on-request delivery and adversarial review. Move the step-by-step procedures into global skills in the Agent Skills format under `docs/agents/skills/`: `development-review` for snapshot identity, opening and verifying Hunk reviews, findings, adversarial review, landing, and delivery; and `herdr-app` for operating Herdr app and herdr-core. The installer links each skill into `~/.agents/skills/` for Codex and pi and `~/.claude/skills/` for Claude Code, with the same protected-destination and conservative-uninstall rules as the instruction files.

ADR 0015 rejected a workflow skill because automatic context loading must not depend on skill selection. That remains true for rules, so every rule stays in the always-loaded file, which also names each skill and the step that requires it, and tells agents to stop rather than improvise when a required skill is unavailable. Procedures are needed only at particular steps, and loading about 21 KB of them into every session in every project cost more than it protected. A skipped skill now produces a visibly incomplete review rather than an unapproved landing.

The review, findings, approval, and landing procedure is the same on every machine. Delivery is the only step that varies: it is chosen from the user's request, then project instructions, then instructions installed on the machine, then a GitHub remote, and otherwise ends at local landing. Delivery submits the landed squash commit instead of preparing a separate local submission branch; a GitHub pull request uses a remote `review/<feature>` branch, while the local Review Branch keeps marking the approved snapshot. The shared workflow and skills name no employer-internal tools, services, or hosts; machine-installed instructions supply those. Bundled upstream guides such as `hunk skill show hunk-review`, `hc --skill`, `herdr-app --skill`, and `herdr --skill` are referenced rather than copied.

This amends ADR 0015's packaging decision. Its approval, evidence, and installation-safety decisions remain.
