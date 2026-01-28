<!-- BEGIN SPECKIT AUTO -->
# Copilot Context for hybridv2

**Last Updated**: 2026-01-28T00:31:34.0565637+08:00

## Project Overview

This project follows SpecKit Consolidated governance with spec-first development and file-based truth.

## Governance Principles

### I. Spec-First Development

- Every workflow change MUST start with a complete specification in 	`specs/changes/<change-id>/spec.md` before implementation begins.

### II. File-Based Truth

- The canonical source of truth is the repository file system; all workflow 	state MUST live in versioned Markdown files under `specs/`.

### III. Validation Gates

- Each phase MUST define entry and exit gates and MUST halt on failure. - `specs/scripts/validate.ps1` (standard or strict) MUST run before any phase

### IV. Dual-State Model

- Active work lives in `specs/changes/<change-id>`; deployed truth lives in 	`specs/<capability>`.

### V. AI-Ready Instructions

- Specifications MUST use imperative, testable language (WHEN/THEN, SHALL/MUST) 	with measurable outcomes.

### VI. Workflow Audit Logging

- Workflow scripts that create, modify, validate, or archive artifacts MUST emit 	audit log entries for every state-changing action.


## Technology Stack

### Backend
- Scripting: PowerShell 7+
- Documentation: Markdown (CommonMark)
- Version Control: Git 2.30+
- Testing: Pester 5 (PowerShell)
- Data Formats: JSON, YAML
- Tooling: VS Code (recommended)


### Feature-Specific Tech Constraints
- Language/Version: {E_G_TYPESCRIPT_53_PYTHON_312_GO_121}
- Primary Dependencies: {E_G_REACT_18_FASTAPI_GIN}
- Storage: {E_G_POSTGRESQL_15_REDIS_FILE_SYSTEM_N_A}
- Testing: {E_G_JEST_PYTEST_GO_TEST}
- Target Platform: {E_G_LINUX_SERVER_BROWSER_CHROME_90_IOS_16}
- Project Type: {SINGLE_WEB_MOBILE_API}
- Performance Goals: {E_G_200MS_P95_RESPONSE_60FPS_1000_REQ_S}
- Constraints: {E_G_100MB_MEMORY_OFFLINE_CAPABLE_WCAG_21_AA}
- Scale/Scope: {E_G_10K_USERS_1M_RECORDS_50_API_ENDPOINTS}


## Code Conventions
- PowerShell formatting
- Markdown formatting
- Output patterns

## Architecture Patterns
- Specification-first workflow
- Dual-state storage
- Scripted automation
- File-based persistence

## Active Changes
- 001-workflow-smoke-test

## SpecKit Workflow

All features follow the 11-phase SpecKit workflow:

1. **document** - Generate workflow guide
2. **constitution** - Verify governance
3. **specify** - Create specification
4. **clarify** - Resolve ambiguities
5. **plan** - Technical implementation plan
6. **tasks** - Task breakdown
7. **checklist** - Acceptance criteria
8. **taskstoissues** - Convert to GitHub issues
9. **analyze** - Validate consistency
10. **implement** - Execute implementation
11. **archive** - Archive and promote to truth

## References

- Constitution: specs/memory/constitution.md
- Project Context: specs/project.md
- Changes: specs/changes/
- SpecKit Agents: .github/agents/
<!-- END SPECKIT AUTO -->






