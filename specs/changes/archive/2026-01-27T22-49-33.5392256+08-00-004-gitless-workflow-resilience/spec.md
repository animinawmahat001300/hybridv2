# Feature Specification: gitless-workflow-resilience

**Feature Branch**: `004-gitless-workflow-resilience`  
**Created**: 2026-01-27  
**Status**: Draft  
**Input**: User description: "Make workflow scripts run without git; capture workspace state for archive; allow archive with uncommitted changes; reduce verbosity."

## # Overview

Enable SpecKit workflows to run without Git, archive with dirty workspaces by capturing a snapshot, and reduce default output verbosity while preserving detailed logs in verbose mode.

## # User Story 1 - Run workflows without Git (Priority: P1)

As a workflow operator, I want all SpecKit scripts to run when Git is missing so I can execute phases in non‑git environments.

**Why this priority**: Without Gitless support, the workflow cannot start in many local or sandbox environments.

**Independent Test**: Run a workflow script in a folder without `.git` and confirm it completes using file-based change resolution.

**Acceptance Scenarios**:

### # Scenario: Happy Path
- **WHEN** a workflow script runs in a workspace without Git
- **THEN** it completes using file-based change resolution and does not require branch checks

### # Scenario: Alternate Success
- **WHEN** Git exists and is healthy
- **THEN** the script behaves as it does today

### # Scenario: Error Handling
- **WHEN** the workspace root cannot be resolved
- **THEN** the script exits non-zero and the message includes the missing path and a next action

---

## # User Story 2 - Archive with uncommitted changes (Priority: P2)

As a maintainer, I want archives to succeed even when the workspace is dirty so I can preserve work in progress with evidence.

**Why this priority**: Blocked archives force manual cleanup and lose traceability of local state.

**Independent Test**: Run archive with modified and untracked files and verify the archive contains a snapshot of workspace state.

**Acceptance Scenarios**:

### # Scenario: Happy Path
- **WHEN** archive runs with uncommitted changes
- **THEN** the archive completes and includes a workspace snapshot

### # Scenario: Error Handling
- **WHEN** the snapshot cannot be written
- **THEN** the archive fails and preserves the active change folder

---

## # User Story 3 - Reduce default verbosity (Priority: P3)

As a user, I want default output to be concise so I can see the key results quickly.

**Why this priority**: Excess output hides actionable signals.

**Independent Test**: Run a script in default mode and verify it prints only phase summaries and warnings.

**Acceptance Scenarios**:

### # Scenario: Happy Path
- **WHEN** a script runs in default mode
- **THEN** it prints a short phase summary and warnings only

### # Scenario: Alternate Success
- **WHEN** a script runs with verbose logging enabled
- **THEN** it prints detailed progress output

---

## # Edge Cases

- **Missing repo root**: Script exits non-zero with recovery guidance.
- **Only untracked files**: Snapshot still records file list.
- **Read-only snapshot path**: Archive fails with a clear message.
- **Very large workspace**: Snapshot uses summarized file metadata, not full contents.
- **Multiple change folders**: Without `SPECIFY_CHANGE_ID`, the script fails and asks for an explicit change ID.

---

# # Requirements *(mandatory)*

## # Requirement: REQ-001 Gitless workflow execution

**Source**: US1

WHEN Git is unavailable or `.git` is missing  
THE SYSTEM SHALL run workflow scripts using file-based change resolution and SHALL NOT require a feature branch.

### # Scenario: Verify Requirement
- **WHEN** `check-prerequisites.ps1` runs without Git
- **THEN** it returns success with file-based paths and no branch failure

---

## # Requirement: REQ-002 Change ID resolution without Git

**Source**: US1

WHEN a change ID is required and Git is unavailable  
THE SYSTEM SHALL resolve it from `SPECIFY_CHANGE_ID` or the active `specs/changes/<change-id>` directory name.

### # Scenario: Verify Requirement
- **WHEN** `SPECIFY_CHANGE_ID` is set
- **THEN** the resolved change ID equals the environment value

---

## # Requirement: REQ-003 Archive workspace snapshot

**Source**: US2

WHEN an archive is executed  
THE SYSTEM SHALL write `workspace-snapshot.json` inside the archive folder capturing modified/untracked file paths and, when available, Git metadata fields: `branch`, `is_dirty`, `status_summary`.

### # Scenario: Verify Requirement
- **WHEN** archive completes
- **THEN** the archive contains `workspace-snapshot.json`

---

## # Requirement: REQ-004 Allow archive with dirty workspace

**Source**: US2

WHEN uncommitted changes exist  
THE SYSTEM SHALL allow archive execution and SHALL emit a warning that a snapshot was captured.

### # Scenario: Verify Requirement
- **WHEN** the workspace is dirty
- **THEN** archive succeeds and reports the snapshot warning

---

## # Requirement: REQ-005 Snapshot failure behavior

