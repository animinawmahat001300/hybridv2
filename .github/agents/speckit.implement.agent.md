---
description: Execute the implementation plan by processing and executing all tasks defined in tasks.md
handoffs:
  - label: Archive Completed Feature
    agent: speckit.archive
    prompt: Archive the completed feature after all tasks are done
  - label: Re-analyze for Issues
    agent: speckit.analyze
    prompt: Re-analyze the implementation for consistency issues
---

# # User Input

```text
    $ARGUMENTS
```
You **MUST** consider the user input before proceeding (if not empty).
# # Outline
1. From repo root, resolve the absolute script path and run prerequisites (prevents positional parsing issues when invoked from subfolders):

   ```powershell
   # Use repo root detection for absolute path
   $RepoRoot = git rev-parse --show-toplevel
   $prereqResult = & "$RepoRoot/specs/scripts/check-prerequisites.ps1" -Json -RequireTasks -IncludeTasks
   ```

   **Validation**: After running the script, check the exit code:
   ```pwsh
   if ($LASTEXITCODE -ne 0) {
      Write-Host "❌ Prerequisite check failed with exit code $LASTEXITCODE"
      throw "check-prerequisites.ps1 failed with exit code $LASTEXITCODE"
   }
   ```
   If `$LASTEXITCODE -ne 0`, **STOP** workflow immediately. Report error with context: script name, exit code, and any error output. Do NOT proceed to next step until error is resolved.

   Parse FEATURE_DIR, CHANGE_ID, and AVAILABLE_DOCS. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").
2. **Check checklists status** (if FEATURE_DIR/checklists/ exists):
   - Scan all checklist files in the checklists/ directory
   - For each checklist, count:
     - Total items: All lines matching `- [ ]` or `- [X]` or `- [x]`
     - Completed items: Lines matching `- [X]` or `- [x]`
     - Incomplete items: Lines matching `- [ ]`
   - Create a status table:

     ```text
     | Checklist | Total | Completed | Incomplete | Status |
     |-----------|-------|-----------|------------|--------|
     | ux.md     | 12    | 12        | 0          | ✓ PASS |
     | test.md   | 8     | 5         | 3          | ⚠ PARTIAL |
     | security.md | 6   | 6         | 0          | ✓ PASS |
     ```

   - Display the current checklist status for visibility
   - **Always proceed automatically** with implementation
   - **Cross-reference mapping**: Analyze tasks.md and checklist files to map which checklist items correspond to which tasks
   - **During implementation**: Update checklist items to `[x]` as requirements are fulfilled
   - **Track progress**: Mark checklist items complete when corresponding tasks are implemented

3. Load and analyze the implementation context:
   - **REQUIRED**: Read `specs/changes/{CHANGE_ID}/tasks.md` for the complete task list and execution plan
   - **REQUIRED**: Read `specs/changes/{CHANGE_ID}/plan.md` for tech stack, architecture, and file structure
   - **REQUIRED**: Cross-reference `FEATURE_DIR/checklists/` files with tasks to establish task-checklist item mappings
   - **Establish mappings**: For each task, identify which checklist items it fulfills (e.g., "Create User API" task fulfills "API returns JSON" checklist item)
   - **REQUIRED**: Read `specs/memory/constitution.md` for governance principles and quality standards
   - **REQUIRED**: Read `specs/project.md` for tech stack, code style, architecture patterns, testing strategy, and git workflow
   - **IF EXISTS**: Read `specs/changes/{CHANGE_ID}/data-model.md` for entities and relationships
   - **IF EXISTS**: Read `specs/changes/{CHANGE_ID}/contracts/` for API specifications and test requirements
   - **IF EXISTS**: Read `specs/changes/{CHANGE_ID}/research.md` for technical decisions and constraints
   - **IF EXISTS**: Read `specs/changes/{CHANGE_ID}/quickstart.md` for integration scenarios

