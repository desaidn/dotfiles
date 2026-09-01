---
status: amended by ADR-0013
---

# Bind review approval to WIP snapshots

A Review Snapshot points to the exact WIP Branch revision instead of containing a synthetic squash commit, and Review Approval binds to that WIP revision rather than freezing its `main` base. Before a snapshot is created, current `main` must already be an ancestor of WIP through normal development history or an explicit Main Merge; `main` may then advance during or after review. Landing applies the approved snapshot to the explicitly selected current Mainline Branch and validates the resulting Landing Candidate. If integration requires changing WIP, those changes are appended as commits and a new snapshot must be reviewed. This avoids fabricated review history and serializing unrelated work on `main` while keeping approval tied to an exact feature state.