**Source**: US2

WHEN the snapshot cannot be written  
THE SYSTEM MUST fail the archive and leave the active change folder intact.

### # Scenario: Verify Requirement
- **WHEN** snapshot write fails
- **THEN** the archive does not move the change folder

---

## # Requirement: REQ-006 Default verbosity limits

**Source**: US3

WHEN a script runs in default mode  
THE SYSTEM SHALL output only phase start/end summaries and warnings (≤ 30 lines per run).

### # Scenario: Verify Requirement
- **WHEN** a script runs without `-Verbose`
- **THEN** output is limited to summaries and warnings

---

## # Requirement: REQ-007 Verbose mode details
**Source**: US3

WHEN verbose mode is enabled  
THE SYSTEM SHALL include detailed progress output for each major step.

### # Scenario: Verify Requirement
- **WHEN** `-Verbose` is supplied
- **THEN** detailed step output is visible

---

## # Requirement: REQ-008 Multiple change folder behavior

**Source**: US1

WHEN multiple `specs/changes/<change-id>` folders exist and `SPECIFY_CHANGE_ID` is not set  
THE SYSTEM MUST stop and emit a message that requires an explicit change ID.

### # Scenario: Verify Requirement
- **WHEN** two change folders exist and `SPECIFY_CHANGE_ID` is empty
- **THEN** the script exits non-zero with a prompt to set `SPECIFY_CHANGE_ID`

---

## # Requirement: REQ-009 Audit logging for gitless behaviors

**Source**: US1, US2

WHEN a gitless fallback or workspace snapshot is used  
THE SYSTEM SHALL emit a workflow audit entry describing the fallback or snapshot action.

### # Scenario: Verify Requirement
- **WHEN** archive captures a snapshot
- **THEN** an audit entry records the snapshot action and outcome

---

## # Requirement: REQ-010 Snapshot performance

**Source**: US2

WHEN writing `workspace-snapshot.json` for a 10k-file workspace  
THE SYSTEM SHALL complete metadata capture within 200 ms at p95.

### # Scenario: Verify Requirement
- **WHEN** snapshot capture is benchmarked on a 10k-file workspace
- **THEN** p95 write time is ≤ 200 ms

---

## # Requirement: REQ-011 Audit append performance

**Source**: Governance

WHEN audit entries are appended during gitless workflows  
THE SYSTEM SHALL keep audit append latency at or below 50 ms at p95.

### # Scenario: Verify Requirement
- **WHEN** audit appends are sampled during gitless execution
- **THEN** p95 append latency is ≤ 50 ms

---

## # Requirement: REQ-012 Documentation and contract alignment

**Source**: Governance

WHEN workflow behavior changes are implemented  
THE SYSTEM SHALL update workflow contracts and documentation to match actual JSON output and user guidance.

### # Scenario: Verify Requirement
- **WHEN** implementation is complete
- **THEN** contracts and docs match observed output fields and behavior

---

**Source**: US3

WHEN verbose mode is enabled  
THE SYSTEM SHALL include detailed progress output for each major step.

### # Scenario: Verify Requirement
- **WHEN** `-Verbose` is supplied
- **THEN** detailed step output is visible

---

# # Key Entities *(include if feature involves data)*

- **Workspace snapshot**: A JSON record of workspace state at archive time (modified files, untracked files, optional Git metadata).
- **Workflow execution context**: Captures execution_id, change_id, git availability, and verbosity mode for snapshot and logging.
- **Git availability**: Boolean state indicating whether Git commands are usable.
- **Verbosity profile**: Output mode controlling summary vs detailed logs.

---

# # Assumptions *(mandatory)*

## # User Assumptions
- Users can run PowerShell 7+ locally or in CI.
- Users can provide `SPECIFY_CHANGE_ID` when Git is unavailable.

## # Technical Assumptions
- File system writes are permitted under `specs/changes/archive/`.
- Workspace size allows snapshot metadata capture without full file contents.

## # Business Assumptions
- Gitless execution is required for sandbox and offline workflows.

## # External Assumptions
- No external services are required for snapshot storage.

---

# # Dependencies *(mandatory)*

- PowerShell 7+ runtime
- File system access to `specs/changes/` and `specs/changes/archive/`
- Optional Git for enhanced metadata

---

# # Success Criteria *(mandatory)*

- **SC-001**: `check-prerequisites.ps1` passes in a workspace without Git.
- **SC-002**: Archive succeeds with uncommitted changes and records `workspace-snapshot.json`.
- **SC-003**: Default output stays within 30 lines for standard runs.
- **SC-004**: Snapshot metadata capture p95 is ≤ 200 ms for 10k files.
- **SC-005**: Audit append p95 is ≤ 50 ms during gitless execution.

---

# # Out of Scope

- Full VCS replacement or external sync services.
- Binary file content capture in workspace snapshots.