3.5. **Extract project conventions from `specs/project.md`**:
   - **Tech Stack**: Note exact framework/library versions (e.g., React 18, Next.js 14, TypeScript 5.x, shadcn/ui, Tailwind CSS, Prisma, tRPC)
   - **Code Style**: Apply file naming (PascalCase components, camelCase utilities, kebab-case routes), formatting rules (indentation, quotes, semicolons), import order
   - **Architecture Patterns**: Follow component organization (Atomic Design, feature-based), state management (TanStack Query + Zustand), API design (REST/GraphQL/tRPC), layer structure (Controller→Service→Repository), database patterns (Prisma/Drizzle)
   - **Testing Strategy**: Use specified frameworks (Vitest/Jest/Playwright), follow coverage targets, apply mocking strategies
   - **Security Patterns**: Apply input sanitization, CORS, rate limiting, SQL injection prevention, XSS prevention
   - **CRITICAL**: ALL generated code MUST conform to these conventions. If plan.md conflicts with project.md, project.md takes precedence as the source of truth

3.7. **Delta specification tracking (OpenSpec-style)**:
   - When the implementation **adds/modifies/removes** behavior for an existing capability, create or update `specs/changes/{CHANGE_ID}/specs/{CAPABILITY}/spec.md` using ADDED/MODIFIED/REMOVED sections (see `specs/project.md` Delta Operations).
   - Reference the corresponding truth file `specs/{CAPABILITY}/spec.md` to align names/IDs; include merge markers or rationale where appropriate.
   - For new API endpoints, add/update `specs/changes/{CHANGE_ID}/contracts/**/*.yaml` and note the linkage in the delta spec.
   - Before archive, ensure every changed capability has a delta spec present; otherwise, flag as a blocking issue.

