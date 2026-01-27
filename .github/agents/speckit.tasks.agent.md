---
description: Generate an actionable, dependency-ordered `FEATURE_DIR/tasks.md` (typically `specs/changes/{CHANGE_ID}/tasks.md`) for the feature based on available design artifacts.
handoffs:
  - label: Analyze For Consistency
    agent: speckit.analyze
    prompt: Run a project analysis for consistency
    send: true
  - label: Implement Project
    agent: speckit.implement
    prompt: Start the implementation in phases
    send: true
---

# # User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

# # Outline

1. **Setup**: From repo root, resolve the absolute script path and run prerequisites to avoid positional parsing errors:

   ```powershell
   # Use repo root detection for absolute path
   $RepoRoot = git rev-parse --show-toplevel
   $prereqResult = & "$RepoRoot/specs/scripts/check-prerequisites.ps1" -Json
   ```

   **Validation**: After running the script, check the exit code:
   ```powershell
   if ($LASTEXITCODE -ne 0) {
      Write-Host "❌ Prerequisite check failed with exit code $LASTEXITCODE"
      throw "check-prerequisites.ps1 failed with exit code $LASTEXITCODE"
   }
   ```
   If `$LASTEXITCODE -ne 0`, **STOP** workflow immediately. Report error with context: script name, exit code, and any error output. Do NOT proceed to next step until error is resolved.

   Parse FEATURE_DIR, CHANGE_ID, and AVAILABLE_DOCS. FEATURE_DIR is the absolute path to the active change (typically `specs/changes/{CHANGE_ID}`) returned by the script. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load design documents**: Read from FEATURE_DIR (typically `specs/changes/{CHANGE_ID}`):
   - **Required**: `FEATURE_DIR/plan.md` (tech stack, libraries, structure), `FEATURE_DIR/spec.md` (user stories with priorities)
   - **Required**: `specs/memory/constitution.md` (governance principles, quality standards)
   - **Required**: `specs/project.md` (tech stack, code style, architecture patterns, testing strategy, folder structure)
   - **Optional**: `specs/changes/{CHANGE_ID}/data-model.md` (entities), `specs/changes/{CHANGE_ID}/contracts/` (API endpoints), `specs/changes/{CHANGE_ID}/research.md` (decisions), `specs/changes/{CHANGE_ID}/quickstart.md` (test scenarios)
   - Note: Not all projects have all documents. Generate tasks based on what's available.

2.5. **Extract conventions from `specs/project.md` for accurate task generation** (see step 2.5b for implementation):
   - **Folder Structure**: Use actual project folders from Domain Context section (e.g., `src/components/ui/`, `src/lib/`, `src/server/`)
   - **File Naming**: Apply conventions (PascalCase for components, camelCase for utilities, kebab-case for routes)
   - **Architecture Patterns**: Generate tasks following project's component organization (Atomic Design vs feature-based), layer structure (Controller→Service→Repository)
   - **Testing Strategy**: Include test tasks matching project's frameworks (Vitest/Jest/Playwright) and coverage targets
   - **Tech Stack**: Reference exact technologies (e.g., "Create Zod schema" not generic "Create validation", "Add shadcn/ui Button component" not generic "Add button component")
   - **CRITICAL**: Task file paths MUST match actual project folder structure from project.md; replace any placeholder tokens (`{SRC_ROOT}`, `{TESTS_ROOT}`, `{CHANGE_ID}`, etc.) with the concrete paths extracted in step 2.5b

