---
description: Execute the implementation planning workflow, generating research, scaffolded artifacts, architectural blueprint (`design.md`), implementation guidance, and master blueprint synthesis.
tools:
  ['vscode/getProjectSetupInfo', 'vscode/installExtension', 'vscode/newWorkspace', 'vscode/runCommand', 'execute/getTerminalOutput', 'execute/runInTerminal', 'read/problems', 'read/readFile', 'read/terminalSelection', 'read/terminalLastCommand', 'edit/editFiles', 'search', 'web', 'context7/*']
handoffs:
  - label: Create Tasks
    agent: speckit.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: speckit.checklist
    prompt: Create a checklist for the following domain...
---

# Quick Reference

## Phase Execution Sequence
1. **COMPREHEND**: Run check-prerequisites.ps1 → Initialize Change ID → Load context files
2. **INVESTIGATE**: Read templates → Scan codebase patterns → Identify exemplars
3. **FETCH**: Fetch URLs from $ARGUMENTS → Anchor knowledge from spec/constitution/project
4. **RESEARCH**: Call context7_resolve-library-id → Call context7_get-library-docs → Create research.md
5. **BEST PRACTICES**: Search codebase for standards → Document patterns
6. **PLAN**: Define artifact sequence → Update plan.md with dependencies
7. **EXECUTE**: Create all 8 artifacts using research.md patterns
8. **DEBUG**: Run problems tool → Fix errors → Re-run failed steps
9. **VERIFY**: Run validate.ps1 → Sweep for placeholders → Confirm PASS
10. **REFLECT**: Generate completion report → Run constitution check
11. **ITERATE**: IF all gates pass THEN EXIT ELSE loop back to failed phase

## Action Card Legend
ACTION: [Verb] [Object] | Tool: tool_name | Input: parameters | Expect: success condition | OnFail: recovery action

---

# User Input
$ARGUMENTS
You MUST consider the user input before proceeding (if not empty).

# Purpose