3.8. **Load Design Artifacts for Citation** (REQUIRED):

   Extract referenceable items from each artifact to enable implementation citations and ensure code aligns with specifications:

   ```powershell
   # Load project.md conventions (folder structure, naming, architecture)
   if (Test-Path "specs/project.md") {
       $projectMd = Get-Content "specs/project.md" -Raw
       Write-Host "📋 Loading project conventions from specs/project.md"

       # Extract folder structure
       if ($projectMd -match '## (Folder Structure|Domain Context)(.*?)(?=##|$)') {
           $folderSection = $Matches[2]
           $srcRoot = if ($folderSection -match '`([^`]+/src/?[^`]*)`') { $Matches[1] } else { 'src/' }
           $testsRoot = if ($folderSection -match '`([^`]+/tests?/?[^`]*)`') { $Matches[1] } else { 'tests/' }
           $docsRoot = if ($folderSection -match '`([^`]+/docs?/?[^`]*)`') { $Matches[1] } else { 'docs/' }
           $configRoot = if ($folderSection -match '`([^`]+/config/?[^`]*)`') { $Matches[1] } else { 'config/' }
           Write-Host "  ├─ Source root: $srcRoot"
           Write-Host "  ├─ Tests root: $testsRoot"
           Write-Host "  ├─ Docs root: $docsRoot"
           Write-Host "  └─ Config root: $configRoot"
       }

       # Extract naming conventions
       $namingRules = @()
       if ($projectMd -match '## (Naming Conventions|Code Style)(.*?)(?=##|$)') {
           $namingSection = $Matches[2]
           if ($namingSection -match 'PascalCase') { $namingRules += "Components: PascalCase" }
           if ($namingSection -match 'camelCase') { $namingRules += "Utilities: camelCase" }
           if ($namingSection -match 'kebab-case') { $namingRules += "Routes: kebab-case" }
           if ($namingSection -match 'snake_case') { $namingRules += "Python files: snake_case" }
           Write-Host "📝 Naming conventions: $($namingRules -join ', ')"
       }

       # Extract architecture patterns
       if ($projectMd -match '## Architecture Patterns(.*?)(?=##|$)') {
           $archSection = $Matches[1]
           if ($archSection -match '(Atomic Design|Feature-based|Controller→Service→Repository|MVC|Layered Architecture)') {
               $archPattern = $Matches[1]
               Write-Host "🏛️ Architecture pattern: $archPattern"
           }
       }
   }

   # Load data-model.md entities
   if (Test-Path "$FeatureDir/data-model.md") {
       $dataModel = Get-Content "$FeatureDir/data-model.md" -Raw
       $entities = ($dataModel | Select-String -Pattern "### (.+)" -AllMatches).Matches | ForEach-Object { $_.Groups[1].Value }
       Write-Host "📊 Loaded entities: $($entities -join ', ')"
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

   # Load quickstart.md integration examples
   if (Test-Path "$FeatureDir/quickstart.md") {
       $quickstart = Get-Content "$FeatureDir/quickstart.md" -Raw
       $scenarios = ($quickstart | Select-String -Pattern "### (.+)" -AllMatches).Matches | ForEach-Object { $_.Groups[1].Value }
       Write-Host "🎬 Loaded integration scenarios: $($scenarios -join ', ')"
   }
   ```

  **Artifact Citation Format** (Use in code comments and commit messages):
  - **Entities**: `EntityName` → `specs/changes/{CHANGE_ID}/data-model.md#entity-name — kebab-case anchor
  - **Endpoints**: `GET /api/users` → `specs/changes/{CHANGE_ID}/contracts/**/*.yaml#L10` — line number anchor, ** matches any subfolder structure
  - **Folder Paths**: Use `$srcRoot`, `$testsRoot` variables from project.md parsing
  - **Naming**: Apply conventions extracted from project.md (PascalCase/camelCase/kebab-case)
  - **Integration Scenarios**: `Scenario Name` → `specs/changes/{CHANGE_ID}/quickstart.md#scenario-name — kebab-case anchor

   **Citation Examples in Implementation**:
   ```typescript
  // Implement User entity per User (`specs/changes/{CHANGE_ID}/data-model.md#user) specification
   export class User {
     // ...
   }

  // Endpoint implementation for GET /api/users (`specs/changes/{CHANGE_ID}/contracts/**/*.yaml#L12`)
   router.get('/api/users', async (req, res) => {
     // ...
   });

  // Integration test for User Registration Flow (`specs/changes/{CHANGE_ID}/quickstart.md#user-registration-flow)
   describe('User Registration Flow', () => {
     // ...
   });
   ```

4. **Project Setup Verification**:
   - **REQUIRED**: Create/verify ignore files based on actual project setup:

   **Detection & Creation Logic**:
   - Check if the following command succeeds to determine if the repository is a git repo (create/verify .gitignore if so):

     ```bash
     git rev-parse --git-dir 2>/dev/null
     ```

   - Check if Dockerfile* exists or Docker in `FEATURE_DIR/plan.md` → create/verify .dockerignore
   - Check if .eslintrc* exists → create/verify .eslintignore
   - Check if eslint.config.* exists → ensure the config's `ignores` entries cover required patterns
   - Check if .prettierrc* exists → create/verify .prettierignore
   - Check if .npmrc or package.json exists → create/verify .npmignore (if publishing)
   - Check if terraform files (*.tf) exist → create/verify .terraformignore
   - Check if .helmignore needed (helm charts present) → create/verify .helmignore

   **If ignore file already exists**: Verify it contains essential patterns, append missing critical patterns only
   **If ignore file missing**: Create with full pattern set for detected technology

   **Common Patterns by Technology** (from `FEATURE_DIR/plan.md` tech stack):
   - **Node.js/JavaScript/TypeScript**: `node_modules/`, `dist/`, `build/`, `*.log`, `.env*`
   - **Python**: `__pycache__/`, `*.pyc`, `.venv/`, `venv/`, `dist/`, `*.egg-info/`
   - **Java**: `target/`, `*.class`, `*.jar`, `.gradle/`, `build/`
   - **C#/.NET**: `bin/`, `obj/`, `*.user`, `*.suo`, `packages/`
   - **Go**: `*.exe`, `*.test`, `vendor/`, `*.out`
   - **Ruby**: `.bundle/`, `log/`, `tmp/`, `*.gem`, `vendor/bundle/`
   - **PHP**: `vendor/`, `*.log`, `*.cache`, `*.env`
   - **Rust**: `target/`, `debug/`, `release/`, `*.rs.bk`, `*.rlib`, `*.prof*`, `.idea/`, `*.log`, `.env*`
   - **Kotlin**: `build/`, `out/`, `.gradle/`, `.idea/`, `*.class`, `*.jar`, `*.iml`, `*.log`, `.env*`
   - **C++**: `build/`, `bin/`, `obj/`, `out/`, `*.o`, `*.so`, `*.a`, `*.exe`, `*.dll`, `.idea/`, `*.log`, `.env*`
   - **C**: `build/`, `bin/`, `obj/`, `out/`, `*.o`, `*.a`, `*.so`, `*.exe`, `Makefile`, `config.log`, `.idea/`, `*.log`, `.env*`
   - **Swift**: `.build/`, `DerivedData/`, `*.swiftpm/`, `Packages/`
   - **R**: `.Rproj.user/`, `.Rhistory`, `.RData`, `.Ruserdata`, `*.Rproj`, `packrat/`, `renv/`
   - **Universal**: `.DS_Store`, `Thumbs.db`, `*.tmp`, `*.swp`, `.vscode/`, `.idea/`

   **Tool-Specific Patterns**:
   - **Docker**: `node_modules/`, `.git/`, `Dockerfile*`, `.dockerignore`, `*.log*`, `.env*`, `coverage/`
   - **ESLint**: `node_modules/`, `dist/`, `build/`, `coverage/`, `*.min.js`
   - **Prettier**: `node_modules/`, `dist/`, `build/`, `coverage/`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
   - **Terraform**: `.terraform/`, `*.tfstate*`, `*.tfvars`, `.terraform.lock.hcl`
   - **Kubernetes/k8s**: `*.secret.yaml`, `secrets/`, `.kube/`, `kubeconfig*`, `*.key`, `*.crt`

5. Parse `specs/changes/{CHANGE_ID}/tasks.md` structure and extract:
   - **Task phases**: Setup, Tests, Core, Integration, Polish
   - **Task dependencies**: Sequential vs parallel execution rules
   - **Task details**: ID, description, file paths, parallel markers [P]
   - **Execution flow**: Order and dependency requirements

6. Execute implementation following the task plan:
   - **Phase-by-phase execution**: Complete each phase before moving to the next
   - **Respect dependencies**: Run sequential tasks in order, parallel tasks [P] can run together
   - **Follow TDD approach**: Execute test tasks before their corresponding implementation tasks
   - **File-based coordination**: Tasks affecting the same files must run sequentially
   - **Validation checkpoints**: Verify each phase completion before proceeding

7. Implementation execution rules (REFERENCE LOADED ARTIFACTS):
   - **Setup first**: Initialize project structure using folder paths from `specs/project.md` (`$srcRoot`, `$testsRoot`, etc.), apply naming conventions (PascalCase/camelCase/kebab-case), configure dependencies
   - **Tests before code**: Write tests for entities from `specs/changes/{CHANGE_ID}/data-model.md`, endpoints from `specs/changes/{CHANGE_ID}/contracts/**/*.yaml`, and integration scenarios from `specs/changes/{CHANGE_ID}/quickstart.md` - include citation links in test comments
  - **Core development**: Implement entities referencing EntityName (`specs/changes/{CHANGE_ID}/data-model.md#entityname), implement endpoints citing METHOD /path (`specs/changes/{CHANGE_ID}/contracts/**/*.yaml#LN`), follow architecture patterns from `project.md`
  - **Integration work**: Implement integration scenarios from `specs/changes/{CHANGE_ID}/quickstart.md` as Scenario Name (`specs/changes/{CHANGE_ID}/quickstart.md#scenario-name), add database connections, middleware, logging, external services
   - **Polish and validation**: Unit tests, performance optimization, documentation with artifact citations
   - **Checklist updates**: As each task is completed, update corresponding checklist items from `FEATURE_DIR/checklists/` to `[x]` when requirements are fulfilled (use established task-checklist mappings)
   - **CRITICAL**: Every file created must follow folder structure and naming conventions from `specs/project.md`. Every entity/endpoint implementation must cite the source artifact in code comments.

8. Progress tracking and error handling:
   - Report progress after each completed task
   - Halt execution if any non-parallel task fails
   - For parallel tasks [P], continue with successful tasks, report failed ones
   - Provide clear error messages with context for debugging
   - Suggest next steps if implementation cannot proceed
   - **IMPORTANT** For completed tasks, make sure to mark the task off as [X] in the tasks file.
   - **IMPORTANT** For checklist items fulfilled by completed tasks, mark them as [x] in the corresponding checklist files.

9. Completion validation:
   - Verify all required tasks are completed
   - Check that implemented features match the original specification
   - Validate that tests pass and coverage meets requirements
   - Confirm the implementation follows the technical plan
   - Report final status with summary of completed work

Note: This command assumes a complete task breakdown exists in `specs/changes/{CHANGE_ID}/tasks.md`. If tasks are incomplete or missing, suggest running `/speckit.tasks` first to regenerate the task list.


