# Data Model: Workflow audit logging for scripts

**Feature**: 003-workflow-audit-logging
**Date**: 2026-01-27

---

# # Entity Overview

| Entity | Description | Storage |
|--------|-------------|---------|
| WorkflowAuditEntry | Immutable audit record for a single state-changing action | `specs/logs/workflow-audit.jsonl` |
| WorkflowScriptRun | Logical grouping of audit entries for one script execution | Derived from audit entries |

---

# # Entity Definitions

## # WorkflowAuditEntry

**Purpose**: Capture a single workflow script action and its outcome for append-only audit history.

**Fields**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| timestamp | string (ISO 8601) | NOT NULL | Time the action completed |
| script_name | string | NOT NULL | Name of the workflow script |
| action | string | NOT NULL | Action label (create, validate, archive, etc.) |
| change_id | string | NULLABLE | Change identifier when applicable |
| outcome | string | NOT NULL, enum: success, failure | Result of the action |
| error_summary | string | NULLABLE, max 512 chars | Sanitized error summary for failures |
| run_id | string | NULLABLE | Correlation identifier for a script run |
| duration_ms | integer | NULLABLE, >= 0 | Action duration in milliseconds |

**Relationships**:
- Belongs to WorkflowScriptRun (optional, via run_id).

**Indexes**:
- Logical index by timestamp (file order) and change_id for filtering.

**Validation Rules**:
- timestamp must be valid ISO 8601.
- outcome must be `success` or `failure`.
- error_summary must be sanitized and length-limited.

---

## # WorkflowScriptRun

**Purpose**: Represent a single workflow execution to correlate multiple audit entries.

**Fields**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| run_id | string | NOT NULL, unique | Identifier for the script run |
| script_name | string | NOT NULL | Script associated with the run |
| started_at | string (ISO 8601) | NOT NULL | Start timestamp |
| finished_at | string (ISO 8601) | NULLABLE | End timestamp |
| outcome | string | NULLABLE, enum: success, failure | Aggregate outcome |
| entry_count | integer | NULLABLE, >= 0 | Number of audit entries recorded |

**Relationships**:
- Has many WorkflowAuditEntry records.

**Indexes**:
- Logical index by run_id for correlating entries.

**Validation Rules**:
- run_id must be stable for a single script execution.
- finished_at must be greater than or equal to started_at.

---

# # State Diagrams

WorkflowAuditEntry is immutable once written. WorkflowScriptRun transitions from Started → Completed or Started → Failed based on outcome.

---

# # Migration Notes

No database migrations are required. Schema evolution should add new optional fields and maintain backward compatibility with existing JSONL entries.




