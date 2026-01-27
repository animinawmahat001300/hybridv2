# Implementation Plan: gitless-workflow-resilience

**Branch**: 004-gitless-workflow-resilience | **Date**: 2026-01-27 | **Spec**: spec.md
**Input**: Feature specification from `specs/changes/004-gitless-workflow-resilience/spec.md`

---

## Summary

This plan implements gitless workflow execution, archive snapshots for dirty workspaces, and concise default logging using file-based change resolution, snapshot capture, and verbosity gating to deliver resilient workflows in non-Git environments.

---

## Technical Context

| Aspect | Value |
|--------|-------|
| **Language/Version** | PowerShell 7.4+ |
| **Primary Dependencies** | PowerShell core, .NET `System.IO` |
| **Storage** | File system (`specs/changes/`, `specs/changes/archive/`, `specs/logs/workflow-audit.jsonl`) |
| **Testing** | Pester 5 |
| **Target Platform** | PowerShell 7 on Windows and Linux runners |
| **Project Type** | Automation scripts |
| **Performance Goals** | Default output ≤ 30 lines; audit append p95 ≤ 50 ms; snapshot metadata write p95 ≤ 200 ms for 10k files |
| **Constraints** | No external dependencies; create log directory if missing; sanitized error summaries only; append-only JSONL; metadata-only snapshots |
| **Scale/Scope** | Up to 5 concurrent workflow scripts; ~50k audit entries/year; snapshot metadata for large workspaces |

---

## Architecture Overview

### System Components

```
[Operator]
  |
[Workflow Scripts (*.ps1)]
  |
  +--> [common.ps1 utilities]
     |-- RepoRootResolver
     |-- ChangeIdResolver (gitless fallback)
     |-- VerbosityController
     |-- SnapshotWriter
     |-- AuditLogger
  |
[File System]
  |-- specs/changes/<change-id>/
  |-- specs/changes/archive/<timestamp>-<change-id>/
  |-- specs/logs/workflow-audit.jsonl
```

#### Decision 1: Gitless change resolution

- **Choice**: Resolve change ID from `SPECIFY_CHANGE_ID`, otherwise from the active `specs/changes/<id>` folder, without requiring Git.
- **Rationale**: Enables workflows in non-Git environments while honoring file-based truth.
- **Alternatives Rejected**: Require Git branch naming; require mandatory CLI change ID for all scripts.
- **Tradeoffs**: Simpler setup vs. risk of ambiguous change folder selection (mitigated by validation).

#### Decision 2: Workspace snapshot format

- **Choice**: Write `workspace-snapshot.json` with metadata-only file lists and optional Git status block.
- **Rationale**: Captures evidence of local changes with low storage and runtime overhead.
- **Alternatives Rejected**: Full workspace archive or Git-only status snapshot.
- **Tradeoffs**: Smaller snapshot vs. no full file contents.

#### Decision 3: Verbosity gating

- **Choice**: Use concise default output with phase summaries and warnings; detailed output via `Write-Verbose` and `-Verbose`.
- **Rationale**: Meets default output constraint while preserving diagnostics.
- **Alternatives Rejected**: Always-verbose output or custom logging flags only.
- **Tradeoffs**: Fewer details by default vs. improved signal-to-noise ratio.

### Integration Points

| System | Direction | Contract | Notes |
|--------|-----------|----------|-------|
| Git CLI (optional) | Consumes | None | Used only for supplemental metadata; scripts must succeed without it. |
| Workflow JSON output | Provides | `contracts/workflow/*.yaml` | Contracts describe JSON outputs for scripts. |
| File system | Consumes | None | Requires read/write access to `specs/changes/` and archive paths. |

---

## Data Model

### Entity Summary

