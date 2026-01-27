# Feature Specification: Workflow audit logging for scripts

**Feature Branch**: `003-workflow-audit-logging`  
**Created**: 2026-01-27  
**Status**: Ready for Archive  
**Input**: User description: "add workflow audit logging to scripts"

## # Overview

This change adds append-only workflow audit logging across state-changing scripts, defines a shared audit schema and retrieval helper, and documents performance and governance validation steps for compliance readiness.

## # User Story 1 - Capture workflow audit entries (Priority: P1)

As a workflow operator, I want every workflow script action that changes state to record an audit entry with the outcome, so I can trace what happened during each run.

**Why this priority**: Without reliable audit entries, there is no trustworthy history of workflow changes or failures.

**Independent Test**: Run a workflow script that performs a state-changing action and verify a new audit entry appears describing the action and outcome.

**Acceptance Scenarios**:

### # Scenario: Happy Path
- **WHEN** a workflow script completes a state-changing action successfully
- **THEN** an audit entry is recorded that identifies the script, action, change ID, timestamp, and success outcome

### # Scenario: Alternate Success
- **WHEN** a workflow script performs multiple state-changing actions in one run
- **THEN** each action has its own audit entry recorded in sequence

### # Scenario: Error Handling
- **WHEN** a workflow script encounters a failure during a state-changing action
- **THEN** an audit entry is recorded with a failure outcome and sanitized error summary before the script exits

---

## # User Story 2 - Preserve append-only history (Priority: P2)

As a workflow maintainer, I need audit logs to be append-only so I can trust that historical records are not overwritten or removed by new runs.

**Why this priority**: Append-only history protects traceability and supports compliance reviews, even when runs occur frequently.

**Independent Test**: Execute two workflow script runs and confirm that the second run only adds new entries without modifying prior ones.

**Acceptance Scenarios**:

### # Scenario: Happy Path
- **WHEN** a workflow script writes a new audit entry while prior entries exist
- **THEN** the new entry is appended after existing entries without altering earlier records

### # Scenario: Error Handling
- **WHEN** an audit entry cannot be written due to a temporary file issue
- **THEN** the script writes a sanitized failure message to stderr, preserves the original error exit code, and leaves existing audit entries unchanged

---

## # User Story 3 - Share safe error details (Priority: P3)

As a compliance reviewer, I want audit logs to contain sanitized error summaries so I can share them without exposing sensitive details.

**Why this priority**: Sanitized error summaries reduce risk while still enabling root-cause analysis.

**Independent Test**: Trigger a failure that includes sensitive values and verify the audit entry reports a sanitized summary.

**Acceptance Scenarios**:

### # Scenario: Happy Path
- **WHEN** a workflow script logs a failure
- **THEN** the recorded error summary excludes sensitive values while preserving the reason for the failure

### # Scenario: Alternate Success
- **WHEN** a workflow script logs a failure caused by missing input data
- **THEN** the audit entry summarizes the missing data condition without exposing any sensitive content

---

## # Edge Cases

- **Missing Log Directory**: Scripts create the log directory before writing audit entries.
- **Concurrent Runs**: Appends use retry/backoff and append-only guards to prevent truncation during concurrent writes.
- **Large Log File**: Operators follow documented rotation/archival guidance; no automatic rotation is included in this change.
- **Clock Skew**: Timestamps reflect the host clock at write time; consumers interpret entries as recorded and must account for host time drift.
- **Write Failure**: Scripts retry appends; if logging still fails, they emit a sanitized warning to stderr and continue with existing failure handling without writing an audit entry.

---

# # State-Changing Actions *(scope)*

Audit logging in this change applies to the following workflow scripts and actions:

- `specs/scripts/create-new-feature.ps1` → create
- `specs/scripts/setup-plan.ps1` → update
- `specs/scripts/generate-proposal.ps1` → update
- `specs/scripts/generate-deltas.ps1` → update
- `specs/scripts/merge-deltas.ps1` → update
- `specs/scripts/archive-feature.ps1` → archive
- `specs/scripts/populate-project.ps1` → update
- `specs/scripts/update-agent-context.ps1` → update
- `specs/scripts/validate.ps1` → validate

## # Change ID Resolution

The `change_id` resolution order is defined in the change_id requirement and implemented by `Get-CurrentChangeId`. When no change context can be resolved, `change_id` remains empty and the audit entry is still recorded.

---

# # Requirements *(mandatory)*

## # Requirement: REQ-001 Record audit entries for state changes

**Source**: US1

WHEN a workflow script performs a state-changing action  
THE SYSTEM SHALL append an audit record in `specs/logs/workflow-audit.jsonl` that includes the script name, action, change ID (if available), ISO 8601 timestamp, and outcome. Error summary requirements are defined in the sanitization requirement.

