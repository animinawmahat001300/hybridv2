# SpecKit Project Context

## Purpose
SpecKit provides a specification-driven development workflow with PowerShell
automation for creating, validating, and archiving feature specifications. The
goal is to standardize change delivery, enforce quality gates, and keep all
workflow state in versioned Markdown artifacts.

## Tech Stack
- **Scripting**: PowerShell 7+
- **Documentation**: Markdown (CommonMark)
- **Version Control**: Git 2.30+
- **Testing**: Pester 5 (PowerShell)
- **Data Formats**: JSON, YAML
- **Tooling**: VS Code (recommended)

## Project Conventions

### Code Style

#### PowerShell formatting
- Indentation: 4 spaces, no tabs
- Line length: 120 characters max
- Braces: K&R style
- Functions: Verb-Noun naming, PascalCase parameters
- Script files: kebab-case

#### Markdown formatting
- ATX headings with sentence case
- Placeholders use UPPER_SNAKE_CASE tokens in templates
- Fenced code blocks include language identifiers

#### Output patterns
- JSON output for automation scripts uses consistent schema
- Errors write to stderr with non-zero exit codes

### Architecture Patterns

#### Specification-first workflow
- All features originate in `specs/changes/<change-id>` before implementation
- Plans, tasks, and checklists derive from template-driven specs

#### Dual-state storage
- `specs/changes/` stores proposals; `specs/<capability>/` stores deployed truth
- Archives live under `specs/changes/archive/` and are immutable

#### Scripted automation
- PowerShell scripts orchestrate workflow phases and validation gates
- Shared utilities live in `specs/scripts/common.ps1`

#### File-based persistence
- Workflow state is stored in Markdown/JSON artifacts committed to Git

### Testing Strategy
- Pester tests live in `specs/tests/` (or `tests/` at repo root)
- `specs/scripts/validate.ps1` is the primary gate for spec compliance
- Strict mode enforces full constitution compliance before archival

### Git Workflow
- Branch naming: `feature/<change-id>` or `<issue>-<slug>`
- Commit format: `<type>(scope): subject` (e.g., `docs(constitution): add audit logging`)
- Merge strategy: squash merges to main
- Tag releases with `vMAJOR.MINOR.PATCH`

## Domain Context
- **Capability**: Deployed spec in `specs/<capability>/spec.md`
- **Change**: Active proposal in `specs/changes/<change-id>/`
- **Archive**: Immutable record in `specs/changes/archive/<timestamp>-<change-id>/`
- **Governance**: `specs/memory/constitution.md`
- **Workflow Scripts**: PowerShell automation in `specs/scripts/`

## Important Constraints
- Final artifacts MUST NOT contain placeholders (TODO, TBD, PLACEHOLDER).
- Specifications MUST pass validation gates before implementation or archive.
- Workflow scripts MUST emit append-only JSONL audit logs in
	`specs/logs/workflow-audit.jsonl`.
- Audit entries MUST include sanitized error summaries only and MUST exclude
	secrets or PII.
- Audit logging MUST create the log directory if missing and log failures
	before non-zero exit.
- Audit logging performance MUST keep p95 append time ≤ 50 ms, total runtime
	impact ≤ 10%, and entries visible within 5 seconds for 95% of runs.
- Markdown must remain human-readable and tool-parseable.
- Core workflow avoids external runtime dependencies.

## External Dependencies
- Git 2.30+ for version control
- PowerShell 7+ for automation scripts
- Pester 5 for test execution
- VS Code with Markdown tooling (recommended)
