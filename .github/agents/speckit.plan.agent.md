---
description: Execute the implementation planning workflow, generating research, scaffolded artifacts, architectural blueprint (design.md), implementation guidance, and master blueprint synthesis.
tools:
  - search/codebase
  - edit/editFiles
  - search
  - runCommands
  - fetch
  - githubRepo
  - context7
  - problems
  - usages
  - new
handoffs:
  - label: Create Tasks
    agent: speckit.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: speckit.checklist
    prompt: Create a checklist for the following domain...
---

# User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

# Purpose

Generate the **complete design artifact set** for a SpecKit feature:

| Artifact | Location | Phase | Required |
|----------|----------|-------|----------|
| `plan.md` | `specs/changes/{CHANGE_ID}/plan.md` | Setup | ✅ Yes |
| `research.md` | `specs/changes/{CHANGE_ID}/research.md` | Phase 4 | ✅ Yes |
| `data-model.md` | `specs/changes/{CHANGE_ID}/data-model.md` | Phase 7 | ✅ Yes |
| `contracts/` | `specs/changes/{CHANGE_ID}/contracts/*.yaml` | Phase 7 | ✅ Yes |
| `quickstart.md` | `specs/changes/{CHANGE_ID}/quickstart.md` | Phase 7 | ✅ Yes |
| `design.md` | `specs/changes/{CHANGE_ID}/design.md` | Phase 7 | ✅ Yes |
| `implementation-guide.md` | `specs/changes/{CHANGE_ID}/implementation-guide.md` | Phase 7 | ✅ Yes |
| `blueprint.md` | `specs/changes/{CHANGE_ID}/blueprint.md` | Phase 7 | ✅ Yes |

**This agent MUST create all 8 artifact types before completing.**

# Placeholder Conventions

Use these placeholder styles consistently:
- **SpecKit paths and artifact templates**: single braces (e.g., `{CHANGE_ID}`, `{FEATURE_NAME}`, `{RESOURCE}`, `{OPERATION}`, `{DATE}`, `{TEAM/PERSON}`, `{CURRENT_BRANCH}`, `{N}`)
- **Context7 tool-call templates**: double braces (e.g., `{{libraryName}}`, `{{libraryId}}`, `{{topic}}`, `{{mode}}`, `{{page}}`)

Replace placeholders with concrete values when generating real artifacts or executing tool calls.

# Outline

1. **Comprehend**: Run prerequisites check; run setup-plan; load spec/constitution/project; extract markers; define success criteria.
2. **Investigate**: Scan codebase patterns; check templates; confirm validate/update scripts; capture naming conventions.
3. **Fetch**: Retrieve user URLs and core files; validate sections; stop if missing.
4. **Research**: Resolve all `[NEEDS...]` using Context7 (mcp_context7_resolve-library-id + mcp_context7_get-library-docs), fetch, githubRepo, and codebase; create research.md.
5. **Best Practices**: Derive standards and anti-patterns from codebase patterns.
6. **Plan**: Define artifact order, dependencies, and rollback strategy.
7. **Execute**: Scaffold data-model/contracts/quickstart → connect artifacts into architectural blueprint (design.md) → write the how's (implementation guide) → synthesize master blueprint (blueprint.md); update agent context.
8. **Debug**: Fix errors, broken references, and template/path issues.
9. **Verify**: Run validation gates and placeholder sweep.
10. **Reflect**: Produce completion report and constitution check.
11. **Iterate**: Route gaps back to phases until exit criteria met.

# Phases

## Phase 1: Comprehend

**Signal**: Request received → **Gate**: Requirements extracted, success criteria defined

**Actions**:
- Run `specs/scripts/check-prerequisites.ps1 -Json`
    ```pwsh
    if ($LASTEXITCODE -ne 0) {
      throw "Prerequisites check failed. Ensure you are in a valid feature branch with `spec.md` created. Run /speckit.specify first."
    }
    ```
    Parse JSON output and verify `FEATURE_SPEC` points to an existing file. If `spec.md` doesn't exist, **STOP** and run `/speckit.specify` first.
