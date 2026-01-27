# Implementation Plan: Workflow audit logging

**Branch**: `002-audit-logging-workflow` | **Date**: 2026-01-26 | **Spec**: spec.md
**Input**: Feature specification from `specs/changes/002-audit-logging-workflow/spec.md`

---

## Summary

This plan implements workflow audit logging for state-changing scripts using a shared PowerShell audit writer that appends structured JSONL entries. The approach delivers traceable, compliant workflow history for operators and release managers with minimal runtime overhead.

---

## Technical Context

| Aspect | Value |
|--------|-------|
| **Language/Version** | PowerShell 7.4+ |
| **Primary Dependencies** | PowerShell core, .NET `System.IO` |
| **Storage** | File system (`specs/logs/workflow-audit.jsonl`) |
| **Testing** | Pester 5 |
| **Target Platform** | PowerShell 7 on Windows and Linux runners |
| **Project Type** | Automation scripts |
| **Performance Goals** | Append audit entry p95 ≤ 50 ms; total runtime impact ≤ 10%; entries visible within 5 seconds for 95% of runs |
| **Constraints** | No external dependencies; create log directory if missing; sanitized error summaries only; append-only JSONL |
| **Scale/Scope** | Up to 5 concurrent workflow scripts; ~50k entries/year |

---

## Architecture Overview

### System Components

```
[Workflow Script] ---> [Audit Logger Helper] ---> specs/logs/workflow-audit.jsonl
                               |
                               +--> [Audit Review/Filter Scripts]
```

#### Decision 1: Append-only JSON Lines audit log

- **Choice**: Use `specs/logs/workflow-audit.jsonl` with schema versioned JSON entries.
- **Rationale**: Aligns with constitution, supports file-based truth, and allows efficient streaming reads.
- **Alternatives Rejected**: CSV (poor structure), Markdown logs (hard to parse), external logging services (adds dependencies).
- **Tradeoffs**: Optimizes for simplicity and auditability; sacrifices rich query capabilities.

#### Decision 2: FileStream append with retry/backoff

- **Choice**: Append using `System.IO.FileStream` with exclusive writer lock and retry/backoff.
- **Rationale**: Ensures atomic writes under concurrent scripts without external synchronization.
- **Alternatives Rejected**: `Add-Content` without locking (risk of interleaved writes), mutex/lock file (more complexity).
- **Tradeoffs**: Optimizes for reliability; adds small implementation complexity.

### Integration Points

| System | Direction | Contract | Notes |
|--------|-----------|----------|-------|
| Workflow scripts | Provides | `contracts/workflow-audit/create.yaml` | Scripts append audit entries after actions. |
| Audit review tooling | Consumes | `contracts/workflow-audit/list.yaml` | Filters entries by change ID for timeline reconstruction. |

---

## Data Model

### Entity Summary

| Entity | Key Fields | Relationships | Storage |
|--------|------------|---------------|---------|
| AuditLogEntry | timestamp, script_name, action, change_id, outcome | None | `specs/logs/workflow-audit.jsonl` |

**Detailed Model**: See `data-model.md`.

---

## API Contracts

### Endpoints

| Method | Path | Purpose | Contract |
|--------|------|---------|----------|
| POST | `/api/workflow-audit` | Append an audit entry | `contracts/workflow-audit/create.yaml` |
| GET | `/api/workflow-audit` | List audit entries (filter by change ID) | `contracts/workflow-audit/list.yaml` |

**Contract Files**: See `contracts/` directory.

---

## Assumptions

### Technical Assumptions

| Assumption | Verification | Risk |
|------------|--------------|------|
| Workflow scripts can write to `specs/logs` | Run a write test in CI and local environments | Medium |
| FileStream append behaves consistently across Windows/Linux | Pester coverage on both platforms | Low |
| Redaction regex removes token-like secrets reliably | Unit tests with known secret patterns | Medium |

### Operational Assumptions

