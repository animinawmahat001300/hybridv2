# Data Model: gitless-workflow-resilience

**Feature**: 004-gitless-workflow-resilience
**Date**: 2026-01-27

---

# # Entity Overview

| Entity | Description | Storage |
|--------|-------------|---------|
| WorkspaceSnapshot | Captures workspace state at archive time with file metadata and optional Git status | File system (`workspace-snapshot.json`) |
| WorkflowExecutionContext | Resolved execution metadata for a workflow script run | In-memory + serialized to script output JSON |

---

# # Entity Definitions

## # WorkspaceSnapshot

**Purpose**: Persist evidence of modified and untracked files at archive time without storing file contents.

**Fields**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| schema_version | integer | Required | Snapshot schema version for compatibility |
| captured_at | string (date-time) | Required | Capture timestamp in ISO 8601 |
| change_id | string | Required | Active change identifier |
| workspace_root | string | Required | Absolute path of workspace root |
| git_available | boolean | Required | Whether Git metadata was available |
| git_status | object | Optional | Git status summary when Git is available |
| modified_files | array | Required | List of modified file metadata entries |
| untracked_files | array | Required | List of untracked file metadata entries |
| notes | string | Optional | Warning or context notes (e.g., snapshot captured with dirty workspace) |

**Relationships**:
- WorkspaceSnapshot references WorkflowExecutionContext via `change_id` and `workspace_root`.

**Indexes**:
- None (file-based storage; lookup by archive folder path).

**Validation Rules**:
- `schema_version` must be a positive integer.
- `modified_files` and `untracked_files` must include `path` for each entry.

## # WorkflowExecutionContext

**Purpose**: Record runtime resolution of change ID, repo root, and verbosity profile for a script run.

**Fields**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| execution_id | string (uuid) | Required | Unique run identifier |
| change_id | string | Required | Resolved change ID used by scripts |
| repo_root | string | Required | Resolved repository or workspace root |
| git_available | boolean | Required | Whether Git is usable for this run |
| verbosity_mode | string | Required | `summary` or `verbose` |
| started_at | string (date-time) | Required | Script start time |

**Relationships**:
- WorkflowExecutionContext may emit a WorkspaceSnapshot on archive.

**Indexes**:
- None (runtime structure only; persisted in output JSON when needed).

**Validation Rules**:
- `verbosity_mode` must be `summary` or `verbose`.

---

# # State Diagrams

No lifecycle state diagrams are required; entities are captured as immutable records per run.

---

# # Migration Notes

- Increment `schema_version` if snapshot schema changes; maintain backward-compatible readers.
- No database migrations required due to file-based storage.




