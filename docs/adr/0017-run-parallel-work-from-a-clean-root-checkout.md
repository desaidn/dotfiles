---
status: accepted
---

# Run parallel work from a clean root checkout

Parallel agent work follows one layout. The root checkout stays clean on the mainline branch as home base for the person or a manager agent. Each idea or workstream gets its own worktree, its own `wip/` branch, and, in Herdr app, its own space. The procedure lives in a global `parallel-worktrees` skill, loaded when work is split this way, alongside `development-review` and `herdr-app` (see ADR 0016). Where worktrees live stays a project decision; the skill asks the person when the project's instructions are silent.

There are two modes. Independent ideas have no manager and land separately. A coordinated feature has a manager that owns a canonical `wip/<feature>` branch in its own integration worktree, into which every worker's `wip/<feature>-<area>` workstream branch merges. A first draft treated each worker's branch as the unit that is reviewed and landed. A manager who had run a large feature this way reported that the two split apart in practice: workers own areas, while reviewers need small stacked changes in reading order, so one area spread across several reviews. The skill therefore separates workstreams from review pieces and lets the manager choose either to review each workstream or to cut stacked review pieces from the canonical branch, checking that the top piece's tree equals the canonical tree. Source changes needed only to deploy to one environment form an environment overlay. It never enters a reviewable branch and meets code only in a disposable deploy checkout, so that tree check stays exact. The skill asks the manager to weigh upstreaming a small hook first, because an overlay that duplicated hooks across environments and carried unrelated changes caused most of the deploy friction.

Before the first review piece goes out, the whole feature is validated on the canonical branch and each piece is validated on the target plus the pieces below it. Later changes may use scoped reruns with a recorded reason, because full deployed runs were too slow to repeat for every fix; a full run is required again before handover.

Agents in a group find each other with `hc` labels (`group`, `role`, `piece`) rather than terminal IDs. Reports were lost twice: once to a manager's old ID after it restarted, and once because a worker kept the ID from its first brief. The manager relabels itself each session, and workers look it up by label each time they report. Workers use their harness's configured default model unless the person names one, so model changes need only a configuration change. Because agents compact their own context, the lasting risk is a restart rather than a full context; the manager writes a handoff note before one.

Cleanup lists harvestable documents, worktrees, deploy checkouts, overlay branches, agent-started terminals, and spaces for the person to approve. Agents never delete WIP or Review Branches, consistent with the append-only rule.