| Assumption | Verification | Risk |
|------------|--------------|------|
| Security policy allows sanitized audit logs in private repo | Compliance sign-off before rollout | High |
| Audit logs retained for 12 months in repo + archives | Release management retention checklist | Medium |
| CI runners permit log writes during workflows | Pipeline dry run validation | Medium |

### High-Risk Flags

- **High** Security policy approval is required for repository-based audit logs → mitigate by scheduling compliance review before implementation.

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
specs/changes/002-audit-logging-workflow/
|-- spec.md              # Feature specification (input)
|-- plan.md              # This file
|-- tasks.md             # Task breakdown (generated by /speckit.tasks)
|-- research.md          # Technical research (Phase 0 output)
|-- data-model.md        # Data model details (Phase 1 output)
|-- quickstart.md        # Integration guide (Phase 1 output)
|-- contracts/           # API contracts (Phase 1 output)
|   `-- workflow-audit/
|       |-- create.yaml
|       `-- list.yaml
`-- checklists/          # Quality checklists (optional)
    `-- requirements.md
```

### Source Code Structure

**Option 1: Single Project** (selected)
```text
specs/scripts/
|-- models/
|-- services/
|-- api/
`-- utils/

specs/tests/
|-- unit/
|-- integration/
`-- contract/
```

### Selected Structure

- **Project Type**: Single (automation scripts)
- **Source Root**: `specs/scripts`
- **Tests Root**: `specs/tests`
- **Docs Root**: `specs`

---

## Implementation Phases

### Phase 0: Research

**Objective**: Resolve technical unknowns before design.

**Tasks**:
- [x] Confirm audit log schema/location and JSONL format
- [x] Decide concurrency strategy for concurrent writes
- [x] Define redaction approach for error summaries
- [x] Document retention and security assumptions
- [x] Document findings in `research.md`

**Output**: `research.md`

**Gate**: All research items resolved.

---

### Phase 1: Design

**Objective**: Create design artifacts before implementation.

**Tasks**:
- [x] Define data models → `data-model.md`
- [x] Design API contracts → `contracts/`
- [x] Create integration guide → `quickstart.md`

**Output**: `data-model.md`, `contracts/`, `quickstart.md`

**Gate**: Architecture review complete, contracts approved.

---

### Phase 2: Task Generation

**Objective**: Generate actionable task breakdown.

**Command**: `/speckit.tasks`

**Input**: This plan + spec.md.

**Output**: `tasks.md`

**Gate**: Tasks reviewed, dependencies validated.

---

## Dependencies

| Dependency | Version | Purpose | Source |
|------------|---------|---------|--------|
| PowerShell | 7.4+ | Run workflow scripts and logging helper | System runtime |
| .NET Runtime | 7.x (bundled) | FileStream and JSON serialization | System runtime |
| Pester | 5.x | Unit and integration testing | PowerShell Gallery |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Log directory missing or unwritable | Medium | High | Create directory if missing; fail fast with clear error and audit failure entry. |
| Concurrent writes cause contention | Medium | Medium | FileStream append with retry/backoff and exclusive writer lock. |
| Log growth becomes excessive | Medium | Medium | Document size thresholds and rotate during archive workflow. |
| Security policy disallows repo storage | Low | High | Obtain compliance approval; pivot to secured storage if needed. |

---

## Complexity Tracking

No constitution violations identified.

---

## Validation Checklist

- [x] **Spec Reference**: spec.md exists and is referenced
- [x] **Technical Context**: All fields filled (no NEEDS CLARIFICATION remaining)
- [x] **Architecture**: Diagram and key decisions documented
- [x] **Data Model**: Entities listed and data-model.md referenced
- [x] **API Contracts**: Endpoints listed and contracts/ referenced
- [x] **Project Structure**: Paths defined for `specs/scripts`, `specs/tests`
- [x] **Phases**: All phases have objectives and outputs
- [x] **Dependencies**: Runtime dependencies listed with versions
- [x] **Risks**: At least one risk identified with mitigation
- [x] **Constitution Check**: All items checked
- [x] **No Placeholders**: No placeholder tokens remain
