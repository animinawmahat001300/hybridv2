---
change_id: "main"
author: "viellaLatbe"
date: "2026-01-27T09:32:12.4426608+08:00"
status: "proposed"
---

# Proposal: Workflow audit logging for scripts

## Why



### Pain Points - 100% of workflow script state-changing actions produce an audit entry with required fields, measurable by audit log review across sampled runs. - 100% of workflow script failures produce a failure audit entry before exit, measurable by reviewing failure logs from scripted tests. - 95% of audit entries are visible in the audit log within 5 seconds of action completion. - Audit logging increases workflow script runtime by no more than 10% in comparative runs. - Audit append latency p95 is ≤ 50 ms under the standard workload profile. - 90% of workflow maintainers can locate a specific script outcome in under 2 minutes during a review exercise. - Support requests related to missing audit entries remain at or below 1 per quarter after rollout. - Quarterly compliance reviews report zero missing audit entries for audited workflow runs.

## What

This plan implements workflow audit entries for state-changing scripts using a shared PowerShell logging helper that appends JSONL records to
`specs/logs/workflow-audit.jsonl`. It delivers append-only, sanitized audit history for compliance reviews and failure troubleshooting.

---

## Impact

### Benefits
- 100% of workflow script state-changing actions produce an audit entry with required fields, measurable by audit log review across sampled runs. - 100% of workflow script failures produce a failure audit entry before exit, measurable by reviewing failure logs from scripted tests. - 95% of audit entries are visible in the audit log within 5 seconds of action completion. - Audit logging increases workflow script runtime by no more than 10% in comparative runs. - Audit append latency p95 is ≤ 50 ms under the standard workload profile. - 90% of workflow maintainers can locate a specific script outcome in under 2 minutes during a review exercise. - Support requests related to missing audit entries remain at or below 1 per quarter after rollout. - Quarterly compliance reviews report zero missing audit entries for audited workflow runs.

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