2.5a. **Load Design Artifacts for Citation** (OPTIONAL - only if artifacts exist):

   Extract referenceable items from each artifact to enable task citations:

   ```powershell
   # Anchor normalization function
   function Get-NormalizedAnchor {
       param([string]$text)
       # Convert to lowercase, replace spaces/underscores with hyphens, remove non-alphanum
       $text.ToLower() -replace '[_\s]+', '-' -replace '[^a-z0-9-]', ''
   }

   # Load data-model.md entities
   if (Test-Path "$FeatureDir/data-model.md") {
       $dataModel = Get-Content "$FeatureDir/data-model.md" -Raw
       $entities = ($dataModel | Select-String -Pattern "### (.+)" -AllMatches).Matches | ForEach-Object {
           $name = $_.Groups[1].Value
           $anchor = Get-NormalizedAnchor $name
           @{ Name = $name; Anchor = $anchor }
       }
       Write-Host "📊 Loaded $($entities.Count) entities from data-model.md"
   }

   # Load contracts/**/*.yaml endpoints (recursive search for subfolders)
   if (Test-Path "$FeatureDir/contracts/") {
       $contracts = Get-ChildItem "$FeatureDir/contracts/**/*.yaml" -ErrorAction SilentlyContinue
       $endpoints = @()
       foreach ($contract in $contracts) {
           $yaml = Get-Content $contract.FullName -Raw
           # Extract endpoint paths (line numbers for anchors)
           $pathMatches = Select-String -Path $contract.FullName -Pattern "path:\s*(.+)" -AllMatches
           foreach ($match in $pathMatches) {
               $endpoints += @{
                   Path = $match.Matches[0].Groups[1].Value.Trim()
                   File = $contract.Name
                   Line = $match.LineNumber
               }
           }
       }
       Write-Host "🔌 Loaded $($endpoints.Count) endpoints from contracts"
   }

   # Load research.md decisions
   if (Test-Path "$FeatureDir/research.md") {
       $research = Get-Content "$FeatureDir/research.md" -Raw
       $decisions = ($research | Select-String -Pattern "(DEC-\d+|RES-\d+|### [^#]+)" -AllMatches).Matches | ForEach-Object {
           $value = $_.Value
           if ($value -match "^### (.+)") {
               $name = $Matches[1]
               $anchor = Get-NormalizedAnchor $name
           } else {
               $anchor = $value.ToLower()
           }
           @{ Value = $value; Anchor = $anchor }
       }
       Write-Host "🔬 Loaded $($decisions.Count) decisions from research.md"
   }

   # Load quickstart.md scenarios
   if (Test-Path "$FeatureDir/quickstart.md") {
       $quickstart = Get-Content "$FeatureDir/quickstart.md" -Raw
       $scenarios = ($quickstart | Select-String -Pattern "### (.+)" -AllMatches).Matches | ForEach-Object {
           $name = $_.Groups[1].Value
           $anchor = Get-NormalizedAnchor $name
           @{ Name = $name; Anchor = $anchor }
       }
       Write-Host "🎬 Loaded $($scenarios.Count) scenarios from quickstart.md"
   }
   ```

   **Artifact Citation Format** (using normalized anchors):
    - **Entities**: `EntityName` (link: `{DATA_MODEL_ENTITY_LINK}`, kebab-case anchor)
    - **Endpoints**: `GET /api/users` (link: `{CONTRACT_LINK}`, line number anchor)
    - **Decisions**: `DEC-001` (link: `{DECISION_LINK}`) or `Decision Heading` (link: `{DECISION_HEADING_LINK}`, normalized anchor)
    - **Scenarios**: `Scenario Name` (link: `{SCENARIO_LINK}`, kebab-case anchor)

   **Anchor Normalization Function** (add to PowerShell code):
   ```powershell
   function Get-NormalizedAnchor {
       param([string]$text)
       # Convert to lowercase, replace spaces/underscores with hyphens, remove non-alphanum
       $text.ToLower() -replace '[_\s]+', '-' -replace '[^a-z0-9-]', ''
   }
   # Usage: $anchor = Get-NormalizedAnchor "Entity Name"  # returns "entity-name"
   ```

