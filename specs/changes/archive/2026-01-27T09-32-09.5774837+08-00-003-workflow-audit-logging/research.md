# Research: Workflow audit logging for scripts

**Feature**: 003-workflow-audit-logging
**Date**: 2026-01-27
**Spec**: spec.md

---

# # Research Summary

| Topic | Decision | Confidence |
|-------|----------|------------|
| Audit log format | Use JSONL append-only file at `specs/logs/workflow-audit.jsonl` | High |
| Concurrency handling | Append with retry and log failures before exit | Medium |
| Error sanitization | Record sanitized error summaries with allowlisted fields only | High |

---

# # Detailed Findings

## # Audit log format

**Question**: What storage format best satisfies governance and auditability requirements?

**Decision**: Use JSONL entries in `specs/logs/workflow-audit.jsonl`, appending one entry per action.

**Rationale**: The constitution mandates JSONL with append-only semantics, and JSONL supports streaming writes and easy inspection.

**Alternatives Considered**:
- CSV: rejected because nested fields and error summaries become ambiguous.
- SQLite: rejected due to new runtime dependency and increased complexity.

**Sources**:
- `specs/memory/constitution.md`
- `specs/project.md`

---

## # Concurrency handling

**Question**: How should concurrent workflow scripts append to the audit log safely?

**Decision**: Use atomic append operations with retry/backoff and log a failure entry if retries exhaust.

**Rationale**: Atomic append operations in PowerShell avoid truncation and keep existing entries intact while respecting the append-only rule.

**Alternatives Considered**:
- Central lock file: rejected because it introduces deadlock risk without strong guarantees.
- External log service: rejected due to the no-external-dependencies constraint.

**Sources**:
- `specs/memory/constitution.md`
- PowerShell file IO guidance in .NET `System.IO.File` documentation

---

## # Error sanitization

**Question**: What error data can be stored without exposing sensitive values?

**Decision**: Store only exception type, a sanitized message, and a redacted summary string limited to a fixed length.

**Rationale**: It preserves failure context while minimizing accidental exposure of secrets or file contents.

**Alternatives Considered**:
- Full stack traces: rejected because they can leak file paths and secrets.
- Raw error records: rejected due to inconsistent serialization and sensitive data risk.

**Sources**:
- `specs/memory/constitution.md`
- `specs/project.md`

---

# # Resolved Items

| Original | Resolution |
|----------|------------|
| No explicit research markers in spec.md | Documented decisions for format, concurrency, and sanitization to guide implementation |

---

# # Remaining Unknowns

None.





