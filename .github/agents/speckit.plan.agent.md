---
description: Execute the implementation planning workflow, generating research, data model, contracts, and quickstart artifacts alongside the implementation plan.
handoffs:
  - label: Create Tasks
    agent: speckit.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: speckit.checklist
    prompt: Create a checklist for the following domain...
---

# # User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

---

# # Purpose

Generate the **complete design artifact set** for a SpecKit feature:

| Artifact | Location | Phase | Required |
|----------|----------|-------|----------|
| `plan.md` | `specs/changes/{CHANGE_ID}/plan.md` | Setup | ✅ Yes |
| `research.md` | `specs/changes/{CHANGE_ID}/research.md` | Phase 0 | ✅ Yes |
| `data-model.md` | `specs/changes/{CHANGE_ID}/data-model.md` | Phase 1 | ✅ Yes |
| `quickstart.md` | `specs/changes/{CHANGE_ID}/quickstart.md` | Phase 1 | ✅ Yes |
| `contracts/` | `specs/changes/{CHANGE_ID}/contracts/*.yaml` | Phase 1 | ✅ Yes |

**This agent MUST create all 5 artifact types before completing.**

---

# # Outline

1. **Validate Prerequisites**: Ensure spec.md exists before proceeding

   ```pwsh
   specs/scripts/check-prerequisites.ps1 -Json
   ```

   **Validation**: After running the script, check the exit code and verify spec.md exists:
   ```pwsh
   if ($LASTEXITCODE -ne 0) {
      throw "Prerequisites check failed. Ensure you are in a valid feature branch with spec.md created. Run /speckit.specify first."
   }
   ```
   Parse the JSON output and verify `FEATURE_SPEC` field points to an existing file. If spec.md doesn't exist, **STOP** and guide user to run `/speckit.specify` first.

2. **Setup**: Run `specs/scripts/setup-plan.ps1 -Json` from repo root

   **Validation**: After running the script, check the exit code:
   ```pwsh
   if ($LASTEXITCODE -ne 0) {
      throw "setup-plan.ps1 failed with exit code $LASTEXITCODE"
   }
   ```
   If `$LASTEXITCODE -ne 0`, **STOP** workflow immediately. Report error with context: script name, exit code, and any error output. Do NOT proceed to next step until error is resolved.

3. **Load Context**: Read `specs/changes/{CHANGE_ID}/spec.md`, `specs/memory/constitution.md`, and `specs/project.md`
4. **Execute Phase 0**: Generate `specs/changes/{CHANGE_ID}/research.md` (resolve all NEEDS CLARIFICATION)
5. **Execute Phase 1**: Generate `specs/changes/{CHANGE_ID}/data-model.md`, `specs/changes/{CHANGE_ID}/contracts/`, `specs/changes/{CHANGE_ID}/quickstart.md`
6. **Finalize**: Complete `plan.md` with all sections filled
7. **Report**: List all generated artifacts and next steps

---

# # Phases

## # Phase 0: Research

**Objective**: Resolve all `[NEEDS RESEARCH]` items and technical unknowns.

### # Input Analysis

Extract from Technical Context all items marked:
- `[NEEDS RESEARCH: ...]`
- `[NEEDS CLARIFICATION: ...]`
- Technology choices without rationale
- Integration points without contracts

### # Research Process

For each unknown:
1. Identify the specific question
2. Research best practices, library options, patterns
3. Document decision with rationale

### # Output: research.md

Create `specs/changes/{CHANGE_ID}/research.md` using template `specs/templates/research-template.md`:

| Section | Content |
|---------|---------|
| Research Summary | Table of topics, decisions, confidence levels |
| Detailed Findings | Per-topic: question, decision, rationale, alternatives, sources |
| Resolved Items | Mapping from original `[NEEDS...]` to resolution |
| Remaining Unknowns | Any items that couldn't be resolved |

**GATE**: All `[NEEDS RESEARCH]` items resolved before proceeding to Phase 1.

---

## # Phase 1: Design & Contracts

**Prerequisites**: `specs/changes/{CHANGE_ID}/research.md` complete with all unknowns resolved.

### # 1.1 Data Model

Extract entities from `specs/changes/{CHANGE_ID}/spec.md` and create `specs/changes/{CHANGE_ID}/data-model.md`:

| Component | Content |
|-----------|---------|
| Entity Overview | Table of entities, descriptions, storage |
| Entity Definitions | Fields, types, constraints, relationships |
| Indexes | Performance optimization indexes |
| State Diagrams | Lifecycle states (if applicable) |
| Migration Notes | Database migration considerations |