2.5b. **Parse Project Conventions from `specs/project.md`** (REQUIRED):

   Extract folder structure and naming conventions to generate tasks with concrete paths:

   ```powershell
   # Load project.md
   if (Test-Path "specs/project.md") {
       $projectMd = Get-Content "specs/project.md" -Raw
       Write-Host "📋 Loading project conventions from specs/project.md"

       # Extract folder structure (from "## Folder Structure" or "## Domain Context" section)
       if ($projectMd -match '## (Folder Structure|Domain Context)(.*?)(?=##|$)') {
           $folderSection = $Matches[2]

           # Parse common folder paths (src/, tests/, docs/, config/, etc.)
           $srcRoot = if ($folderSection -match '`([^`]+/src/?[^`]*)`') { $Matches[1] } else { 'src/' }
           $testsRoot = if ($folderSection -match '`([^`]+/tests?/?[^`]*)`') { $Matches[1] } else { 'tests/' }
           $docsRoot = if ($folderSection -match '`([^`]+/docs?/?[^`]*)`') { $Matches[1] } else { 'docs/' }
           $configRoot = if ($folderSection -match '`([^`]+/config/?[^`]*)`') { $Matches[1] } else { 'config/' }

           Write-Host "  ├─ Source root: $srcRoot"
           Write-Host "  ├─ Tests root: $testsRoot"
           Write-Host "  ├─ Docs root: $docsRoot"
           Write-Host "  └─ Config root: $configRoot"
       }

       # Extract naming conventions (from "## Naming Conventions", "## Code Style", or "## Architecture Patterns")
       $namingRules = @()
       if ($projectMd -match '## (Naming Conventions|Code Style)(.*?)(?=##|$)') {
           $namingSection = $Matches[2]

           # Parse file naming patterns
           if ($namingSection -match 'PascalCase') { $namingRules += "Components: PascalCase" }
           if ($namingSection -match 'camelCase') { $namingRules += "Utilities: camelCase" }
           if ($namingSection -match 'kebab-case') { $namingRules += "Routes: kebab-case" }
           if ($namingSection -match 'snake_case') { $namingRules += "Python files: snake_case" }

           Write-Host "📝 Naming conventions: $($namingRules -join ', ')"
       }

       # Extract architecture patterns (component organization, layer structure)
       if ($projectMd -match '## Architecture Patterns(.*?)(?=##|$)') {
           $archSection = $Matches[1]
           if ($archSection -match '(Atomic Design|Feature-based|Controller→Service→Repository|MVC)') {
               $archPattern = $Matches[1]
               Write-Host "🏛️ Architecture pattern: $archPattern"
           }
       }
   } else {
       Write-Host "⚠️ specs/project.md not found - using default paths"
       $srcRoot = 'src/'
       $testsRoot = 'tests/'
       $docsRoot = 'docs/'
       $configRoot = 'config/'
   }
   ```

   **Path Template Replacements**:
   - Replace `{SRC_ROOT}` with `$srcRoot` variable value (e.g., `src/`, `app/src/`, `lib/`)
   - Replace `{TESTS_ROOT}` with `$testsRoot` variable value (e.g., `tests/`, `test/`, `__tests__/`)
   - Replace `{DOCS_ROOT}` with `$docsRoot` variable value
   - Replace `{CONFIG_ROOT}` with `$configRoot` variable value
   - Replace `{CHANGE_ID}` with the actual feature identifier
   - Apply naming conventions to generated file names in task descriptions

   **Example Concrete Paths** (after replacement):
   - ❌ Before: `"Create User model in {SRC_ROOT}/models/user.py"`
   - ✅ After: `"Create User model in src/models/user.py"` (if project.md shows `src/`)
   - ✅ After: `"Create User model in app/lib/models/user.dart"` (if project.md shows `app/lib/`)

