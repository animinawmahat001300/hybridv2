---

## DETAILED 11-PHASE CONTENT (Preserving ALL Original Quality)

---

### `## 1. Comprehend`

**Signal**: Request received → **Gate**: Requirements extracted, success criteria defined

- Validate `specs/changes/{CHANGE_ID}/spec.md` exists and is readable
- Run `eng/speckit-plan-setup.ps1` to initialize `specs/changes/{CHANGE_ID}/plan.md`
  ```powershell
  if ($LASTEXITCODE -ne 0) {
      throw "speckit-plan-setup.ps1 failed with exit code $LASTEXITCODE"
  }
  ```
- Read `specs/changes/{CHANGE_ID}/spec.md` for feature requirements
- Read `specs/memory/constitution.md` for governance constraints
- Read `specs/project.md` for tech stack: languages, frameworks, APIs, infrastructure
- Extract all markers:
  - `[NEEDS RESEARCH: ...]`
  - `[NEEDS CLARIFICATION: ...]`
  - Technology choices without rationale
  - Integration points without contracts
- Define success criteria: **all 8 artifacts must be created**

> Success Gate: spec.md readable, constitution.md accessible, plan.md template initialized, all markers cataloged.

---

### `## 2. Investigate`

**Signal**: Requirements extracted → **Gate**: Codebase patterns documented

- Use `codebase` tool to search `src/` for existing implementation patterns
- Check `specs/templates/` for artifact templates:
  | Template | Purpose |
  |----------|---------|
  | `research-template.md` | Research findings structure |
  | `data-model-template.md` | Entity definitions |
  | `quickstart-template.md` | Integration guide |
  | `design-template.md` | Architecture blueprint |
  | `implementation-guide-template.md` | How-to instructions |
  | `blueprint-template.md` | Master synthesis |
- Search existing `specs/changes/*/` directories for artifact structure patterns
- Document naming conventions from existing files
- Validate `specs/scripts/validate.ps1` and `specs/scripts/update-agent-context.ps1` exist
- Identify exemplar files to reference for each artifact type

> Rule: Document what IS (discovered patterns), not what SHOULD BE. Skip generic observations.

---

### `## 3. Fetch`

**Signal**: Patterns documented → **Gate**: All inputs accessible

- Use `fetch` tool to retrieve any user-provided URLs
- Read core files using `read_file`:
  - `specs/changes/{CHANGE_ID}/spec.md` → **STOP if missing**
  - `specs/memory/constitution.md` → **STOP if missing**
  - `specs/project.md` → **STOP if missing**
- Parse user input from `$ARGUMENTS` for additional context
- Validate all three core files contain expected sections
- Fetch external documentation for any third-party libraries mentioned in `specs/project.md`

> If any required file missing, report error with path and halt workflow.

---

### `## 4. Research`

**Signal**: Inputs accessible → **Gate**: All unknowns resolved, `research.md` created

**Context7 Research Pattern** — ALWAYS use context7 for library/framework research:

**Placeholder Guidance**:
- `{{libraryName}}`: multi-word query or package name (framework + vendor + domain)
- `{{libraryId}}`: value returned from resolve step (format like `/org/project`)
- `{{topic}}`: 4–5 terms with functions, paths, or errors
- `{{conceptTopic}}`: conceptual phrasing for architecture/decisions
- `{{mode}}`: `code` or `info` (lowercase only)
- `{{page}}`: number 1–10

**Step A - Resolve Library ID**:
| Do | Don't |
|----|-------|
| Use multi-word queries | Use single-word queries |
| Include versions from `specs/project.md` | Use boolean operators (AND/OR) |
| Add technology context | Guess library IDs |
| Include framework for variants | Skip version specification |

**Selection criteria**: Maximum coverage (highest snippet count), highest quality (benchmark score), specific version when required

**Step B - Get Library Docs**:
| Do | Don't |
|----|-------|
| Use compound topics (4–5 terms) | Use single-word topics |
| Include function names or file paths | Use boolean operators |
| Use exact error message text | Use uppercase values for `mode` |
| Use `mode: "info"` for conceptual guidance | Use `page` outside 1–10 |
| Paginate with `page: 1..10` | Stop before "=== LAST PAGE ===" |

**Mode selection**: `mode: "code"` for implementation/syntax (default), `mode: "info"` for concepts/architecture

