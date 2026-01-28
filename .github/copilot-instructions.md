<!-- BEGIN SPECKIT AUTO -->
# Copilot Context for hybridv2

**Last Updated**: 2026-01-28T05:10:55.9635610+08:00

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
- Language/Version: PowerShell 7.0+
- Primary Dependencies: None (core PowerShell only)
- Storage: N/A (stateless, in-memory)
- Testing: Pester 5
- Target Platform: Windows, Linux, macOS (PowerShell 7+)
- Project Type: Single module
- Performance Goals: Instant response (<50ms per calculation)
- Constraints: No external dependencies, [double] numeric range
- Scale/Scope: Single function, 9 requirements


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
- 002-simple-calculator
- 003-simple-calculator

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