**Template**: `specs/templates/data-model-template.md`

### # 1.2 API Contracts

For each user action documented in `specs/changes/{CHANGE_ID}/spec.md`, generate OpenAPI contracts in `specs/changes/{CHANGE_ID}/contracts/`:

| Spec Requirement Type | Contract Pattern |
|-----------------------|------------------|
| "User can create X" | `POST /api/{RESOURCE}` |
| "User can view X" | `GET /api/{RESOURCE}/:id` |
| "User can list X" | `GET /api/{RESOURCE}` |
| "User can update X" | `PUT /api/{RESOURCE}/:id` |
| "User can delete X" | `DELETE /api/{RESOURCE}/:id` |

**Create**: `specs/changes/{CHANGE_ID}/contracts/{RESOURCE}/{OPERATION}.yaml` for each endpoint

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

### # 1.3 Quickstart Guide

Create `specs/changes/{CHANGE_ID}/quickstart.md` using template `specs/templates/quickstart-template.md`:

| Section | Content |
|---------|---------|
| Overview | Brief feature description |
| Prerequisites | What's needed before using |
| Quick Integration | Step-by-step scenarios with code |
| API Reference | Endpoint table referencing contracts |
| Error Handling | Error codes and resolutions |
| Testing | Unit and integration test examples |

### # 1.4 Agent Context Update

```powershell
specs/scripts/update-agent-context.ps1 -AgentType copilot

# Check script execution status
if ($LASTEXITCODE -ne 0) {
    throw "update-agent-context.ps1 failed with exit code $LASTEXITCODE. Review output above for details."
}
```

---

# # Validation Gates

## # Pre-Phase 0 Gate

- [ ] `specs/changes/{CHANGE_ID}/spec.md` exists and is readable
- [ ] `specs/memory/constitution.md` accessible
- [ ] `specs/changes/{CHANGE_ID}/plan.md` template copied successfully

## # Pre-Phase 1 Gate

- [ ] `specs/changes/{CHANGE_ID}/research.md` exists
- [ ] All `[NEEDS RESEARCH]` items resolved
- [ ] Technical Context has no placeholders

## # Post-Phase 1 Gate

- [ ] `specs/changes/{CHANGE_ID}/data-model.md` exists with at least 1 entity
- [ ] `specs/changes/{CHANGE_ID}/quickstart.md` exists with at least 1 scenario
- [ ] `specs/changes/{CHANGE_ID}/contracts/` exists with at least 1 contract file
- [ ] `specs/changes/{CHANGE_ID}/plan.md` fully populated with no `[NEEDS...]` markers
- [ ] Constitution Check passed

---

# # Validate Generated Artifacts

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

---

# # Completion Report

After generating all artifacts, output:

```markdown
# # Plan Phase Complete

**Branch**: {CURRENT_BRANCH}
**Feature**: {CHANGE_ID}

## # Generated Artifacts

| Artifact | Path | Status |
|----------|------|--------|
| plan.md | `specs/changes/{CHANGE_ID}/plan.md` | ✅ Created |
| research.md | `specs/changes/{CHANGE_ID}/research.md` | ✅ Created |
| data-model.md | `specs/changes/{CHANGE_ID}/data-model.md` | ✅ Created |
| quickstart.md | `specs/changes/{CHANGE_ID}/quickstart.md` | ✅ Created |
| contracts/ | `specs/changes/{CHANGE_ID}/contracts/` | ✅ Created ({N} files) |

## # Constitution Check

- [x] Spec-First Development
- [x] File-Based Truth
- [x] Validation Gates
- [x] Dual-State Model
- [x] AI-Ready Instructions

## # Next Step

Run `/speckit.tasks` to generate the task breakdown.
```

---

# # Key Rules

1. **ALL 5 ARTIFACTS REQUIRED**: specs/changes/{CHANGE_ID}/plan.md, specs/changes/{CHANGE_ID}/research.md, specs/changes/{CHANGE_ID}/data-model.md, specs/changes/{CHANGE_ID}/quickstart.md, specs/changes/{CHANGE_ID}/contracts/
2. **USE REPO-RELATIVE PATHS IN INSTRUCTIONS**: Prefer `specs/...` references; scripts provide absolute paths via JSON outputs when needed.
3. **NO PLACEHOLDERS IN FINAL OUTPUT**: Replace all `[NEEDS...]` markers
4. **VALIDATE GATES**: Each phase has entry and exit criteria
5. **ERROR ON FAILURE**: Do not proceed if prerequisites missing


