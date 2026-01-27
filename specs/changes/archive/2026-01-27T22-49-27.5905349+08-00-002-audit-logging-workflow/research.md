# Research: Workflow audit logging

**Feature**: 002-audit-logging-workflow
**Date**: 2026-01-26
**Spec**: spec.md

---

# # Research Summary

| Topic | Decision | Confidence |
|-------|----------|------------|
| Audit log storage and format | Append JSON Lines entries to `specs/logs/workflow-audit.jsonl` with a schema version field | High |
| Concurrent write strategy | Use `System.IO.FileStream` append with exclusive writer lock and retry/backoff | Medium |
| Error redaction policy | Allowlist fields and redact token-like patterns; cap error summaries to 500 characters | Medium |
| Retention and security assumptions | Retain logs in repo/archives for 12 months; private repo with sanitized entries | Medium |
| Placeholder success criteria values | Set concurrency target to 5 parallel scripts and user success targets to 90% first-attempt | Medium |

---

# # Detailed Findings

## # Audit log storage and format

**Question**: Where should workflow audit entries live and what schema ensures traceability while remaining file-based?

**Decision**: Store append-only JSON Lines entries in `specs/logs/workflow-audit.jsonl`. Each entry includes `schema_version`, ISO 8601 `timestamp`, `script_name`, `action`, `change_id` (nullable), `outcome`, and optional `error_summary`/`error_type`.

**Rationale**: The SpecKit constitution mandates JSONL audit logs in `specs/logs/`. JSON Lines allows streaming append without locking the entire file and preserves machine-readable structure.

**Alternatives Considered**:
- CSV log: rejected because nested error details and optional fields are awkward to encode.
- Markdown log: rejected because parsing is brittle and not automation-friendly.
- External logging service: rejected due to added dependency and conflict with file-based truth.

**Sources**:
- SpecKit Constitution VI: Workflow Audit Logging.

---

## # Concurrent write strategy

**Question**: How do we safely append entries when multiple workflow scripts run concurrently?

**Decision**: Use `System.IO.FileStream` with `FileMode.Append`, `FileAccess.Write`, and `FileShare.Read`, wrapped in retry/backoff (e.g., 3 attempts, 50ms → 200ms). Write via `StreamWriter` using UTF-8 without BOM.

**Rationale**: FileStream append provides atomic append semantics with an exclusive writer lock while still allowing readers. Retry handles short-lived contention without external synchronization.

**Alternatives Considered**:
- `Add-Content` without locking: rejected due to higher risk of interleaved writes.
- Mutex/lock file: rejected for complexity and cross-platform friction.

**Sources**:
- .NET `System.IO.FileStream` append semantics documentation.
- PowerShell file I/O guidance for streaming writes.

---

## # Error redaction policy

**Question**: How can audit entries record failures without leaking sensitive data?

**Decision**: Log only a sanitized `error_summary` and `error_type`. Apply regex redaction for token/secret patterns and truncate summaries to 500 characters. Avoid stack traces or raw exception text.

**Rationale**: A narrow, sanitized payload satisfies compliance requirements and aligns with the constitution’s “no sensitive data” principle while still supporting troubleshooting.

**Alternatives Considered**:
- Full exception logging: rejected due to secret leakage risk.
- No error details: rejected because it hampers troubleshooting.

**Sources**:
- SpecKit Constitution VI: Workflow Audit Logging.
- OWASP logging guidance for sensitive data redaction.

---

## # Retention and security assumptions

**Question**: What retention and storage policy should satisfy compliance assumptions?

**Decision**: Retain `workflow-audit.jsonl` in the repository and archives for at least 12 months. Store logs only in private repos and perform an annual retention verification by release management.

**Rationale**: The existing archive workflow already maintains immutable records; extending retention to 12 months requires no new infrastructure.

**Alternatives Considered**:
- External storage (SIEM): rejected to avoid new dependencies and credentials.

**Sources**:
- Spec assumptions in `spec.md`.
- SpecKit dual-state model and archive workflow.

---

## # Placeholder success criteria values

**Question**: What concrete values replace placeholder success criteria in the spec?

**Decision**: Target support for 5 concurrent workflow script executions without audit log write failures or >10% runtime regression. Maintain 90% first-attempt success for locating audit trails and fewer than 1 audit-related ticket per quarter.

**Rationale**: These values align with existing success criteria while staying realistic for a file-based workflow system.

**Alternatives Considered**:
- Higher concurrency targets: rejected until load testing data is available.

**Sources**:
- Current success criteria in `spec.md`.

---

# # Resolved Items

| Original | Resolution |
|----------|------------|
| `{NEEDS_VALIDATION_CONFIRM_SECURITY_REVIEW}` | Assume sanitized audit logs stored in private repo; compliance review required before rollout. |
| `{NEEDS_VALIDATION_CONFIRM_RETENTION_POLICY}` | Retain audit logs for 12 months in repo + archive; verify annually. |
| `{SYSTEM_HANDLES_N_CONCURRENT_USERS_WITHOUT_DEGRADAT}` | Set target to 5 concurrent workflow scripts without log contention or >10% runtime increase. |
| `{X_OF_USERS_COMPLETE_TASK_ON_FIRST_ATTEMPT}` | Set user success target to 90% first-attempt audit trace completion. |
| `{SUPPORT_TICKETS_RELATED_TO_THIS_FEATURE_BELOW_N_PE}` | Set target to <1 audit-log-related ticket per quarter. |

---

# # Remaining Unknowns

None.