3. **Execute task generation workflow**:
   - Load `FEATURE_DIR/plan.md` and extract tech stack, libraries, project structure
   - Load `FEATURE_DIR/spec.md` and extract user stories with their priorities (P1, P2, P3, etc.)
   - **If `specs/changes/{CHANGE_ID}/data-model.md` exists**: Extract entities/fields and generate entity-specific tasks:
     - Task description format: "Create EntityName (link: `specs/changes/{CHANGE_ID}/data-model.md#entityname`) model in {IMPLEMENTATION_FILE_PATH}"
     - Example: "- [ ] T010 [P] [US1] Create User entity (link: `specs/changes/{CHANGE_ID}/data-model.md#user`) in src/models/user.py"
     - Entity anchor format: lowercase entity name (e.g., `#user`, `#product`, `#orderitem`)
   - **If `specs/changes/{CHANGE_ID}/contracts/` exists**: For each contract file and endpoint, generate tasks:
     - Task description format: "Implement GET /api/path (link: `specs/changes/{CHANGE_ID}/contracts/{RESOURCE}/{OPERATION}.yaml#L10`) in {HANDLER_FILE_PATH}"
     - Example: "- [ ] T015 [US1] Implement GET /api/users (link: `specs/changes/{CHANGE_ID}/contracts/users/list.yaml#L12`) in src/routes/users.ts"
     - Use line number anchors from artifact loading step
   - **If `specs/changes/{CHANGE_ID}/research.md` exists**: Extract decisions (with IDs/headings) and embed into setup/config tasks:
     - Task description format: "Apply DEC-001 (link: `specs/changes/{CHANGE_ID}/research.md#dec-001`) for {DECISION_TOPIC}"
     - Example: "- [ ] T003 Apply DEC-001 (link: `specs/changes/{CHANGE_ID}/research.md#dec-001`) for logger selection in src/config/logger.ts"
     - Decision anchor format: lowercase decision ID (e.g., `#dec-001`, `#res-002`)
   - **If `specs/changes/{CHANGE_ID}/quickstart.md` exists**: Extract scenario names and generate integration test tasks:
     - Task description format: "Implement Scenario Name test (link: `specs/changes/{CHANGE_ID}/quickstart.md#scenario-name`) in {TEST_FILE_PATH}"
     - Example: "- [ ] T025 [US2] Implement User Registration Flow test (link: `specs/changes/{CHANGE_ID}/quickstart.md#user-registration-flow`) in tests/integration/user-flow.spec.ts"
     - Scenario anchor format: kebab-case heading (e.g., `#user-registration-flow`, `#password-reset`)
   - Generate tasks organized by user story (see Task Generation Rules below)
   - Generate dependency graph showing user story completion order
   - Create parallel execution examples per user story
   - Validate task completeness (each user story has all needed tasks, independently testable)

4. **Generate `FEATURE_DIR/tasks.md`**: Use `specs/templates/tasks-template.md` as structure, fill with:
   - Correct feature name from `FEATURE_DIR/plan.md`
   - **REQUIRED: Source File Traceability section** documenting all files read during generation:
     - List each source file with absolute/relative path
     - For each source file, specify which sections/lines were read
     - Map each source file to the task phases/IDs it influenced
     - Include: agent files, templates, spec.md, plan.md, constitution.md, project.md, data-model.md, contracts/, research.md, quickstart.md
     - Show validation cross-reference table confirming format compliance, coverage, and traceability
   - Phase 1: Setup tasks (project initialization)
   - Phase 2: Foundational tasks (blocking prerequisites for all user stories)
   - Phase 3+: One phase per user story (in priority order from `FEATURE_DIR/spec.md`)
   - Each phase includes: story goal, independent test criteria, tests (if requested), implementation tasks
   - **Artifact Citations in Task Descriptions** (when artifacts exist):
    - Entity tasks: Link to data-model.md sections (e.g., `Create User model (link: {DATA_MODEL_ENTITY_LINK})`)
    - Endpoint tasks: Link to contract files with line numbers (e.g., `Implement GET /api/users (link: {CONTRACT_LINK})`)
    - Config tasks: Link to research decisions (e.g., `Apply DEC-001 (link: {DECISION_LINK})`)
    - Test tasks: Link to quickstart scenarios (e.g., `Test Login Flow (link: {SCENARIO_LINK})`)
   - Final Phase: Polish & cross-cutting concerns
   - All tasks must follow the strict checklist format (see Task Generation Rules below)
   - Clear file paths for each task (implementation files from project.md conventions)
   - Dependencies section showing story completion order
   - Parallel execution examples per story
   - Implementation strategy section (MVP first, incremental delivery)

5. **Validate Generated Artifact**

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