**CREATE these 8 artifacts before completing**:
1. CREATE plan.md at specs/changes/{CHANGE_ID}/plan.md (Setup)
2. CREATE research.md at specs/changes/{CHANGE_ID}/research.md (Phase 4)
3. CREATE data-model.md at specs/changes/{CHANGE_ID}/data-model.md (Phase 7)
4. CREATE contracts/ directory with YAML files at specs/changes/{CHANGE_ID}/contracts/*.yaml (Phase 7)
5. CREATE quickstart.md at specs/changes/{CHANGE_ID}/quickstart.md (Phase 7)
6. CREATE design.md at specs/changes/{CHANGE_ID}/design.md (Phase 7)
7. CREATE implementation-guide.md at specs/changes/{CHANGE_ID}/implementation-guide.md (Phase 7)
8. CREATE blueprint.md at specs/changes/{CHANGE_ID}/blueprint.md (Phase 7)

# Placeholder Conventions

Use these placeholder styles consistently:
- **SpecKit paths and artifact templates**: single braces (e.g., `{CHANGE_ID}`, `{FEATURE_NAME}`, `{RESOURCE}`, `{OPERATION}`, `{DATE}`, `{TEAM/PERSON}`, `{CURRENT_BRANCH}`, `{N}`)
- **Context7 tool-call templates**: double braces (e.g., `{{libraryName}}`, `{{libraryId}}`, `{{topic}}`, `{{mode}}`, `{{page}}`)

Replace placeholders with concrete values when generating real artifacts or executing tool calls.

# Governance & Protocols

### I. Core Rules
- **200-Line Rule**: Never read >200 lines in one `read_file` call. Loop with increments.
- **Gate-First**: Pass all gate checks before proceeding to next phase.
- **Research-First**: Patterns from research.md Context7 findings only (Benchmark 80+).

### II. Script Output Schema
ALL SpecKit scripts return JSON with this structure:
- **status**: `success` | `validation_error` | `operation_error`
- **timestamp**: ISO 8601 format
- **script**: Script name that emitted the result
- **data**: Payload object with results
- **errors**: Array of error strings (empty on success)
- **warnings**: Array of warning strings

### III. Exit Codes
- **0 (Success)**: All prerequisites met, operation completed
- **1 (Validation)**: Prerequisites not met (missing file, wrong branch)
- **2 (Operation)**: Runtime error during execution

### II. Logic Gates
- **IF** `spec.md` missing **THEN** STOP → Run `/speckit.specify`
- **IF** Context7 called **THEN** document libraryId + findings in research.md
- **IF** research.md pattern identified **THEN** apply to all artifacts

### III. Context7 Selection Criteria
- Benchmark Score **80+**
- Snippet Count **5k+**
- Source Reputation: **High**

# Workflow

**EXECUTE phases 1-11 in sequence. Pass each GATE before advancing.**

---

## Phase 1: Comprehend

> **Gate**: Requirements extracted, Change ID initialized

### DO 1.1: Check Prerequisites
**Tool**: run_in_terminal
**Command**: pwsh -File specs/scripts/check-prerequisites.ps1 -Json
**Params**: goal="Check prerequisites", isBackground=false, timeout=30000

**Expected JSON Output**:
status: "success"
data.FEATURE_SPEC: absolute path to spec.md
data.IMPL_PLAN: absolute path to plan.md
data.CHANGE_ID: e.g. "003-simple-calculator"
data.REPO_ROOT: absolute path to repo
data.AVAILABLE_DOCS: array of existing doc filenames

**Parse & Store for Later Steps**:
- CHANGE_ID → use in all artifact paths
- REPO_ROOT → use for absolute path construction
- FEATURE_DIR → specs/changes/{CHANGE_ID}/

**Note**: For single quotes in args use escape: 'I'\''m Groot' (or double-quote: "I'm Groot")
**Pass**: status=success AND data.FEATURE_SPEC exists
**Fail**: STOP → Handoff to `/speckit.specify` to create spec.md first

### DO 1.2: Setup Plan
**Tool**: run_in_terminal
**Command**: pwsh -File specs/scripts/setup-plan.ps1 -Json
**Params**: goal="Setup plan artifacts", isBackground=false, timeout=60000

**Expected JSON Output**:
status: "success"
data.IMPL_PLAN: path to created plan.md
data.RESEARCH_FILE: path to created research.md  
data.DATA_MODEL_FILE: path to created data-model.md
data.QUICKSTART_FILE: path to created quickstart.md
data.CONTRACTS_DIR: path to created contracts/ directory

**Creates**: Template copies of plan.md, research.md, data-model.md, quickstart.md + empty contracts/ directory
**Pass**: status=success AND exit code 0
**Fail (exit 1)**: Missing spec.md → Handoff to `/speckit.specify`
**Fail (exit 2)**: Operation error → Read data.error + data.suggestion → fix → retry

### DO 1.3: Load Context
**Tool**: read_file (call 3 times, use 200-line chunks if files are large)

**File 1**: specs/changes/{CHANGE_ID}/spec.md
read_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/spec.md")
**Extract**: User stories, acceptance criteria, requirements (REQ-NNN), priorities (P1/P2/P3), scenarios
**Store**: Requirements list for artifact traceability

**File 2**: specs/memory/constitution.md  
read_file(filePath="{REPO_ROOT}/specs/memory/constitution.md")
**Extract**: Governance rules, principles, forbidden patterns
**Store**: Constraints for constitution check in Phase 10

**File 3**: specs/project.md
read_file(filePath="{REPO_ROOT}/specs/project.md")
**Extract**: Tech stack, libraries, folder structure, conventions
**Store**: Tech context for research queries in Phase 4

### DO 1.4: Initialize Change ID
1. Check `$env:SPECIFY_CHANGE_ID` → use if set
2. Fallback: `git rev-parse --abbrev-ref HEAD`

### DO 1.5: Extract Markers
Scan for: `[NEEDS RESEARCH]` | `[NEEDS CLARIFICATION]` | Unrationed tech choices | Missing contracts

### DO 1.6: Define Success Criteria
8 artifacts required: plan.md + research.md + data-model.md + contracts/ + quickstart.md + design.md + implementation-guide.md + blueprint.md

### GATE 1: ✓ spec.md readable | ✓ constitution.md accessible | ✓ Change ID set | ✓ Markers cataloged

---

## Phase 2: Investigate
> **Gate**: Templates loaded, patterns documented

### DO 2.1: Load Templates
Read specs/templates/research-template.md, data-model-template.md, quickstart-template.md, plan-template.md

### DO 2.2: Search Codebase
Search src/ for patterns, search specs/changes/*/ for structures

