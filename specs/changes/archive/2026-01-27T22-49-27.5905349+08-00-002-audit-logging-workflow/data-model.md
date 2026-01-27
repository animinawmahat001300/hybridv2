# Data Model: Workflow audit logging

**Feature**: 002-audit-logging-workflow
**Date**: 2026-01-26

---

# # Entity Overview

| Entity | Description | Storage |
|--------|-------------|---------|
| AuditLogEntry | Immutable record of workflow actions and outcomes | JSON Lines file `specs/logs/workflow-audit.jsonl` |

---

# # Entity Definitions

## # AuditLogEntry

**Purpose**: Capture a non-sensitive, structured audit trail for workflow scripts that create, validate, or archive changes.

**Fields**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| schema_version | integer | NOT NULL, default 1 | Log schema version for backward compatibility |
| timestamp | string | NOT NULL, ISO 8601 | Time the action completed |
| script_name | string | NOT NULL, max 120 chars | Workflow script name |
| action | string | NOT NULL, enum: create, update, validate, archive, system | Action executed by the script |
| change_id | string | nullable, pattern `^\d{3}-[a-z0-9-]+$` | Change identifier (nullable for system actions) |
| outcome | string | NOT NULL, enum: success, failure | Result of the action |
| error_summary | string | nullable, max 500 chars | Sanitized failure summary |
| error_type | string | nullable, max 120 chars | High-level error classification |
| duration_ms | integer | nullable, min 0 | Duration of the action in milliseconds |
| execution_id | string | nullable, GUID format | Correlation id for the script run |
| host | string | nullable, max 120 chars | Execution host or runner name |

**Relationships**:
- None (append-only log entries are independent).

**Indexes**:
- N/A (append-only JSONL file; filtering occurs at read time).

**Validation Rules**:
- `timestamp` must be ISO 8601 and represent UTC or include offset.
- `outcome` must be `success` or `failure`.
- `action` must match the workflow action type.
- `change_id` is required for change-scoped actions and omitted for system maintenance actions.
- `error_summary` is required only when `outcome` is `failure` and must be redacted.

---

# # State Diagrams

Audit entries are immutable once appended; no lifecycle states apply.

---

# # Migration Notes

- Use `schema_version` to manage additive schema updates.
- New fields must be optional to preserve backward compatibility with existing log parsers.
- Any future migration should include a reader that tolerates missing fields.