6. **Report**: Output path to generated `FEATURE_DIR/tasks.md` (typically `specs/changes/{CHANGE_ID}/tasks.md`) and summary:
   - Total task count
   - Task count per user story
   - Parallel opportunities identified
   - Independent test criteria for each story
   - Suggested MVP scope (typically just User Story 1)
   - Format validation: Confirm ALL tasks follow the checklist format (checkbox, ID, labels, file paths)
   - **Source file traceability**: Confirm all source files are documented in the "Source File Traceability" section with:
     - File paths (absolute or relative)
     - Sections/lines read from each file
     - Task IDs influenced by each source file
     - Validation cross-reference showing format compliance and coverage

Context for task generation: $ARGUMENTS

`FEATURE_DIR/tasks.md` should be immediately executable - each task must be specific enough that an LLM can complete it without additional context.

# # Task Generation Rules

**CRITICAL**: Tasks MUST be organized by user story to enable independent implementation and testing.

**Tests are OPTIONAL**: Only generate test tasks if explicitly requested in the feature specification or if user requests TDD approach.

## # Checklist Format (REQUIRED)

Every task MUST strictly follow this format:

```text
- [ ] [TaskID] [P?] [Story?] Description with file path
```

**Format Components**:

1. **Checkbox**: ALWAYS start with `- [ ]` (markdown checkbox)
2. **Task ID**: Sequential number (T001, T002, T003...) in execution order
3. **[P] marker**: Include ONLY if task is parallelizable (different files, no dependencies on incomplete tasks)
4. **[Story] label**: REQUIRED for user story phase tasks only
   - Format: [US1], [US2], [US3], etc. (maps to user stories from `FEATURE_DIR/spec.md`)
   - Setup phase: NO story label
   - Foundational phase: NO story label
   - User Story phases: MUST have story label
   - Polish phase: NO story label
5. **Description**: Clear action with exact file path

**Examples**:

- ✅ CORRECT: `- [ ] T001 Create project structure per implementation plan`
- ✅ CORRECT: `- [ ] T005 [P] Implement authentication middleware in src/middleware/auth.py`
- ✅ CORRECT: `- [ ] T012 [P] [US1] Create User model in src/models/user.py`
- ✅ CORRECT: `- [ ] T014 [US1] Implement UserService in src/services/user_service.py`
- ❌ WRONG: `- [ ] Create User model` (missing ID and Story label)
- ❌ WRONG: `T001 [US1] Create model` (missing checkbox)
- ❌ WRONG: `- [ ] [US1] Create User model` (missing Task ID)
- ❌ WRONG: `- [ ] T001 [US1] Create model` (missing file path)

## # Task Organization

1. **From User Stories (`FEATURE_DIR/spec.md`)** - PRIMARY ORGANIZATION:
   - Each user story (P1, P2, P3...) gets its own phase
   - Map all related components to their story:
     - Models needed for that story
     - Services needed for that story
     - Endpoints/UI needed for that story
     - If tests requested: Tests specific to that story
   - Mark story dependencies (most stories should be independent)

2. **From Contracts**:
   - Map each contract/endpoint → to the user story it serves
   - If tests requested: Each contract → contract test task [P] before implementation in that story's phase

3. **From Data Model**:
   - Map each entity to the user story(ies) that need it
   - If entity serves multiple stories: Put in earliest story or Setup phase
   - Relationships → service layer tasks in appropriate story phase

4. **From Setup/Infrastructure**:
   - Shared infrastructure → Setup phase (Phase 1)
   - Foundational/blocking tasks → Foundational phase (Phase 2)
   - Story-specific setup → within that story's phase

## # Phase Structure

- **Phase 1**: Setup (project initialization)
- **Phase 2**: Foundational (blocking prerequisites - MUST complete before user stories)
- **Phase 3+**: User Stories in priority order (P1, P2, P3...)
  - Within each story: Tests (if requested) → Models → Services → Endpoints → Integration
  - Each phase should be a complete, independently testable increment
- **Final Phase**: Polish & Cross-Cutting Concerns