### # Scenario: Verify Requirement
- **WHEN** a script creates, validates, or archives workflow artifacts
- **THEN** an audit entry is recorded containing all required fields for that action, including an ISO 8601 timestamp

---

## # Requirement: REQ-002 Append audit entries without overwriting history

**Source**: US1, US2

WHEN an audit entry is written  
THE SYSTEM SHALL append it to the existing audit log without truncating or altering prior entries.

### # Scenario: Verify Requirement
- **WHEN** two workflow script runs write audit entries sequentially
- **THEN** the audit log shows both entries in chronological order with earlier entries unchanged

---

## # Requirement: REQ-003 Create audit log storage when missing

**Source**: US1

WHEN a workflow script attempts to write an audit entry and the audit log storage location is missing  
THE SYSTEM SHALL create the required storage location before writing the entry.

### # Scenario: Verify Requirement
- **WHEN** the audit log directory is absent before a script run
- **THEN** the directory is created and the audit entry is written successfully

---

## # Requirement: REQ-004 Log failures before exiting

**Source**: US1, US3

WHEN a workflow script is about to exit due to a failure  
THE SYSTEM MUST record a failure audit entry before the script terminates, unless the audit append fails, in which case it SHALL emit a sanitized warning to stderr that follows the sanitization rules.

### # Scenario: Verify Requirement
- **WHEN** a workflow script encounters a validation failure and exits non-zero
- **THEN** a failure audit entry appears in the log describing the failure outcome
- **WHEN** an audit entry cannot be written after retries
- **THEN** the script emits a sanitized warning to stderr before completing its failure handling

---

## # Requirement: REQ-005 Ensure timely audit visibility

**Source**: US2

WHEN audit entries are written  
THE SYSTEM SHALL make entries visible to log readers (via `Get-WorkflowAuditEntries` or log file tail) within 5 seconds for at least 95% of runs.

### # Scenario: Verify Requirement
- **WHEN** a workflow script completes and writes audit entries over a 20-run sample
- **THEN** reviewers can locate at least 95% of the new entries in the audit log within 5 seconds

---

## # Requirement: REQ-006 Sanitize error summaries

**Source**: US3

WHEN an audit entry records a failure  
THE SYSTEM SHALL sanitize error summaries by redacting values matching sensitive key patterns (password, secret, token, key) and SHALL limit the summary to 512 characters.

### # Scenario: Verify Requirement
- **WHEN** a failure contains a token-like value or secret label
- **THEN** the stored error summary replaces the sensitive value with a redaction marker and remains within 512 characters

---

## # Requirement: REQ-007 Provide audit entry retrieval

**Source**: US2

WHEN a reviewer requests audit history for a change  
THE SYSTEM SHALL provide a list of audit entries from `specs/logs/workflow-audit.jsonl`, with optional filters for change ID and outcome and an adjustable limit.

**Interface Note**: Retrieval is provided by a local helper aligned to `contracts/workflow-audit/list.yaml`; no network service is required.

### # Scenario: Verify Requirement
- **WHEN** a reviewer requests entries for a specific change ID
- **THEN** the system returns a list of matching audit entries in chronological order

---

## # Requirement: REQ-008 Maintain append latency performance

**Source**: SC-008

WHEN audit entries are appended under the standard workload (20 audit writes using the validate action per the quickstart performance check)  
THE SYSTEM SHALL keep append latency at or below 50 ms for the 95th percentile of samples.

### # Scenario: Verify Requirement
- **WHEN** 20+ audit append samples are measured using the quickstart workload profile
- **THEN** the 95th percentile append latency is ≤ 50 ms

---

## # Requirement: REQ-009 Limit runtime impact

**Source**: SC-004

WHEN audit logging is enabled for a representative workflow run (e.g., `validate.ps1 -Target <change-id> -Strict`)  
THE SYSTEM SHALL keep total runtime impact at or below 10% compared to the same workflow executed on the pre-audit logging commit (baseline).

### # Scenario: Verify Requirement
- **WHEN** the representative workflow is executed with logging enabled and compared to the pre-audit baseline run
- **THEN** the total duration delta is ≤ 10%

---

## # Requirement: REQ-010 Maintain documentation and validation evidence

**Source**: Governance

WHEN audit logging behavior or performance verification changes  
THE SYSTEM SHALL update workflow documentation (scripts README and quickstart) and record validation gate execution evidence in `quickstart.md`.

### # Scenario: Verify Requirement
- **WHEN** audit logging tasks are completed
- **THEN** documentation updates and validation evidence are recorded in the change artifacts