- Run `specs/scripts/setup-plan.ps1 -Json`
    ```pwsh
    if ($LASTEXITCODE -ne 0) {
            throw "setup-plan.ps1 failed with exit code $LASTEXITCODE"
    }
    ```
- Read `specs/changes/{CHANGE_ID}/spec.md` for feature requirements
- Read `specs/memory/constitution.md` for governance constraints
- Read `specs/project.md` for tech stack: languages, frameworks, APIs, infrastructure
- Extract markers:
    - `[NEEDS RESEARCH: ...]`
    - `[NEEDS CLARIFICATION: ...]`
    - Technology choices without rationale
    - Integration points without contracts
- Define success criteria: **all 8 artifacts must be created**

**Gate**: `spec.md` readable, `constitution.md` accessible, `plan.md` template initialized, all markers cataloged.

## Phase 2: Investigate

**Signal**: Requirements extracted → **Gate**: Codebase patterns documented

**Actions**:
- Use `codebase` to search `src/` for existing implementation patterns
- Check `specs/templates/` for artifact templates:
    | Template | Purpose |
    |----------|---------|
    | `research-template.md` | Research findings structure |
    | `data-model-template.md` | Entity definitions |
    | `quickstart-template.md` | Integration guide |
    | `plan-template.md` | Implementation plan |
- If `design.md`, `implementation-guide.md`, or `blueprint.md` templates are missing, use the structures defined in Phase 7 and record the gap.
- Search existing `specs/changes/*/` directories for artifact structure patterns
- Document naming conventions from existing files
- Validate `specs/scripts/validate.ps1` and `specs/scripts/update-agent-context.ps1` exist
- Identify exemplar files to reference for each artifact type

**Rule**: Document what IS (discovered patterns), not what SHOULD BE. Skip generic observations.

**Gate**: Patterns documented, templates located, naming conventions captured.

## Phase 3: Fetch

**Signal**: Patterns documented → **Gate**: All inputs accessible

**Actions**:
- Use `fetch` to retrieve any user-provided URLs
- Read core files using `read_file`:
    - `specs/changes/{CHANGE_ID}/spec.md` → **STOP if missing**
    - `specs/memory/constitution.md` → **STOP if missing**
    - `specs/project.md` → **STOP if missing**
- Parse user input from `$ARGUMENTS` for additional context
- Validate all three core files contain expected sections
- Fetch external documentation for any third-party libraries mentioned in `specs/project.md`

**Gate**: All required files accessible. If any missing, report error with path and halt workflow.

## Phase 4: Research

**Signal**: Inputs accessible → **Gate**: All unknowns resolved, `research.md` created

**Objective**: Resolve all `[NEEDS RESEARCH]` items and technical unknowns using tools (`mcp_context7_resolve-library-id`, `mcp_context7_get-library-docs`, `fetch`, `githubRepo`, `codebase`). Research findings become the **foundation for artifact creation** in Phase 7.

### Context Sources

Use these inputs to ground research decisions:
- `specs/changes/{CHANGE_ID}/spec.md` (feature requirements)
- `specs/memory/constitution.md` (governance and constraints)
- `specs/project.md` (tech stack: languages, frameworks, APIs, infrastructure)

### Input Analysis

Extract from Technical Context all items marked:
- `[NEEDS RESEARCH: ...]`
- `[NEEDS CLARIFICATION: ...]`
- Technology choices without rationale
- Integration points without contracts

### Research Process

For each unknown:
1. Identify the specific question
2. If the question involves selecting or confirming programming languages, frameworks, or tooling, **use tools** to validate the choice and document the rationale
3. Use `mcp_context7_resolve-library-id` + `mcp_context7_get-library-docs` to fetch up-to-date library documentation (see Context7 Research Pattern below)
4. Use `fetch` to access external documentation
5. Use `githubRepo` to examine reference implementations
6. Use `codebase` to search existing patterns
7. Document decision with rationale

