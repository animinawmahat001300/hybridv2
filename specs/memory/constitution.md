<!--
Sync Impact Report
- Version change: 1.0.0 → 1.0.1
- Modified principles:
	- VI. Workflow Audit Logging → VI. Workflow Audit Logging (clarified append-only logging and sanitized errors)
- Added sections: none
- Removed sections: none
- Templates requiring updates:
	- ✅ C:\Users\raze0\Documents\hybridv2\specs\templates\plan-template.md (no changes required)
	- ✅ C:\Users\raze0\Documents\hybridv2\specs\templates\spec-template.md (no constitution-specific changes required)
	- ✅ C:\Users\raze0\Documents\hybridv2\specs\templates\tasks-template.md (no changes required)
- Other dependent updates:
	- ✅ C:\Users\raze0\Documents\hybridv2\specs\project.md
	- ✅ C:\Users\raze0\Documents\hybridv2\specs\scripts\README.md
- Follow-up TODOs:
	- TODO(RATIFICATION_DATE): original adoption date unknown; confirm when governance was first ratified.
-->
# SpecKit Constitution

## Core Principles

### I. Spec-First Development
- Every workflow change MUST start with a complete specification in
	`specs/changes/<change-id>/spec.md` before implementation begins.
- Implementation tasks MUST trace to approved requirements; out-of-scope changes
	are prohibited without an updated spec.
Rationale: keeps delivery aligned to documented intent and measurable outcomes.

### II. File-Based Truth
- The canonical source of truth is the repository file system; all workflow
	state MUST live in versioned Markdown files under `specs/`.
- Scripts MUST NOT rely on hidden state or external databases for core workflow
	operations.
Rationale: ensures deterministic, reviewable, and auditable workflow state.

### III. Validation Gates
- Each phase MUST define entry and exit gates and MUST halt on failure.
- `specs/scripts/validate.ps1` (standard or strict) MUST run before any phase
	transition and before archival.
Rationale: prevents propagation of incomplete or invalid artifacts.

### IV. Dual-State Model
- Active work lives in `specs/changes/<change-id>`; deployed truth lives in
	`specs/<capability>`.
- Promotion from change to capability MUST occur only via the archive workflow,
	which produces an immutable record in `specs/changes/archive/`.
Rationale: separates proposal state from authoritative, deployed specifications.

### V. AI-Ready Instructions
- Specifications MUST use imperative, testable language (WHEN/THEN, SHALL/MUST)
	with measurable outcomes.
- Requirements and success criteria MUST avoid ambiguous terms and include
	explicit verification scenarios.
Rationale: guarantees machine- and human-verifiable specifications.

### VI. Workflow Audit Logging
- Workflow scripts that create, modify, validate, or archive artifacts MUST emit
	audit log entries for every state-changing action.
- Audit logs MUST be structured JSON lines in
	`specs/logs/workflow-audit.jsonl` and include: ISO 8601 timestamp, script
	name, action, change ID, outcome, and sanitized error summaries when
	applicable.
- Audit logs MUST be append-only; scripts MUST NOT truncate or rewrite existing
	entries.
- Scripts MUST create the log directory if missing and MUST log failures before
	exiting non-zero.
- Audit entries MUST exclude sensitive data and only include sanitized error
	summaries.
Rationale: provides traceability for compliance and operational forensics.

## Quality Standards

### Specification Quality
- Specifications MUST include at least one P1 user story with WHEN/THEN
	acceptance scenarios.
- Requirements MUST use EARS notation and include a verification scenario.
- Maximum 3 [NEEDS CLARIFICATION] markers per spec (0 in Strict mode).
- Success criteria MUST be measurable and tied to user outcomes.

### Documentation Quality
- Markdown MUST use ATX headings and MUST NOT skip heading levels.
- External links MUST use reference-style links (no inline http/https URLs).
- Final artifacts MUST NOT contain placeholder tokens (TBD, TODO, PLACEHOLDER).
- Files MUST end with a newline and avoid trailing whitespace.

## Decision Framework

### User Value First
Prefer changes that improve clarity, usability, or automation for workflow
participants.

### Automation Over Manual Steps
Automate repeatable steps in scripts before adding manual checklists.

### Minimal Dependencies
Avoid introducing new runtime dependencies; favor PowerShell, Markdown, and Git
capabilities already present.

### Backward-Compatible Evolution
Maintain compatibility with existing file layouts and script interfaces, or
provide documented migration paths.

### Auditability and Security
Favor designs that preserve traceability while avoiding sensitive data in logs.

## Governance

- This constitution supersedes all other guidance for workflow decisions.
- Amendments require an explicit update to this file and `specs/project.md`, a
	documented rationale, and an updated Sync Impact Report.
- Versioning follows semantic versioning: MAJOR for breaking governance changes,
	MINOR for new principles or sections, PATCH for clarifications.
- Compliance reviews MUST include `validate.ps1 -Strict` and a Constitution
	Check in plan artifacts. Exceptions must be documented in Complexity Tracking.

**Version**: 1.0.1 | **Ratified**: TODO(RATIFICATION_DATE): original adoption date unknown | **Last Amended**: 2026-01-27
