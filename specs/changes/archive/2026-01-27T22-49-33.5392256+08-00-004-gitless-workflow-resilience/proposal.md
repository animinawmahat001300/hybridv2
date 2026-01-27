---
change_id: "004-gitless-workflow-resilience"
author: "viellaLatbe"
date: "2026-01-27T22:49:35.9864528+08:00"
status: "proposed"
---

# Proposal: gitless-workflow-resilience

## Why



### Pain Points - `check-prerequisites.ps1` passes in a workspace without Git. - Archive succeeds with uncommitted changes and records `workspace-snapshot.json`. - Default output stays within 30 lines for standard runs. - Snapshot metadata capture p95 is ≤ 200 ms for 10k files. - Audit append p95 is ≤ 50 ms during gitless execution.

## What

This plan implements gitless workflow execution, archive snapshots for dirty workspaces, and concise default logging using file-based change resolution, snapshot capture, and verbosity gating to deliver resilient workflows in non-Git environments.

---

## Impact

### Benefits
- `check-prerequisites.ps1` passes in a workspace without Git. - Archive succeeds with uncommitted changes and records `workspace-snapshot.json`. - Default output stays within 30 lines for standard runs. - Snapshot metadata capture p95 is ≤ 200 ms for 10k files. - Audit append p95 is ≤ 50 ms during gitless execution.

### Risks
No critical risks identified.

### Dependencies
- PowerShell 7+ - Git (optional)

### Affected Components
| Component | Change Type | Notes |
|-----------|-------------|-------|


## Delta Summary

| Operation | Count |
|-----------|-------|
| ADDED | 0 |
| MODIFIED | 0 |
| REMOVED | 0 |
| RENAMED | 0 |
| **Total** | **0** |

### File Changes


## Approval

- [ ] Technical review complete
- [ ] Stakeholder sign-off
- [ ] Ready for implementation