**Common Library IDs Reference**:
| Category | Library ID | Description |
|----------|------------|-------------|
| React | `/reactjs/react.dev` | React documentation |
| Next.js | `/vercel/next.js` | Next.js framework |
| Validation | `/websites/zod_dev` | Zod (112k snippets) |
| Database (Prisma) | `/prisma/docs` | Prisma ORM |
| Database (Drizzle) | `/drizzle-team/drizzle-orm-docs` | Drizzle ORM |
| UI | `/shadcn-ui/ui` | shadcn/ui components |
| Testing | `/vitest-dev/vitest` | Vitest testing |
| State | `/pmndrs/zustand` | Zustand state management |

**Tool Call Templates**:
```typescript
// Resolve library ID (required first)
context7_resolve-library-id({ libraryName: "{{libraryName}}" })

// Fetch documentation (after resolve)
context7_get-library-docs({
  context7CompatibleLibraryID: "{{libraryId}}",
  topic: "{{topic}}",
  mode: "{{mode}}",
  page: {{page}}
})

// Conceptual guidance (use mode: "info")
context7_get-library-docs({
  context7CompatibleLibraryID: "{{libraryId}}",
  topic: "{{conceptTopic}}",
  mode: "info"
})
```

**Additional Research Tools**:
- Use `githubRepo` to examine reference implementations
- Use `fetch` to access external documentation
- Use `codebase` to search existing patterns in repo

**Output: research.md** — Create `specs/changes/{CHANGE_ID}/research.md`:
| Section | Content |
|---------|---------|
| Research Summary | Table of topics, decisions, confidence levels |
| Detailed Findings | Per-topic: question, decision, rationale, alternatives, sources |
| Resolved Items | Mapping from original `[NEEDS...]` to resolution |
| Remaining Unknowns | Any items that couldn't be resolved |

> Gate: All `[NEEDS RESEARCH]` items resolved before proceeding.

---

### `## 5. Best Practices`

**Signal**: Research complete → **Gate**: Standards defined from codebase

- Extract coding standards from `specs/project.md`
- Use `codebase` to search for error handling patterns in `src/errors/` or `src/middleware/`
- Use `codebase` to search for validation patterns in `src/validators/` or `src/api/`

**Coding Standards** (derive from discovered patterns):
| Element | Convention | Example |
|---------|------------|---------|
| Files | kebab-case | `user-service.ts` |
| Classes | PascalCase | `UserService` |
| Functions | camelCase | `createUser()` |
| Constants | SCREAMING_SNAKE | `MAX_RETRIES` |
| Interfaces | PascalCase with I prefix | `IUserRepository` |

**Anti-Patterns to Avoid**:
| Anti-Pattern | Why Avoid | Instead Do |
|--------------|-----------|------------|
| Hard-coded values | Brittle, environment-specific | Use config/env variables |
| `TODO`/`FIXME` placeholders | Incomplete implementation | Resolve before commit |
| Empty catch blocks | Hidden failures | Log and handle properly |
| `.unwrap()` without context | Panics without info | Use `.expect("reason")` or `?` |
| Magic numbers | Unclear intent | Use named constants |
| Deep nesting | Hard to read | Extract to functions |

**Required Patterns**:
- Configuration for all external values
- Input validation on all entry points
- Error handling with meaningful messages
- Pattern consistency with existing codebase
- Tests that fail when implementation is wrong

> Standards must come from THIS codebase's patterns. Generic advice is useless.

---

### `## 6. Plan`

**Signal**: Standards defined → **Gate**: Artifact sequence created with dependencies