| Entity | Key Fields | Relationships | Storage |
|--------|------------|---------------|---------|
| WorkspaceSnapshot | schema_version, captured_at, change_id, file lists | References WorkflowExecutionContext by change_id | File system (JSON) |
| WorkflowExecutionContext | execution_id, change_id, repo_root, verbosity_mode | Emits WorkspaceSnapshot on archive | Script output JSON |

**Detailed Model**: See `data-model.md`.

---

## API Contracts

### Endpoints

| Method | Path | Purpose | Contract |
|--------|------|---------|----------|
| GET | `/api/workflow/check-prerequisites` | Resolve change ID and environment readiness | `contracts/workflow/check-prerequisites.yaml` |
| POST | `/api/workflow/run` | Execute workflow with summary or verbose output | `contracts/workflow/run.yaml` |
| POST | `/api/workflow/archive` | Archive change and capture workspace snapshot | `contracts/workflow/archive.yaml` |

**Contract Files**: See `contracts/workflow/` directory.

---

## Assumptions

### Technical Assumptions

| Assumption | Verification | Risk |
|------------|--------------|------|
| `SPECIFY_CHANGE_ID` is available in Gitless environments | Run scripts with env var set and confirm change resolution | Medium |
| File metadata access is permitted for snapshot capture | Attempt snapshot in a restricted folder and confirm error handling | Medium |
| PowerShell `Write-Verbose` respects `-Verbose` preference | Run script with and without `-Verbose` to confirm output | Low |

### Operational Assumptions

| Assumption | Verification | Risk |
|------------|--------------|------|
| Archive folder is writable under `specs/changes/archive/` | Create a test archive and verify file writes | Medium |
| CI runners provide PowerShell 7+ | Validate in CI images or local tests | Low |
| Local execution allows JSON output to stdout | Run scripts and confirm JSON outputs are captured | Low |

### High-Risk Flags

- **Medium** Snapshot performance on very large workspaces could exceed acceptable runtime → Mitigation: collect metadata only and cap file enumeration time if needed.

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Spec-First Development**: Specification complete before implementation
- [x] **File-Based Truth**: All state in Markdown files
- [x] **Validation Gates**: Gates defined for all transitions
- [x] **Dual-State Model**: Work staged in `specs/changes/` before promotion
- [x] **AI-Ready Instructions**: Imperative language with testable scenarios
- [x] **Workflow Audit Logging** (workflow scripts only): Audit logs planned for state-changing operations

---

## Project Structure

### Documentation (this feature)

```text
specs/changes/004-gitless-workflow-resilience/
├── spec.md              # Feature specification (input)
├── plan.md              # This file
├── tasks.md             # Task breakdown (generated by /speckit.tasks)
├── research.md          # Technical research (Phase 0 output)
├── data-model.md        # Data model details (Phase 1 output)
├── quickstart.md        # Integration guide (Phase 1 output)
├── contracts/           # API contracts (Phase 1 output)
│   └── workflow/
│       ├── check-prerequisites.yaml
│       ├── run.yaml
│       └── archive.yaml
└── checklists/          # Quality checklists (optional)
  └── requirements.md
```

### Source Code Structure

**Selected Structure**: Single Project

```text
specs/scripts/           # Workflow automation scripts
specs/tests/             # Pester tests for scripts
tests/                   # Repository-level integration tests
```

### Selected Structure

- **Project Type**: Single (automation scripts)
- **Source Root**: `specs/scripts`
- **Tests Root**: `specs/tests` (plus `tests/` for integration)
- **Docs Root**: `specs/`

---

## Implementation Phases

### Phase 0: Research

**Objective**: Resolve technical unknowns before design

**Tasks**:
- [x] Document gitless change ID resolution approach
- [x] Define workspace snapshot schema and metadata limits
- [x] Confirm verbosity control using `Write-Verbose`

**Output**: `research.md`

**Gate**: All research items resolved

---

### Phase 1: Design

**Objective**: Create design artifacts before implementation

**Tasks**:
- [x] Define data models → `data-model.md`
- [x] Design API contracts → `contracts/`
- [x] Create integration guide → `quickstart.md`