### Context7 Research Pattern

**ALWAYS use Context7 (mcp_context7_* tools) for library/framework research.** Follow this two-step process:

**Placeholder Guidance**:
- `{{libraryName}}`: multi-word query or package name (framework + vendor + domain)
- `{{libraryId}}`: value returned from resolve step (format like `/org/project`)
- `{{topic}}`: 4–5 terms with functions, paths, or errors
- `{{conceptTopic}}`: conceptual phrasing for architecture/decisions
- `{{mode}}`: `code` or `info` (lowercase)
- `{{page}}`: number 1–10
- Use double-brace placeholders only inside Context7 tool-call templates.
- Replace placeholders with concrete values before calling the tool.

**Step A - Resolve Library ID**:
- **Do**: Use multi-word queries, include versions from `specs/project.md`, add technology context, include framework for variants
- **Don't**: Use single-word queries, use boolean operators (AND/OR)
- **Selection criteria**: Maximum coverage (highest snippet count), highest quality (benchmark score), specific version when required

**Step B - Get Library Docs**:
- **Do**: Use compound topics (4–5 terms), include function names or file paths, use exact error message text, use `mode: "info"` for conceptual guidance, paginate with `page: 1..10`
- **Don't**: Use single-word topics, use boolean operators, use uppercase values for `mode`, use `page` outside 1–10
- **Mode selection**: `mode: "code"` for implementation/syntax (default), `mode: "info"` for concepts/architecture
- **Pagination**: Use `page: 1-10` for more results. Stop when you see "=== LAST PAGE ===".

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
mcp_context7_resolve-library-id({ libraryName: "{{libraryName}}" })

// Fetch documentation (after resolve)
mcp_context7_get-library-docs({
  context7CompatibleLibraryID: "{{libraryId}}",
  topic: "{{topic}}",
  mode: "{{mode}}",
  page: {{page}}
})

// Conceptual guidance (use mode: "info")
mcp_context7_get-library-docs({
  context7CompatibleLibraryID: "{{libraryId}}",
  topic: "{{conceptTopic}}",
  mode: "info"
})
```

**Concrete Examples**:

**Example 1: Researching Zod for validation schema**
```typescript
// Step A: Resolve Zod library ID
mcp_context7_resolve-library-id({ libraryName: "zod typescript validation schema" })
// Returns: { libraryId: "/websites/zod_dev", snippets: 112000 }

// Step B: Get validation patterns
mcp_context7_get-library-docs({
  context7CompatibleLibraryID: "/websites/zod_dev",
  topic: "schema object validation optional default",
  mode: "code",
  page: 1
})
```

**Example 2: Researching Prisma for data model**
```typescript
// Step A: Resolve Prisma library ID
mcp_context7_resolve-library-id({ libraryName: "prisma orm database schema" })
// Returns: { libraryId: "/prisma/docs", snippets: 45000 }

// Step B: Get schema definition patterns
mcp_context7_get-library-docs({
  context7CompatibleLibraryID: "/prisma/docs",
  topic: "model relation one-to-many foreign key",
  mode: "code",
  page: 1
})

// Step B (conceptual): Get architecture guidance
mcp_context7_get-library-docs({
  context7CompatibleLibraryID: "/prisma/docs",
  topic: "database schema design best practices",
  mode: "info",
  page: 1
})
```

**Example 3: Researching Next.js API routes for contracts**
```typescript
// Step A: Resolve Next.js library ID
mcp_context7_resolve-library-id({ libraryName: "next.js vercel react framework" })
// Returns: { libraryId: "/vercel/next.js", snippets: 89000 }