**Artifact Creation Order**:
| Order | Artifact | Path | Dependencies |
|-------|----------|------|--------------|
| 1 | research.md | `specs/changes/{CHANGE_ID}/research.md` | spec.md, constitution.md, project.md |
| 2 | data-model.md | `specs/changes/{CHANGE_ID}/data-model.md` | research.md |
| 3 | contracts/*.yaml | `specs/changes/{CHANGE_ID}/contracts/` | data-model.md |
| 4 | quickstart.md | `specs/changes/{CHANGE_ID}/quickstart.md` | contracts/ |
| 5 | design.md | `specs/changes/{CHANGE_ID}/design.md` | all scaffold artifacts |
| 6 | implementation-guide.md | `specs/changes/{CHANGE_ID}/implementation-guide.md` | design.md |
| 7 | blueprint.md | `specs/changes/{CHANGE_ID}/blueprint.md` | all previous artifacts |
| 8 | plan.md (finalize) | `specs/changes/{CHANGE_ID}/plan.md` | all artifacts |

**Parallel Work**: `data-model.md` and `contracts/` can proceed simultaneously after research

**Rollback Strategy**: Delete incomplete artifacts, restart from last passed gate

> Track progress using checklist in `plan.md`. Check off each artifact as completed.

---

### `## 7. Execute`

**Signal**: Plan created → **Gate**: All 8 artifacts created

#### 7.1 Scaffold Artifacts

**Data Model** — Create `specs/changes/{CHANGE_ID}/data-model.md`:
| Component | Content |
|-----------|---------|
| Entity Overview | Table of entities, descriptions, storage |
| Entity Definitions | Fields, types, constraints, relationships |
| Indexes | Performance optimization indexes |
| State Diagrams | Lifecycle states (if applicable) |
| Migration Notes | Database migration considerations |

**Template**: `specs/templates/data-model-template.md`

**API Contracts** — Create `specs/changes/{CHANGE_ID}/contracts/`:
| Spec Requirement Type | Contract Pattern |
|-----------------------|------------------|
| "User can create X" | `POST /api/{RESOURCE}` |
| "User can view X" | `GET /api/{RESOURCE}/:id` |
| "User can list X" | `GET /api/{RESOURCE}` |
| "User can update X" | `PUT /api/{RESOURCE}/:id` |
| "User can delete X" | `DELETE /api/{RESOURCE}/:id` |

**Organization Structure**:
```
contracts/
├── {RESOURCE}/
│   ├── {OPERATION}.yaml    # e.g., users/list.yaml
│   └── {OPERATION}.yaml    # e.g., users/create.yaml
└── {RESOURCE}/
    └── {OPERATION}.yaml
```

**Quickstart Guide** — Create `specs/changes/{CHANGE_ID}/quickstart.md`:
| Section | Content |
|---------|---------|
| Overview | Brief feature description |
| Prerequisites | What's needed before using |
| Quick Integration | Step-by-step scenarios with code |
| API Reference | Endpoint table referencing contracts |
| Error Handling | Error codes and resolutions |
| Testing | Unit and integration test examples |

**Agent Context Update**:
```powershell
specs/scripts/update-agent-context.ps1 -AgentType copilot
if ($LASTEXITCODE -ne 0) {
    throw "update-agent-context.ps1 failed with exit code $LASTEXITCODE"
}
```

#### 7.2 Connect Artifacts

**Artifact Analysis** — Read and analyze:
- `research.md` — Technical decisions and rationale
- `data-model.md` — Entity definitions and relationships
- `contracts/*.yaml` — API contracts and operations
- `quickstart.md` — Integration scenarios

**Connection Mapping**:
| Connection Type | Source Artifact | Target Artifact | Relationship |
|-----------------|-----------------|-----------------|--------------|
| Data → API | `data-model.md` entities | `contracts/*.yaml` | Entity used in request/response |
| API → Integration | `contracts/*.yaml` endpoints | `quickstart.md` scenarios | Endpoint demonstrated in scenario |
| Research → Design | `research.md` decisions | All artifacts | Decision influences implementation |

**Output: design.md** — Create `specs/changes/{CHANGE_ID}/design.md`:
```markdown
# Design: {FEATURE_NAME}

## 1. Architecture Overview
[C4 diagram or text description of system context]

## 2. Component Architecture
### 2.1 Component Inventory
| Component | Type | Responsibility | Dependencies |
|-----------|------|----------------|--------------|

### 2.2 Component Interactions
[Sequence diagrams or interaction descriptions]

## 3. Data Architecture
### 3.1 Entity Relationships
[Reference to data-model.md with relationship diagrams]

### 3.2 Data Flow
[How data moves between components]

## 4. API Architecture
### 4.1 Endpoint Map
[Reference to contracts/ with endpoint summary]

### 4.2 API Dependencies
[Which endpoints depend on which entities/services]

## 5. Integration Architecture
### 5.1 External Integrations
[Third-party services, APIs, databases]

### 5.2 Internal Service Boundaries
[How internal services communicate]

## 6. Artifact Traceability Matrix
| Requirement | Data Model | API Contract | Quickstart | Test |
|-------------|------------|--------------|------------|------|
| REQ-001     | Entity-A   | POST /api/x  | Scenario-1 | TEST-001 |

## 7. Technology Decisions
[Reference to research.md with decision summary]
```

#### 7.3 Create Implementation Guide

**Output: implementation-guide.md** — Create `specs/changes/{CHANGE_ID}/implementation-guide.md`:
```markdown
# Implementation Guide: {FEATURE_NAME}

## 1. Implementation Sequence
| Order | Component | Dependencies | Estimated Effort |
|-------|-----------|--------------|------------------|
| 1     | Data Layer | None | 2 days |
| 2     | API Layer | Data Layer | 3 days |
| 3     | Integration | API Layer | 1 day |

## 2. Component Implementation Instructions

### 2.1 {Component-A}
**File**: `src/components/{component-a}/`
**Prerequisites**: {list dependencies}

**Steps**:
1. Create the directory structure
2. Implement the types (reference `data-model.md`)
3. Implement the repository
4. Implement the service

**Validation**:
- [ ] All types match data-model.md
- [ ] Repository operations work
- [ ] Service handles edge cases
- [ ] Unit tests pass

## 3. Coding Standards
[Reference Phase 5 Best Practices]

## 4. Pattern Library
[Design patterns to use with examples]

## 5. Anti-Patterns to Avoid
[Reference Phase 5 Anti-Patterns table]

## 6. Testing Strategy
[Unit, integration, and E2E testing approaches]

## 7. Integration Wiring
[Dependency injection and environment configuration]
```

#### 7.4 Synthesize Master Blueprint

**Key Distinction**: `design.md` is the **technical architecture** document. `blueprint.md` is the **project/delivery** document that references `design.md` for architecture details (does NOT duplicate).

**Output: blueprint.md** — Create `specs/changes/{CHANGE_ID}/blueprint.md`:
```markdown
# Master Blueprint: {FEATURE_NAME}

**Version**: 1.0
**Status**: Draft | Review | Approved
**Last Updated**: {DATE}
**Owner**: {TEAM/PERSON}

---

## Executive Summary
### Purpose
{One paragraph describing what this feature does and why it matters}

### Scope
| In Scope | Out of Scope |
|----------|--------------|

### Key Decisions
| Decision | Rationale | Reference |
|----------|-----------|-----------|

### Timeline
| Phase | Deliverable | Target Date |
|-------|-------------|-------------|

---

## Architecture Overview
{Reference design.md — 2-3 sentence summary, do NOT duplicate}

## Data Architecture
{Reference data-model.md}

## API Architecture
{Reference contracts/}

## Implementation Plan
{Reference implementation-guide.md}

## Testing Strategy
{Reference quickstart.md}

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|

## Success Criteria
### Functional
- [ ] All API contracts implemented and tested
### Non-Functional
- [ ] Response time < 200ms (p95)

---

## Artifact Index
| Artifact | Path | Purpose |
|----------|------|---------|
| Specification | `specs/changes/{CHANGE_ID}/spec.md` | Requirements |
| Research | `specs/changes/{CHANGE_ID}/research.md` | Technical decisions |
| Data Model | `specs/changes/{CHANGE_ID}/data-model.md` | Entity definitions |
| API Contracts | `specs/changes/{CHANGE_ID}/contracts/` | API specifications |
| Quickstart | `specs/changes/{CHANGE_ID}/quickstart.md` | Integration guide |
| Design | `specs/changes/{CHANGE_ID}/design.md` | Architecture |
| Implementation Guide | `specs/changes/{CHANGE_ID}/implementation-guide.md` | How to build |
| Plan | `specs/changes/{CHANGE_ID}/plan.md` | Project plan |
```

> Gate: All 8 artifacts exist and are complete.

---

### `## 8. Debug`

**Signal**: Errors encountered → **Gate**: Root cause fixed

- Use `problems` tool to check for lint/type errors in generated files
- If template not found: use `codebase` to search for alternative template paths
- If cross-reference broken: use `read_file` to verify target file exists and section name matches
- If validation script fails: read full error output

**Common Fixes**:
| Error Type | Cause | Fix |
|------------|-------|-----|
| Missing entity reference | Entity not in data-model.md | Add entity definition first |
| Invalid contract schema | YAML syntax error | Fix schema, validate with linter |
| Broken artifact link | Wrong path or section name | Verify path case-sensitivity |
| Template not found | Wrong template path | Search `specs/templates/` |
| Script failure | Missing dependency | Check script prerequisites |

**Process**:
1. Read full error message and context
2. Identify origin vs surface location
3. Fix source, not symptom — no error suppression
4. Re-run the failed step before proceeding

> Use `usages` tool to find all references to a broken artifact. Fix all references, not just the first.

---

### `## 9. Verify`

**Signal**: Artifacts created → **Gate**: All validation gates pass

**Pre-Step Gates**:

| Gate | Checks |
|------|--------|
| Pre-Step 1 | spec.md exists, constitution.md accessible, plan.md template copied |
| Pre-Step 2 | research.md exists, all `[NEEDS RESEARCH]` resolved, no placeholders |
| Pre-Step 3 | data-model.md has ≥1 entity, quickstart.md has ≥1 scenario, contracts/ has ≥1 file |
| Pre-Step 4 | design.md exists, all artifacts referenced, component map complete, traceability matrix populated |
| Pre-Step 5 | implementation-guide.md exists, sequence defined, all components have instructions |
| Post-Step 5 | blueprint.md exists, executive summary complete, all artifacts indexed, success criteria defined |

**Run Validation Script**:
```powershell
$RepoRoot = git rev-parse --show-toplevel
$validationResult = & "$RepoRoot/specs/scripts/validate.ps1" -Json
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ VALIDATION FAILED - Aborting workflow"
    Write-Host $validationResult
    exit 1
}
```

Parse JSON output:
- `status: "FAIL"` → **STOP workflow**, report errors
- `status: "WARNING"` → Log warnings, continue
- `status: "PASS"` → Proceed to completion

**Placeholder Sweep**:
```powershell
$featureId = $env:SPECIFY_CHANGE_ID
if (-not $featureId) {
    $featureId = (git rev-parse --abbrev-ref HEAD) -replace '^feature/', ''
}
$placeholders = Select-String -Path "specs/changes/$featureId/*" -Pattern "TBD|TODO|FIXME|\[insert\]|\[placeholder\]|{PLACEHOLDER}" -Exclude "*.log" -ErrorAction SilentlyContinue
if ($placeholders) {
    Write-Host "❌ PLACEHOLDERS FOUND in generated artifacts:"
    $placeholders | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber) - $($_.Line.Trim())" }
    exit 1
}
```

> Validation is not optional. If `validate.ps1` fails, DO NOT proceed.

---

### `## 10. Reflect`

**Signal**: Verification complete → **Gate**: Assessment documented

**Completion Report**:
```markdown
## Plan Phase Complete

**Branch**: {CURRENT_BRANCH}
**Feature**: {CHANGE_ID}

### Generated Artifacts

| Artifact | Path | Step | Status |
|----------|------|------|--------|
| plan.md | `specs/changes/{CHANGE_ID}/plan.md` | Setup | ✅ Created |
| research.md | `specs/changes/{CHANGE_ID}/research.md` | Step 1: Research | ✅ Created |
| data-model.md | `specs/changes/{CHANGE_ID}/data-model.md` | Step 2: Scaffold | ✅ Created |
| contracts/ | `specs/changes/{CHANGE_ID}/contracts/` | Step 2: Scaffold | ✅ Created ({N} files) |
| quickstart.md | `specs/changes/{CHANGE_ID}/quickstart.md` | Step 2: Scaffold | ✅ Created |
| design.md | `specs/changes/{CHANGE_ID}/design.md` | Step 3: Connect | ✅ Created |
| implementation-guide.md | `specs/changes/{CHANGE_ID}/implementation-guide.md` | Step 4: How's | ✅ Created |
| blueprint.md | `specs/changes/{CHANGE_ID}/blueprint.md` | Step 5: Master | ✅ Created |

### Workflow Summary

| Step | Objective | Output | Status |
|------|-----------|--------|--------|
| Step 1 | Thorough Research | research.md | ✅ Complete |
| Step 2 | Scaffold Artifacts | data-model, contracts, quickstart | ✅ Complete |
| Step 3 | Connect Artifacts | design.md (architecture) | ✅ Complete |
| Step 4 | Implementation How's | implementation-guide.md | ✅ Complete |
| Step 5 | Master Blueprint | blueprint.md | ✅ Complete |
```

**Constitution Check**:
- [ ] Spec-First Development
- [ ] File-Based Truth
- [ ] Validation Gates
- [ ] Dual-State Model
- [ ] AI-Ready Instructions

> Gate: Report generated, constitution check passed.

---

### `## 11. Iterate`

**Signal**: Reflection complete → **Gate**: All blocking issues resolved OR routed to fix

**Exit Blocked If**:
- Any of 8 artifacts missing
- `[NEEDS RESEARCH]` markers remain in any artifact
- Placeholder sweep finds `TODO`, `FIXME`, `TBD`, `[insert]`
- Validation script status is `FAIL`
- Cross-references between artifacts broken
- Constitution check fails

**Routing Matrix**:
| Gap | Route To |
|-----|----------|
| Missing codebase patterns | Phase 2: Investigate |
| Technology knowledge gap | Phase 4: Research |
| Artifact dependency wrong | Phase 6: Plan |
| Artifact error/bug | Phase 8: Debug |
| Incomplete artifact content | Phase 7: Execute |
| Validation failure | Phase 9: Verify |

**Discipline**:
- Log each iteration: `gap → phase → action taken`
- Same gap after 2 iterations → re-assess at Phase 6 (Plan)
- After any fix → Verify → Reflect → Iterate
- Exit only when ALL blocking criteria clear

**Exit**:
```
✅ Plan Phase Complete
Next: Run `/speckit.tasks` to generate task breakdown from blueprint.md
```