**Output**: `data-model.md`, `contracts/`, `quickstart.md`

**Gate**: Design artifacts complete and consistent with spec

---

### Phase 2: Task Generation

**Objective**: Generate actionable task breakdown

**Command**: `/speckit.tasks`

**Input**: This plan + spec.md

**Output**: `tasks.md`

**Gate**: Tasks reviewed and dependencies validated

---

## Dependencies

| Dependency | Version | Purpose | Source |
|------------|---------|---------|--------|
| PowerShell | 7.4+ | Script runtime | System |
| Git | 2.30+ (optional) | Optional metadata and branch info | System |
| .NET `System.IO` | Bundled | File system operations | Runtime |
| Pester | 5.x | Script tests | PowerShell Gallery |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Snapshot metadata capture slows on very large workspaces | Medium | Medium | Use metadata-only capture and allow early exit on time budget if needed. |
| Ambiguous change folder selection in Gitless mode | Low | High | Require `SPECIFY_CHANGE_ID` when multiple change folders exist. |
| Reduced default verbosity hides critical details | Low | Medium | Ensure warnings and summary include actionable guidance; verbose mode available. |

---

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | No constitution violations detected. | Not applicable. |

---

## Validation Checklist

- [x] **Spec Reference**: spec.md exists and is referenced
- [x] **Technical Context**: All fields filled
- [x] **Architecture**: Diagram and key decisions documented
- [x] **Data Model**: Entities listed and data-model.md referenced
- [x] **API Contracts**: Endpoints listed and contracts referenced
- [x] **Project Structure**: Paths defined for source and tests
- [x] **Phases**: All phases have objectives and outputs
- [x] **Dependencies**: Runtime dependencies listed with versions
- [x] **Risks**: Risks identified with mitigations
- [x] **Constitution Check**: All items checked
- [x] **No Placeholders**: No placeholder tokens remain
```text
{SRC_ROOT}/           # e.g., src/ or lib/
â”œâ”€â”€ models/           # Data models and entities
â”œâ”€â”€ services/         # Business logic
â”œâ”€â”€ api/              # API endpoints/handlers
â””â”€â”€ utils/            # Shared utilities

{TESTS_ROOT}/         # e.g., tests/ or __tests__/
â”œâ”€â”€ unit/             # Unit tests
â”œâ”€â”€ integration/      # Integration tests
â””â”€â”€ contract/         # Contract tests
```

**Option 2: Web Application** (frontend + backend)
```text
backend/{SRC_ROOT}/   # e.g., backend/src/
â”œâ”€â”€ models/
â”œâ”€â”€ services/
â””â”€â”€ api/
backend/{TESTS_ROOT}/

frontend/{SRC_ROOT}/  # e.g., frontend/src/
â”œâ”€â”€ components/
â”œâ”€â”€ pages/
â””â”€â”€ services/
frontend/{TESTS_ROOT}/
```

**Option 3: Mobile + API**
```text
api/{SRC_ROOT}/       # API backend
â””â”€â”€ {SAME_AS_OPTION_1}

ios/{SRC_ROOT}/       # iOS app (or android/)
â””â”€â”€ {PLATFORM_SPECIFIC}
```

### Selected Structure

> **AI Instructions**: Document the actual paths for this project.

- **Project Type**: {SINGLE_WEB_MOBILE}
- **Source Root**: `{ACTUAL_PATH_E_G_SRC}`
- **Tests Root**: `{ACTUAL_PATH_E_G_TESTS}`
- **Docs Root**: `{ACTUAL_PATH_E_G_DOCS}`

---

## Implementation Phases

> **AI Instructions - Phases**:
> - Phase 0 (Research) and Phase 1 (Design) produce artifacts, not code
> - Phase 2 generates tasks.md - the actionable implementation plan
> - Each phase has clear objectives, tasks, and outputs
> - Link to output files in same folder