// Step B: Get API route patterns
mcp_context7_get-library-docs({
  context7CompatibleLibraryID: "/vercel/next.js",
  topic: "api routes handler request response POST GET",
  mode: "code",
  page: 1
})
```

**Example 4: Researching Vitest for testing strategy**
```typescript
// Step A: Resolve Vitest library ID
mcp_context7_resolve-library-id({ libraryName: "vitest testing framework" })
// Returns: { libraryId: "/vitest-dev/vitest", snippets: 32000 }

// Step B: Get mocking patterns
mcp_context7_get-library-docs({
  context7CompatibleLibraryID: "/vitest-dev/vitest",
  topic: "mock function spy module vi.fn vi.mock",
  mode: "code",
  page: 1
})
```

**When to Use Each Tool**:
| Situation | Tool | Example Query |
|-----------|------|---------------|
| Library/framework docs | `mcp_context7_resolve-library-id` + `mcp_context7_get-library-docs` | "prisma relation cascade delete" |
| External API documentation | `fetch` | URL to REST API docs |
| Reference implementation | `githubRepo` | Search for similar feature |
| Existing project patterns | `codebase` | Search `src/` for validation pattern |

### Research-to-Artifact Mapping

Research findings directly inform artifact creation:

| Research Topic | Informs Artifact | How It's Used |
|----------------|------------------|---------------|
| Entity/data structures | `data-model.md` | Defines entities, fields, relationships, constraints |
| API patterns/conventions | `contracts/*.yaml` | Determines endpoint structure, request/response schemas |
| Integration patterns | `quickstart.md` | Shapes integration scenarios and code examples |
| Architecture decisions | `design.md` | Drives component boundaries and data flow |
| Implementation patterns | `implementation-guide.md` | Provides coding standards and pattern library |
| Technology rationale | `blueprint.md` | Documents decisions in executive summary |

### Output: research.md

Create `specs/changes/{CHANGE_ID}/research.md` using template `specs/templates/research-template.md`:

| Section | Content |
|---------|---------|
| Research Summary | Table of topics, decisions, confidence levels |
| Detailed Findings | Per-topic: question, decision, rationale, alternatives, sources |
| Resolved Items | Mapping from original `[NEEDS...]` to resolution |
| Artifact Implications | How each finding affects artifact creation |
| Remaining Unknowns | Any items that couldn't be resolved |

**GATE**: All `[NEEDS RESEARCH]` items resolved before proceeding. Each finding must have an artifact implication documented.

## Phase 5: Best Practices

**Signal**: Research complete → **Gate**: Standards defined from codebase

**Actions**:
- Extract coding standards from `specs/project.md`
- Use `codebase` to search for error handling patterns in `src/errors/` or `src/middleware/`
- Use `codebase` to search for validation patterns in `src/validators/` or `src/api/`

**Gate**: Coding standards documented, anti-patterns listed, patterns derived from codebase.

## Phase 6: Plan

**Signal**: Standards defined → **Gate**: Artifact sequence created with dependencies

**Artifact Creation Order**:
| Order | Artifact | Path | Dependencies |
|-------|----------|------|--------------|
| 1 | research.md | `specs/changes/{CHANGE_ID}/research.md` | `spec.md`, `constitution.md`, `project.md` |
| 2 | data-model.md | `specs/changes/{CHANGE_ID}/data-model.md` | research.md |
| 3 | contracts/*.yaml | `specs/changes/{CHANGE_ID}/contracts/` | data-model.md |
| 4 | quickstart.md | `specs/changes/{CHANGE_ID}/quickstart.md` | contracts/ |
| 5 | design.md | `specs/changes/{CHANGE_ID}/design.md` | all scaffold artifacts |
| 6 | implementation-guide.md | `specs/changes/{CHANGE_ID}/implementation-guide.md` | design.md |
| 7 | blueprint.md | `specs/changes/{CHANGE_ID}/blueprint.md` | all previous artifacts |
| 8 | plan.md (finalize) | `specs/changes/{CHANGE_ID}/plan.md` | all artifacts |

**Actions**:
- Update `plan.md` with artifact order, dependencies, and checklist items.
- Document rollback strategy in `plan.md` (delete incomplete artifacts, restart from last passed gate).

**Gate**: Artifact sequence defined, dependencies mapped, rollback strategy documented.

## Phase 7: Execute

**Signal**: Plan created → **Gate**: All 8 artifacts created

### Scaffold Artifacts

**Data Model** — Create `specs/changes/{CHANGE_ID}/data-model.md` using `specs/templates/data-model-template.md`:

| Component | Content |
|-----------|---------|
| Entity Overview | Table of entities, descriptions, storage |
| Entity Definitions | Fields, types, constraints, relationships |
| Indexes | Performance optimization indexes |
| State Diagrams | Lifecycle states (if applicable) |
| Migration Notes | Database migration considerations |

**API Contracts** — Create `specs/changes/{CHANGE_ID}/contracts/{RESOURCE}/{OPERATION}.yaml` for each endpoint using the standard CRUD patterns:

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
│   ├── {OPERATION}.yaml    # e.g., users/list.yaml, users/create.yaml
│   └── {OPERATION}.yaml    # e.g., auth/login.yaml, auth/logout.yaml
└── {RESOURCE}/
    └── {OPERATION}.yaml
```

**File Naming Convention**:
- **Resource folder**: lowercase resource name (e.g., `users`, `products`, `auth`)
- **Operation file**: lowercase operation name (e.g., `list`, `create`, `get`, `update`, `delete`, `login`, `logout`)

**Quickstart Guide** — Create `specs/changes/{CHANGE_ID}/quickstart.md` using `specs/templates/quickstart-template.md`:

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
        throw "update-agent-context.ps1 failed with exit code $LASTEXITCODE. Review output above for details."
}
```

### Connect Artifacts (Architectural Blueprint)

**Prerequisites**: All scaffold artifacts complete (`data-model.md`, `contracts/`, `quickstart.md`).

**Objective**: Analyze relationships between all scaffolded artifacts and create a unified architectural view in `design.md`.

**Artifact Analysis** — Read and analyze all scaffolded artifacts:
- `specs/changes/{CHANGE_ID}/research.md` - Technical decisions and rationale
- `specs/changes/{CHANGE_ID}/data-model.md` - Entity definitions and relationships
- `specs/changes/{CHANGE_ID}/contracts/*.yaml` - API contracts and operations
- `specs/changes/{CHANGE_ID}/quickstart.md` - Integration scenarios

**Connection Mapping** — Identify and document connections between artifacts:
| Connection Type | Source Artifact | Target Artifact | Relationship |
|-----------------|-----------------|-----------------|--------------|
| Data → API | `data-model.md` entities | `contracts/*.yaml` | Entity used in request/response |
| API → Integration | `contracts/*.yaml` endpoints | `quickstart.md` scenarios | Endpoint demonstrated in scenario |
| Research → Design | `research.md` decisions | All artifacts | Decision influences implementation |

**Output: design.md** — Create `specs/changes/{CHANGE_ID}/design.md` with:
| Section | Content |
|---------|---------|
| Architecture Overview | High-level system diagram (C4 Context/Container level) |
| Component Map | All components with responsibilities and boundaries |
| Data Flow Diagrams | How data moves through the system |
| Integration Points | External systems and internal service boundaries |
| Dependency Graph | Which artifacts depend on which |
| Technology Stack | Languages, frameworks, libraries with versions |
| Cross-Cutting Concerns | Security, logging, error handling, validation |
| Artifact Traceability | Matrix showing how artifacts connect |

**design.md Structure**:
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

**GATE**: `design.md` must have all sections populated with connections to scaffolded artifacts.

### Implementation Guide (The How's)

**Prerequisites**: `specs/changes/{CHANGE_ID}/design.md` complete with all connections mapped.

**Objective**: Generate Copilot-style implementation instructions that define how to implement each component.

**Instruction Generation Pattern** — Follow the GitHub Copilot instructions pattern:
- Use imperative language ("Create", "Implement", "Configure")
- Be specific with file paths, function names, and patterns
- Include code snippets for non-obvious implementations
- Define success criteria for each instruction

**Output: implementation-guide.md** — Create `specs/changes/{CHANGE_ID}/implementation-guide.md` with:
| Section | Content |
|---------|---------|
| Implementation Sequence | Ordered list of what to implement first |
| Component Instructions | Per-component implementation steps |
| Coding Standards | Project-specific conventions to follow |
| Pattern Library | Design patterns to use with examples |
| Anti-Patterns | What to avoid with rationale |
| Testing Strategy | How to test each component |
| Integration Steps | How to wire components together |

**implementation-guide.md Structure**:
```markdown
# Implementation Guide: {FEATURE_NAME}

## 1. Implementation Sequence

Execute in this order to minimize rework:

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

### Naming Conventions
| Element | Convention | Example |
|---------|------------|---------|
| Files | kebab-case | `user-service.ts` |
| Classes | PascalCase | `UserService` |
| Functions | camelCase | `createUser()` |

## 4. Pattern Library
[Design patterns to use with examples]

## 5. Anti-Patterns to Avoid
| Anti-Pattern | Why Avoid | Instead Do |
|--------------|-----------|------------|

## 6. Testing Strategy
[Unit, integration, and E2E testing approaches]

## 7. Integration Wiring
[Dependency injection and environment configuration]
```

Reference `.github/copilot-instructions.md` for the logic/standards used when generating the how's.

**GATE**: `implementation-guide.md` must have actionable instructions for every component in `design.md`.

### Master Architectural Blueprint

**Prerequisites**: All previous artifacts complete (`research.md`, `data-model.md`, `contracts/`, `quickstart.md`, `design.md`, `implementation-guide.md`).

**Objective**: Synthesize all artifacts into a single authoritative document that serves as the complete technical reference.

**Blueprint Synthesis** — Combine insights from all artifacts into a cohesive **stakeholder-facing** master document:
- Executive summary for non-technical stakeholders
- Project delivery perspective (roadmap, risks, success criteria)
- Cross-references to technical artifacts (does NOT duplicate them)
- Decision log with rationale

**Key distinction**: `design.md` is the **technical architecture** document. `blueprint.md` is the **project/delivery** document that references `design.md` for architecture details.

**Output: blueprint.md** — Create `specs/changes/{CHANGE_ID}/blueprint.md` with:
| Section | Content |
|---------|---------|
| Executive Summary | One-page overview for stakeholders (non-technical) |
| Feature Scope | What's included and excluded |
| Architecture Reference | Link to `design.md` with 2-3 sentence summary (do NOT duplicate) |
| Implementation Roadmap | Phased delivery plan with timeline |
| Risk Assessment | Technical and delivery risks with mitigations |
| Success Criteria | How to measure completion (functional + non-functional) |
| Artifact Index | Links to all supporting documents (navigation, not content duplication) |
| Appendices | Glossary, acronyms, external references |

**blueprint.md Structure**:
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
{Reference design.md — do NOT duplicate content}

## Data Architecture
{Reference data-model.md — do NOT duplicate content}

## API Architecture
{Reference contracts/ — do NOT duplicate content}

## Implementation Plan
{Reference implementation-guide.md — do NOT duplicate content}

## Testing Strategy
{Reference quickstart.md — do NOT duplicate content}

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

**GATE**: `blueprint.md` must cross-reference all other artifacts and provide complete project specification.

Finalize `specs/changes/{CHANGE_ID}/plan.md` with all sections filled, checklist updated, and no `[NEEDS...]` markers.

**Gate**: All 8 artifacts exist and are complete.

## Phase 8: Debug

**Signal**: Errors encountered → **Gate**: Root cause fixed

**Actions**:
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

**Rule**: Use `usages` tool to find all references to a broken artifact. Fix all references, not just the first.

**Gate**: All errors resolved, no suppressed exceptions, failed steps re-run successfully.

## Phase 9: Verify

**Signal**: Artifacts created → **Gate**: All validation gates pass

**Actions**:
- Run all validation gates (Pre-Phase 4, Pre-Phase 7, Post-Phase 7)
- Run validation script:
  ```powershell
  $RepoRoot = git rev-parse --show-toplevel
  $validationResult = & "$RepoRoot/specs/scripts/validate.ps1" -Json
  if ($LASTEXITCODE -ne 0) {
      Write-Host "❌ VALIDATION FAILED - Aborting workflow"
      Write-Host $validationResult
      exit 1
  }
  ```
- Parse JSON output:
  - `status: "FAIL"` → **STOP workflow**, report errors
  - `status: "WARNING"` → Log warnings, continue
  - `status: "PASS"` → Proceed to completion
- Perform placeholder sweep:
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

**Rule**: Validation is not optional. If `validate.ps1` fails, DO NOT proceed.

**Gate**: All validation gates pass, placeholder sweep clean, validation script returns PASS.

## Phase 10: Reflect

**Signal**: Verification complete → **Gate**: Assessment documented

**Actions**:
- Generate completion report with all 8 artifacts listed
- Run constitution check against all 5 principles:
  - [ ] Spec-First Development — All changes started with `spec.md`
  - [ ] File-Based Truth — All artifacts in `specs/changes/{CHANGE_ID}/`
  - [ ] Validation Gates — All gates passed before proceeding
  - [ ] Dual-State Model — Active work in `specs/changes/`
  - [ ] AI-Ready Instructions — Imperative, testable language used
- Document workflow summary with phase-by-phase status

**Completion Report Template**:
```markdown
## Plan Phase Complete

**Branch**: {CURRENT_BRANCH}
**Feature**: {CHANGE_ID}

### Generated Artifacts
| Artifact | Path | Status |
|----------|------|--------|
| plan.md | `specs/changes/{CHANGE_ID}/plan.md` | ✅ Created |
| research.md | `specs/changes/{CHANGE_ID}/research.md` | ✅ Created |
| data-model.md | `specs/changes/{CHANGE_ID}/data-model.md` | ✅ Created |
| contracts/ | `specs/changes/{CHANGE_ID}/contracts/` | ✅ Created ({N} files) |
| quickstart.md | `specs/changes/{CHANGE_ID}/quickstart.md` | ✅ Created |
| design.md | `specs/changes/{CHANGE_ID}/design.md` | ✅ Created |
| implementation-guide.md | `specs/changes/{CHANGE_ID}/implementation-guide.md` | ✅ Created |
| blueprint.md | `specs/changes/{CHANGE_ID}/blueprint.md` | ✅ Created |

### Constitution Check
- [x] Spec-First Development
- [x] File-Based Truth
- [x] Validation Gates
- [x] Dual-State Model
- [x] AI-Ready Instructions
```

**Gate**: Report generated and constitution check passed.

## Phase 11: Iterate

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

# Validation Gates

## Pre-Phase 4 Gate

- [ ] `specs/changes/{CHANGE_ID}/spec.md` exists and is readable
- [ ] `specs/memory/constitution.md` accessible
- [ ] `specs/changes/{CHANGE_ID}/plan.md` template copied successfully

## Pre-Phase 7 Gate

- [ ] `specs/changes/{CHANGE_ID}/research.md` exists
- [ ] All `[NEEDS RESEARCH]` items resolved
- [ ] Technical Context has no placeholders

## Post-Phase 7 Gate

- [ ] `specs/changes/{CHANGE_ID}/data-model.md` exists with at least 1 entity
- [ ] `specs/changes/{CHANGE_ID}/contracts/` exists with at least 1 contract file
- [ ] `specs/changes/{CHANGE_ID}/quickstart.md` exists with at least 1 scenario
- [ ] `specs/changes/{CHANGE_ID}/design.md` exists with all artifacts referenced
- [ ] `specs/changes/{CHANGE_ID}/implementation-guide.md` exists with implementation sequence
- [ ] `specs/changes/{CHANGE_ID}/blueprint.md` exists with executive summary and artifact index
- [ ] `specs/changes/{CHANGE_ID}/plan.md` fully populated with no `[NEEDS...]` markers
- [ ] Constitution Check passed

# Validate Generated Artifacts

Run validation script:
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
- If `status: "FAIL"` → STOP workflow, report errors
- If `status: "WARNING"` → Log warnings, continue
- If `status: "PASS"` → Proceed to completion

Error types:
- **FAIL**: Missing required sections, constitution violations, broken references
- **WARNING**: Placeholder markers, style inconsistencies

**Placeholder Sweep**: After validation passes, run placeholder detection:
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

If placeholders are detected, STOP workflow and report each occurrence with file path and line number.

# Completion Report

After generating all artifacts, output:

```markdown
# Plan Phase Complete

**Branch**: {CURRENT_BRANCH}
**Feature**: {CHANGE_ID}

## Generated Artifacts

| Artifact | Path | Status |
|----------|------|--------|
| plan.md | `specs/changes/{CHANGE_ID}/plan.md` | ✅ Created |
| research.md | `specs/changes/{CHANGE_ID}/research.md` | ✅ Created |
| data-model.md | `specs/changes/{CHANGE_ID}/data-model.md` | ✅ Created |
| contracts/ | `specs/changes/{CHANGE_ID}/contracts/` | ✅ Created ({N} files) |
| quickstart.md | `specs/changes/{CHANGE_ID}/quickstart.md` | ✅ Created |
| design.md | `specs/changes/{CHANGE_ID}/design.md` | ✅ Created |
| implementation-guide.md | `specs/changes/{CHANGE_ID}/implementation-guide.md` | ✅ Created |
| blueprint.md | `specs/changes/{CHANGE_ID}/blueprint.md` | ✅ Created |

## Constitution Check

- [x] Spec-First Development
- [x] File-Based Truth
- [x] Validation Gates
- [x] Dual-State Model
- [x] AI-Ready Instructions

## Next Step

Run `/speckit.tasks` to generate the task breakdown.
```

# Key Rules

1. **ALL 8 ARTIFACTS REQUIRED**: `plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`, `design.md`, `implementation-guide.md`, `blueprint.md`
2. **PHASE-BASED WORKFLOW**: Comprehend → Investigate → Fetch → Research → Best Practices → Plan → Execute → Debug → Verify → Reflect → Iterate (no skipping phases)
3. **USE TOOLS FOR RESEARCH**: Always use `mcp_context7_resolve-library-id`, `mcp_context7_get-library-docs`, `fetch`, `githubRepo`, `codebase` for thorough research in Phase 4
4. **SCAFFOLD BEFORE CONNECTING**: Phase 7 must scaffold data-model/contracts/quickstart before connecting artifacts into design.md
5. **CONNECT BEFORE SYNTHESIZING**: design.md must map all artifact relationships before implementation-guide.md
6. **COPILOT-STYLE INSTRUCTIONS**: implementation-guide.md follows GitHub Copilot instructions pattern (imperative, specific, actionable)
7. **MASTER BLUEPRINT IS STAKEHOLDER-FACING**: `blueprint.md` references technical artifacts (does NOT duplicate them)
8. **USE REPO-RELATIVE PATHS**: Prefer `specs/...` references; scripts provide absolute paths via JSON when needed
9. **NO PLACEHOLDERS IN FINAL OUTPUT**: Replace all `[NEEDS...]` markers
10. **VALIDATE GATES**: Each phase has entry and exit criteria
11. **ERROR ON FAILURE**: Do not proceed if prerequisites missing