---

## # Requirement: REQ-011 Resolve change_id consistently

**Source**: Governance

WHEN a workflow script resolves `change_id`  
THE SYSTEM SHALL use the following precedence order: `SPECIFY_CHANGE_ID` environment value, `SPECIFY_FEATURE` (deprecated), git branch name, then latest `specs/changes/<change-id>` directory.

### # Scenario: Verify Requirement
- **WHEN** `SPECIFY_CHANGE_ID` is set for a workflow run
- **THEN** the resolved change_id matches the environment value regardless of branch or directory

---

## # Requirement: REQ-012 Track post-rollout success criteria

**Source**: SC-005, SC-006, SC-007

WHEN audit logging is deployed to production workflows  
THE SYSTEM SHALL record the measurement plan for SC-005 (maintainer lookup time), SC-006 (support request rate), and SC-007 (compliance review results) in the change artifacts.

### # Scenario: Verify Requirement
- **WHEN** the feature is marked ready for archive
- **THEN** the post-rollout measurement plan for SC-005/SC-006/SC-007 is documented in the spec

---

# # Key Entities *(include if feature involves data)*

- **Audit entry**: A record of a workflow script action, including when it occurred, what changed, and the outcome.
- **Workflow script run**: A single execution instance that may produce one or more audit entries.
- **Change identifier**: A reference that links an audit record with the feature or change it affected, when applicable.

---

# # Assumptions *(mandatory)*

## # User Assumptions
- Workflow operators have access to the repository logs needed to review audit entries.
- Workflow maintainers understand how to interpret script names and action labels in audit records.

## # Technical Assumptions
- Workflow scripts execute with file system write access to the audit log location.
- Up to five concurrent workflow script runs may append entries without corrupting the log.

## # Business Assumptions
- Audit logging is required for governance and operational traceability across all workflow scripts.
- Log retention follows existing repository retention practices and does not require separate archival in this change.

## # External Assumptions
- No external audit aggregation system is required for initial compliance reviews.
- Compliance reviewers rely on sanitized error summaries rather than raw error payloads.

---

# # Dependencies *(mandatory)*

## # Technical Dependencies

| Dependency | Purpose | Status | Risk | Mitigation |
|------------|---------|--------|------|------------|
| Repository file system write access | Store audit entries for workflow scripts | Available | Low | Validate write permissions before running workflows |
| Reliable system clock | Provide accurate timestamps for audit entries | Available | Low | Document clock skew impacts in runbooks |

## # Feature Dependencies

| Feature | Relationship | Status | Notes |
|---------|--------------|--------|-------|
| Workflow scripts in `specs/scripts/` | Integrates | Complete | Audit logging instruments existing workflow actions |

## # External Dependencies

| External System | What It Provides | Owner | Risk |
|-----------------|------------------|-------|------|
| None | No external system required for this feature | N/A | Low |

---

# # Success Criteria *(mandatory)*

## # Functional Success

- **SC-001**: 100% of workflow script state-changing actions produce an audit entry with required fields, measurable by audit log review across sampled runs.
- **SC-002**: 100% of workflow script failures produce a failure audit entry before exit, measurable by reviewing failure logs from scripted tests.

## # Performance Success

- **SC-003**: 95% of audit entries are visible in the audit log within 5 seconds of action completion.
- **SC-004**: Audit logging increases workflow script runtime by no more than 10% in comparative runs.
- **SC-008**: Audit append latency p95 is ≤ 50 ms under the standard workload profile.

## # User Satisfaction

- **SC-005**: 90% of workflow maintainers can locate a specific script outcome in under 2 minutes during a review exercise.
- **SC-006**: Support requests related to missing audit entries remain at or below 1 per quarter after rollout.

## # Business Success

- **SC-007**: Quarterly compliance reviews report zero missing audit entries for audited workflow runs.

---

# # Post-Rollout Measurement Plan

- **SC-005 (Maintainer lookup time)**: Measure via quarterly review exercise; target ≤ 2 minutes per lookup. Owner: workflow maintainer.
- **SC-006 (Support request rate)**: Track audit-related support requests per quarter; target ≤ 1. Owner: support lead.
- **SC-007 (Compliance review results)**: Record quarterly compliance outcomes; target zero missing audit entries. Owner: compliance reviewer.

---

# # Out of Scope

- **Centralized analytics dashboard**: Aggregated reporting or visualization of audit entries is deferred to a future iteration.
- **Automated alerting**: Notifications or paging based on audit failures are not included in this change.
- **Retention policy changes**: Adjustments to long-term storage or archival of audit logs are excluded from this scope.