### Phase 0: Research

> **AI Instructions**: Only needed if technical unknowns exist. Skip if technology is well-known.

**Objective**: Resolve technical unknowns before design

**When Needed**:
- New technology or framework
- Complex integration requirements
- Performance-critical decisions
- Multiple viable approaches

**Tasks**:
- [ ] Research {TECHNOLOGY_PATTERN} options
- [ ] Evaluate {LIBRARY_A} vs {LIBRARY_B}
- [ ] Prototype {CRITICAL_FUNCTIONALITY}
- [ ] Document findings and recommendations

**Output**: `research.md`

**Gate**: All {NEEDS_RESEARCH} items from spec.md resolved

---

### Phase 1: Design

**Objective**: Create design artifacts before implementation

**Tasks**:
- [ ] Define data models â†’ `data-model.md`
- [ ] Design API contracts â†’ `contracts/`
- [ ] Create integration guide â†’ `quickstart.md`
- [ ] Update architecture diagram if needed

**Output**: `data-model.md`, `contracts/`, `quickstart.md`

**Gate**: Architecture review complete, contracts approved

---

### Phase 2: Task Generation

**Objective**: Generate actionable task breakdown

**Command**: `/speckit.tasks`

**Input**: This plan + spec.md

**Output**: `tasks.md`

**Gate**: Tasks reviewed, dependencies validated

---

## Dependencies

> **AI Instructions - Dependencies Table**:
> - List runtime dependencies (libraries, packages)
> - Include version requirements
> - Reference package.json, requirements.txt, or equivalent

| Dependency | Version | Purpose | Source |
|------------|---------|---------|--------|
| {PACKAGE_NAME} | {X_X_X} | {WHY_NEEDED} | npm / pip / go mod |
| {PACKAGE_NAME} | {X_X} | {WHY_NEEDED} | npm / pip / go mod |

---

## Risks & Mitigations

> **AI Instructions - Risk Assessment**:
> - Import risks from spec.md dependencies section
> - Add technical implementation risks
> - Each risk needs: likelihood, impact, mitigation strategy
> - Focus on risks that could block or delay implementation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| {TECHNICAL_RISK} | Low / Medium / High | Low / Medium / High | {PREVENTION_OR_RESPONSE_STRATEGY} |
| {INTEGRATION_RISK} | Low / Medium / High | Low / Medium / High | {PREVENTION_OR_RESPONSE_STRATEGY} |
| {DEPENDENCY_RISK} | Low / Medium / High | Low / Medium / High | {PREVENTION_OR_RESPONSE_STRATEGY} |

---

## Complexity Tracking

> **AI Instructions - Complexity Tracking**:
> - Only fill if Constitution Check has violations
> - Document WHY complexity is necessary
> - Explain why simpler alternatives don't work

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| {CONSTITUTION_VIOLATION} | {CURRENT_NECESSITY} | {WHY_SIMPLER_APPROACH_INSUFFICIENT} |

---

## Validation Checklist

> **AI Instructions**: Before marking plan complete, verify ALL items pass.

- [ ] **Spec Reference**: spec.md exists and is referenced
- [ ] **Technical Context**: All fields filled (no NEEDS CLARIFICATION remaining)
- [ ] **Architecture**: Diagram and key decisions documented
- [ ] **Data Model**: Entities listed or data-model.md referenced
- [ ] **API Contracts**: Endpoints listed or contracts/ referenced
- [ ] **Project Structure**: Paths defined for `{SRC_ROOT}`, `{TESTS_ROOT}`
- [ ] **Phases**: All phases have objectives and outputs
- [ ] **Dependencies**: Runtime dependencies listed with versions
- [ ] **Risks**: At least one risk identified with mitigation
- [ ] **Constitution Check**: All items checked or violations documented
- [ ] **No Placeholders**: No placeholder tokens remain