### DO 2.3: Validate Scripts
Read specs/scripts/validate.ps1 and update-agent-context.ps1

### DO 2.4: Identify Exemplars
Scan reference files in specs/changes/*/

---

## Phase 3: Fetch
> **Gate**: All inputs accessible

### DO 3.1: Fetch URLs
Fetch all URLs from $ARGUMENTS. On fail: log and continue.

### DO 3.2: Anchor Knowledge
Read spec.md, constitution.md, project.md. On fail: STOP.

### DO 3.3: Parse Supplementary
Scan $ARGUMENTS and project.md for library references.

---

## Phase 4: Research

> **Gate**: research.md created with all unknowns resolved

**DO**: Resolve ALL `[NEEDS RESEARCH]` items. research.md drives Phase 7 artifact creation.

**Read These Files** (200-line chunks):
1. Read specs/changes/{CHANGE_ID}/spec.md → Extract feature requirements
2. Read specs/memory/constitution.md → Extract governance and constraints
3. Read specs/project.md → Extract tech stack info

### DO 4.1: Catalog Research Items

1. Search spec.md for `[NEEDS RESEARCH: ...]` markers
2. Search spec.md for `[NEEDS CLARIFICATION: ...]` markers
3. List technology choices without rationale
4. List integration points without contracts

### DO 4.2: Execute Context7 Research

**For EACH unknown, run these 2 tools**:

#### Step A: Resolve Library ID
Run context7_resolve-library-id with libraryName: "multi-word query"
Expect: context7CompatibleLibraryID + snippets count + benchmarkScore
Prioritize: Benchmark 80+ AND Snippets 5k+ AND High Reputation

#### Step B: Get Library Docs
Run context7_get-library-docs with context7CompatibleLibraryID, topic: "4-5 terms", mode: "code", page: 1
Expect: Code patterns, configuration, best practices
Paginate: Increment page until "=== LAST PAGE ==="

**Topic Format**: 4-5 words, include function names, use natural language (no AND/OR)

**IF Context7 returns result THEN** Extract findings → Document in research.md
**IF Context7 unavailable THEN** Use fetch for external docs
**IF Insufficient results THEN** Use codebase for existing patterns

### DO 4.3: Document Findings
Create specs/changes/{CHANGE_ID}/research.md with these sections per topic:
1. Question: What needs to be decided
2. Tool Used: Context7 / fetch / codebase
3. Key Findings: 2-3 bullet points with direct quotes
4. Code Examples: Extracted from Context7 response
5. Decision: Final choice
6. Rationale: Why this choice
7. Artifact Impact: Which artifacts use this, how

**Critical Rule**: If Context7 is called, research.md MUST document:
- [ ] libraryId returned
- [ ] Key findings with quotes
- [ ] Code examples from response
- [ ] How findings inform artifact creation

### Context7 Quick Reference

**USE these Library IDs** (Benchmark 80+ / Snippets 5k+):
- React: /reactjs/react.dev (45k snippets)
- Next.js: /vercel/next.js (89k snippets)
- Zod: /websites/zod_dev (112k snippets)
- Prisma: /prisma/docs (45k snippets)
- Drizzle: /drizzle-team/drizzle-orm-docs (28k snippets)
- shadcn/ui: /shadcn-ui/ui (15k snippets)
- Vitest: /vitest-dev/vitest (32k snippets)
- Zustand: /pmndrs/zustand (12k snippets)
- PowerShell: /microsoftdocs/powershell-docs (18k, 87.9 benchmark)

**PRIORITIZE**: Benchmark 80+ THEN Snippets 5k+ THEN High Reputation

**Context7 Tool Call Pattern**:
1. Run context7_resolve-library-id({ libraryName: "zod typescript validation" }) → Returns libraryID + snippets + benchmarkScore
2. Run context7_get-library-docs({ context7CompatibleLibraryID: "/websites/zod_dev", topic: "schema object validation optional", mode: "code", page: 1 })
3. IF more pages exist THEN increment page and repeat until "=== LAST PAGE ==="

**MODE**: Use "code" for implementation syntax (default), use "info" for concepts/architecture
**TOPIC**: 4-5 words, include function names, use exact error message text for debugging

### Research-to-Artifact Mapping
**APPLY research findings to these artifacts**:
- Entity/data structures → data-model.md (field types, validation rules)
- API patterns → contracts/*.yaml (endpoint structure, schemas)
- Integration patterns → quickstart.md (code examples, client usage)
- Architecture decisions → design.md (component boundaries, data flow)
- Implementation patterns → implementation-guide.md (coding standards, pattern library)
- Technology rationale → blueprint.md (decision log with sources)

### DO 4.4: Create research.md
Run create_file at specs/changes/{CHANGE_ID}/research.md
Base on specs/templates/research-template.md

**INCLUDE these sections**:
1. Research Summary (topics, decisions, confidence)
2. Detailed Findings (per-topic with Context7 sources)
3. Resolved Items (mapping from [NEEDS...] to resolution)
4. Artifact Implications (how each finding affects artifacts)
- [ ] Context7 Knowledge Extraction (all calls documented)
- [ ] Remaining Unknowns (if any)

### GATE 4: VERIFY before proceeding
1. CONFIRM all [NEEDS RESEARCH] items resolved
2. CONFIRM research.md exists
3. CONFIRM Context7 findings documented with libraryId
4. CONFIRM artifact implications specified
**IF any check fails THEN continue research**

---

## Phase 5: Best Practices
> **Gate**: Standards defined from codebase

### DO 5.1: Extract Standards
Read specs/project.md and identify: naming conventions, directory structure, code style rules, testing requirements, documentation standards

### DO 5.2: Search Error Patterns
Search src/errors/ and src/middleware/ for: error class definitions, error handling middleware, error response formats, logging patterns

### DO 5.3: Search Validation Patterns
Search src/validators/ and src/api/ for: input validation schemas, request/response types, authentication patterns, authorization rules

---

## Phase 6: Plan
> **Gate**: Artifact sequence created

**CREATE artifacts in this order** (each depends on previous):
1. research.md (depends on: spec.md, constitution.md, project.md)
2. data-model.md (depends on: research.md)
3. contracts/*.yaml (depends on: data-model.md)
4. quickstart.md (depends on: contracts/)
5. design.md (depends on: all scaffold artifacts)
6. implementation-guide.md (depends on: design.md)
7. blueprint.md (depends on: all previous)
8. plan.md (depends on: all artifacts)

**ON FAILURE**: Delete incomplete artifact → restart from last gate

---

## Phase 7: Execute

> **Gate**: All 8 artifacts created

**RULE**: Use ONLY patterns from research.md Context7 findings. NO generic LLM patterns.

### DO 7.1: Anchor Context
**Tool**: read_file
read_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/research.md")
**Extract & Hold in Working Memory**: libraryId, code patterns, validation rules, entity definitions from Context7 findings

### DO 7.2: Create data-model.md
**Tool**: read_file THEN create_file (or replace_string_in_file if template exists)

**Step 1**: Read template
read_file(filePath="{REPO_ROOT}/specs/templates/data-model-template.md")

**Step 2**: Create artifact
create_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/data-model.md", content="...filled template...")

**Fill these sections**:
   - **Entity Overview**: List all entities with brief descriptions
   - **Entity Definitions**: For each entity define: name, fields (name/type/required/default), relationships, constraints
   - **Indexes**: Primary keys, foreign keys, unique constraints, search indexes
   - **Validation Rules**: Field-level validation (min/max/pattern), cross-field validation, business rules
3. Verify: Field types (string/number/boolean/date/array/object) match research.md decisions from Context7

### DO 7.3: Create contracts/
**Tool**: create_file (multiple calls for directory structure)

**Step 1**: Create directory structure
create_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/contracts/{RESOURCE}/create.yaml", content="...")
create_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/contracts/{RESOURCE}/get.yaml", content="...")
create_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/contracts/{RESOURCE}/list.yaml", content="...")
create_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/contracts/{RESOURCE}/update.yaml", content="...")
create_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/contracts/{RESOURCE}/delete.yaml", content="...")

**For each YAML file, include**:
   - **create.yaml**: POST /{resource} - request body schema, response schema, success/error codes
   - **get.yaml**: GET /{resource}/:id - path params, response schema, 404 handling
   - **list.yaml**: GET /{resource} - query params (pagination/filter/sort), response array schema
   - **update.yaml**: PUT /{resource}/:id - request body, response schema, optimistic locking
   - **delete.yaml**: DELETE /{resource}/:id - response schema, cascade behavior
3. All schema types MUST reference data-model.md entity definitions

### DO 7.4: Create quickstart.md
**Tool**: read_file + create_file + run_in_terminal

**Step 1**: Read template
read_file(filePath="{REPO_ROOT}/specs/templates/quickstart-template.md")

**Step 2**: Create artifact
create_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/quickstart.md", content="...filled template...")

**Fill these sections**:
- **Overview**: What the feature does, key capabilities, target users
- **Prerequisites**: Required dependencies, environment setup, configuration
- **Quick Integration**: Step-by-step code examples to get started (use Context7 patterns from research.md)
- **API Reference**: Endpoint summary table, authentication, rate limits
- **Error Handling**: Error codes, retry logic, fallback behavior
- **Testing**: Example test cases, mock data, integration test setup

**Step 3**: Update agent context
**Tool**: run_in_terminal
**Command**: pwsh -File specs/scripts/update-agent-context.ps1 -AgentType copilot -Json
**Params**: goal="Update agent context", isBackground=false, timeout=30000
**Expect JSON**: {status: "success"} → Agent context updated

### DO 7.5: Create design.md
**Prerequisites**: data-model.md + contracts/ + quickstart.md must exist
**Tool**: create_file

create_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/design.md", content="...")

**Fill these sections**:
   - **Architecture Overview**: High-level system diagram, component interactions, data flow
   - **Component Architecture**: Each component with responsibility, dependencies, interfaces
   - **Data Architecture**: Data stores, caching strategy, data lifecycle, migrations
   - **API Architecture**: API versioning, authentication flow, rate limiting, error handling strategy
   - **Integration Architecture**: External service integrations, event-driven patterns, message queues
   - **Artifact Traceability**: Link each design decision to source artifact (data-model.md, contracts/, research.md)
   - **Technology Decisions**: Rationale for each tech choice with Context7 source citations

### DO 7.6: Create implementation-guide.md
**Tool**: create_file

create_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/implementation-guide.md", content="...")

**Fill these sections**:
   - **Implementation Sequence**: Ordered list of implementation steps with dependencies
   - **Component Instructions**: For each component: setup steps, key files to create/modify, dependencies to install
   - **Coding Standards**: Naming conventions, file structure, comment style, import ordering
   - **Pattern Library**: Reusable code patterns from research.md Context7 findings with source citations
   - **Anti-Patterns**: Common mistakes to avoid with explanations
   - **Testing Strategy**: Unit test requirements, integration test setup, test coverage targets
   - **Integration Wiring**: How components connect, event flows, API calls between services

### DO 7.7: Create blueprint.md
**Tool**: create_file

create_file(filePath="{REPO_ROOT}/specs/changes/{CHANGE_ID}/blueprint.md", content="...")

**Fill these sections**:
   - **Executive Summary**: One-paragraph feature overview for stakeholders
   - **Feature Scope**: In-scope deliverables, out-of-scope items, success metrics
   - **Architecture Reference**: Link to design.md with key architecture decisions summary
   - **Implementation Roadmap**: Phased delivery plan with milestones and estimated effort
   - **Risk Assessment**: Technical risks, mitigation strategies, fallback plans
   - **Success Criteria**: Measurable acceptance criteria, performance targets, quality gates
   - **Artifact Index**: Links to all generated artifacts with brief descriptions

**NOTE**: design.md = technical architecture | blueprint.md = project/delivery document for stakeholders

### DO 7.8: Finalize plan.md
1. Open: `specs/changes/{CHANGE_ID}/plan.md`
2. Remove: ALL `[NEEDS...]` markers
3. Verify: All artifact paths are correct

### GATE 7: Verify 8 Artifacts Exist
✓ research.md ✓ data-model.md ✓ contracts/ ✓ quickstart.md ✓ design.md ✓ implementation-guide.md ✓ blueprint.md ✓ plan.md

---

## Phase 8: Debug
> **Gate**: All errors resolved

### DO 8.1: Check Errors
**Tool**: get_errors
get_errors(filePaths=["{REPO_ROOT}/specs/changes/{CHANGE_ID}"])
**Returns**: Array of {file, line, message, severity}
**Store**: Error list for fixing

### DO 8.2: Diagnose
**Match each error to fix action**:
- Missing entity → add to data-model.md
- YAML syntax error → fix schema in contracts/*.yaml  
- Broken link → verify path case matches filesystem
- Undefined reference → add definition to source artifact

### DO 8.3: Apply Fixes
**Tool**: replace_string_in_file (for each fix)
**CRITICAL**: Fix source not symptom. Run grep_search to find all references before fixing.

replace_string_in_file(filePath="{artifact_path}", oldString="{broken_content}", newString="{fixed_content}")

**After each fix**: Re-run get_errors to verify fix worked

---

## Phase 9: Verify
> **Gate**: Validation PASS, no placeholders

### DO 9.1: Run Validation
**Tool**: run_in_terminal
**Command**: pwsh -File specs/scripts/validate.ps1 -Json
**Params**: goal="Run validation", isBackground=false, timeout=60000

**Expected JSON Output**:
status: "success" | "validation_error"
data.artifacts_validated: number of artifacts checked
data.missing_artifacts: array of missing artifact paths
data.placeholder_count: number of unfilled placeholders
data.errors: array of validation errors

**Pass**: status=success AND data.placeholder_count=0
**Fail (exit 1)**: Review data.missing_artifacts → create missing → retry
**Fail (exit 2)**: Operation error → read data.error → fix → retry

### DO 9.2: Placeholder Sweep
**Tool**: grep_search
grep_search(query="TBD|TODO|FIXME|\\[placeholder\\]|\\[NEEDS", isRegexp=true, includePattern="specs/changes/{CHANGE_ID}/**")

**If matches found**: STOP → Replace each placeholder in the artifact → Re-run sweep
**If no matches**: Proceed to Phase 10

**IF FAIL THEN** STOP immediately
**IF WARNING THEN** Log and continue
**IF PASS THEN** Proceed to Phase 10

**RULE**: Validation is NOT optional. IF validate.ps1 fails THEN DO NOT proceed.

---

## Phase 10: Reflect

> **Gate**: Assessment documented

**Completion Report**: Output artifact status table (all 8 artifacts with ✅/❌)

**Constitution Check**: Spec-First, File-Based Truth, Validation Gates, Dual-State, AI-Ready Instructions

---

## Phase 11: Iterate
> **Gate**: EXIT or LOOP

**IF all 8 artifacts exist THEN** EXIT
**IF missing artifacts THEN** Loop back to Phase 7
**IF validation failures THEN** Loop back to Phase 8
**IF research gaps THEN** Loop back to Phase 4

**EXIT when**: 8 artifacts ✓ + Validation PASS ✓ + No placeholders ✓ + Constitution check ✓

**OUTPUT**: "✅ Plan Phase Complete. Next: Run /speckit.tasks"

---

## Appendix A: Gate Checklists

**Pre-Phase 4**: VERIFY spec.md exists AND constitution.md accessible AND plan.md template copied

**Pre-Phase 7**: VERIFY research.md exists AND no placeholders AND Context7 knowledge documented with libraryId AND Research-to-Artifact mapping complete

**Post-Phase 7**: VERIFY all 8 artifacts exist AND Constitution check passed AND Research knowledge applied to each artifact with source citations

**Context7 Knowledge**: REQUIRE libraryId documented → Key findings extracted (2-3 points) → Code examples included → Artifact implications specified

---

## Appendix B: Key Rules

1. **Gate-First Execution**: If prerequisite gate passes, proceed; else fix blocker.
2. **Anchor-Based Scaffolding**: If generating artifacts, use `research.md` as primary anchor; else re-read `research.md`.
3. **Phase Integrity**: If current phase complete, advance; else iterate until Gate satisfies.
4. **Context7 Anchoring**: If unknowns exist, resolve via Context7; else use codebase patterns.
5. **No Placeholders**: If placeholders found, STOP; else continue verification.
6. **Path Precision**: If referencing files, use repo-relative paths (`specs/...`); else fail.
7. **Traceability**: If artifact created, trace to `research.md` decision; else fix artifact.
