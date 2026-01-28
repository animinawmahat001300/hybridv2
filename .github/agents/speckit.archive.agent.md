---
description: Promote a completed feature from specs/changes/ to the Source of Truth (specs/{CAPABILITY}/). Handles OpenSpec delta merging for ADDED, MODIFIED, and REMOVED sections.
---

# User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The input should be a feature ID (e.g., `001-user-auth`).

---

# Pre-Archive Checklist

Before proceeding, verify ALL conditions are met:

- [ ] All tasks in `specs/changes/{CHANGE_ID}/tasks.md` marked `[X]`
- [ ] `specs/scripts/validate.ps1 -Target {CHANGE_ID} -Strict` passes
- [ ] No uncommitted git changes in working directory
- [ ] Delta specs merged (if `specs/changes/{CHANGE_ID}/specs/` exists)

Run this command to check git status:
```powershell
git status --porcelain
```
If output is not empty, prompt user to commit or stash changes before continuing.

---

# Outline

## 1. Locate Feature

Identify the feature directory:
```powershell
$FeatureId = "{CHANGE_ID}"  # From user input
$FeatureDir = "specs/changes/$FeatureId"
Test-Path $FeatureDir  # Must return True
```

Alternatively, run `specs/scripts/check-prerequisites.ps1 -Json -RequireTasks` to auto-detect.

**Validation**: After running the script, check the exit code:
```pwsh
if ($LASTEXITCODE -ne 0) {
   throw "check-prerequisites.ps1 failed with exit code $LASTEXITCODE. Review output above for details."
}
```
If `$LASTEXITCODE -ne 0`, **STOP** workflow immediately and report error with context.

## 2. Verify Completion

Check all tasks are complete before archiving:

```powershell
# Count incomplete tasks
$tasks = Get-Content "specs/changes/$FeatureId/tasks.md"
$incomplete = $tasks | Where-Object { $_ -match '^\s*-\s*\[ \]' }
if ($incomplete) {
    Write-Error "Incomplete tasks found:"
    $incomplete | ForEach-Object { Write-Host "  $_" }
   exit 1
}
```

Verify required artifacts exist:
- `specs/changes/{CHANGE_ID}/spec.md` (specification)
- `specs/changes/{CHANGE_ID}/plan.md` (implementation plan)
- `specs/changes/{CHANGE_ID}/tasks.md` (task tracker)

## 3. Run Pre-Archive Validation

Execute strict validation before archiving:
```powershell
specs/scripts/validate.ps1 -Target $FeatureId -Strict -Json
if ($LASTEXITCODE -ne 0) {
   throw "validate.ps1 failed with exit code $LASTEXITCODE. Review validation errors above and fix before proceeding."
}
```

**Validation**: Check script exit code. If `$LASTEXITCODE -ne 0`, **STOP** workflow immediately. Report error with context: script name, exit code, and any error output. Do NOT proceed to archiving until validation passes.

## 4. Check for Delta Specs

Determine if feature has OpenSpec delta specifications:
```powershell
$DeltaSpecsDir = "specs/changes/$FeatureId/specs"
$HasDeltaSpecs = Test-Path $DeltaSpecsDir
```

If `$HasDeltaSpecs` is `$true`, delta merge will occur during archive.

## 5. Execute Archive

Call the archive script to perform the promotion:
```powershell
specs/scripts/archive-feature.ps1 -FeatureId $FeatureId -Json
if ($LASTEXITCODE -ne 0) {
   throw "archive-feature.ps1 failed with exit code $LASTEXITCODE. Review output above for details."
}
```

**Validation**: Check script exit code. If `$LASTEXITCODE -ne 0`, **STOP** workflow immediately. Report error with context: script name, exit code, and any error output.

Available flags:
- `-Force` / `-Yes`: Skip confirmation prompts
- `-SkipValidation`: Skip pre-archive validation (not recommended)
- `-SkipMerge`: Skip delta spec merging
- `-WhatIf`: Dry-run to preview changes

## 6. Post-Archive Validation

After archiving, verify the merge was successful:
```powershell
specs/scripts/validate.ps1 -Strict
if ($LASTEXITCODE -ne 0) {
   throw "Post-archive validation failed with exit code $LASTEXITCODE. Review validation errors above."
}
```

**Validation**: Check script exit code. If `$LASTEXITCODE -ne 0`, warn user that archive completed but validation found issues. Report error with context: script name, exit code, and any error output.

Confirm target capability specs are updated in `specs/{CAPABILITY}/spec.md`.

---

# OpenSpec Delta Merge Logic

When `specs/changes/{CHANGE_ID}/specs/` exists, the archive script performs delta merging:

## Delta Section Types

| Section Header | Action | Target |
|----------------|--------|--------|
| `## ADDED Requirements` | Append to main spec | `specs/{CAPABILITY}/spec.md` |
| `## MODIFIED Requirements` | Replace matching section in main spec | `specs/{CAPABILITY}/spec.md` |
| `## REMOVED Requirements` | Comment out in main spec (preserves history) | `specs/{CAPABILITY}/spec.md` |

## Merge Behavior by Type

**ADDED Sections**:
- Content appended to end of target spec
- Merge marker inserted: `<!-- ADDED from {CHANGE_ID} on {DATE} -->`
- No conflict possible; always succeeds

**MODIFIED Sections**:
- Locates matching `### Requirement: {REQUIREMENT_NAME}` in target spec
- Replaces entire requirement block (from header to next `###`)
- Merge marker inserted: `<!-- MODIFIED from {CHANGE_ID} on {DATE} -->`
- If requirement not found: added as new with `<!-- MODIFIED (new) -->` marker

**REMOVED Sections**:
- Locates matching `### Requirement: {REQUIREMENT_NAME}` in target spec
- Comments out entire block (does NOT delete)
- Removal markers: `<!-- REMOVED from {CHANGE_ID} on {DATE}` ... `-->`
- Preserves history for audit trail

## Delta Spec Structure

Delta specs in `specs/changes/{CHANGE_ID}/specs/{CAPABILITY}/spec.md` must follow:

```markdown
# ADDED Requirements

## Requirement: New-Feature-Name

WHEN user performs action
THE SYSTEM SHALL respond with expected behavior

# MODIFIED Requirements

## Requirement: Existing-Feature-Name

WHEN user performs updated action
THE SYSTEM SHALL respond with updated behavior

# REMOVED Requirements

## Requirement: Deprecated-Feature-Name

(Reason for removal documented here)
```

---

# Delta Transformation Rules

When converting `specs/changes/{CHANGE_ID}/spec.md` to delta format:

| Artifact Section | Delta Format | Notes |
| ---------------- | ------------ | ----- |
| Requirements (new) | `## ADDED Requirements` | New capabilities |
| Requirements (updated) | `## MODIFIED Requirements` | Changed behavior |
| Requirements (deprecated) | `## REMOVED Requirements` | To be commented out |
| User Stories | Extract to requirement scenarios | Include in ADDED/MODIFIED body |
| Success Criteria | Include in requirement body | Under each requirement |

**Critical**: MODIFIED deltas MUST include complete requirement text (not diffs).

---

# Archive Output

The archive script produces:

1. **Historical Snapshot**: `specs/changes/archive/{YYYY_MM_DD}-{CHANGE_ID}/`
   - Complete copy of feature directory at archive time
   - Preserves all artifacts for audit

2. **Truth Updates**: `specs/{CAPABILITY}/spec.md`
   - Delta specs merged into capability source of truth
   - Merge markers indicate provenance

3. **JSON Result** (when `-Json` flag used):
```json
{
  "success": true,
  "feature_id": "{CHANGE_ID}",
   "archive_path": "specs/changes/archive/{YYYY_MM_DD}-{CHANGE_ID}",
  "validation": { "passed": true, "errors": [], "warnings": [] },
  "tasks_check": { "passed": true, "total": 5, "complete": 5, "incomplete": [] },
  "merged_specs": [
    { "capability": "auth", "delta": "...", "target": "...", "status": "merged" }
  ]
}
```

---

# Completion Report Template

After successful archive, report:

```text
# Archive Complete: {CHANGE_ID}

## Summary
- **Feature ID**: {CHANGE_ID}
- **Archive Location**: specs/changes/archive/{YYYY_MM_DD}-{CHANGE_ID}/
- **Validation Status**: PASSED

## Delta Specs Merged
- specs/{CAPABILITY_1}/spec.md (ADDED: 2 requirements)
- specs/{CAPABILITY_2}/spec.md (MODIFIED: 1 requirement, REMOVED: 1 requirement)

## Task Completion
- Total Tasks: {N}
- Completed: {N}

## Next Steps
1. Review merged specs in `specs/{CAPABILITY}/spec.md` for accuracy
2. Update dependent documentation if needed
3. Notify stakeholders of feature completion
4. Run full test suite if implementation affected
```

---

# Archive Flow

```mermaid
flowchart TD
    accTitle: Archive Flow with Delta Merge
    accDescr: Shows how speckit.archive promotes changes with OpenSpec delta merging

    START["/speckit.archive {CHANGE_ID}"] --> CHECKLIST["Pre-Archive Checklist"]
    CHECKLIST --> VALIDATE["validate.ps1 -Strict"]
    VALIDATE -->|Pass| TASKS["Check tasks.md complete"]
    VALIDATE -->|Fail| ABORT["Abort: Fix validation errors"]
    TASKS -->|All [X]| DELTA{"Delta specs exist?"}
    TASKS -->|Incomplete| ABORT2["Abort: Complete tasks first"]
    DELTA -->|Yes| MERGE["Merge ADDED/MODIFIED/REMOVED"]
    DELTA -->|No| ARCHIVE["archive-feature.ps1"]
    MERGE --> ARCHIVE
    ARCHIVE --> SNAPSHOT["Create historical snapshot"]
    SNAPSHOT --> POSTVAL["Post-archive validate.ps1"]
    POSTVAL --> REPORT["Output completion report"]
```

---

# Error Handling

| Error | Resolution |
|-------|------------|
| Feature directory not found | Verify feature ID and path `specs/changes/{CHANGE_ID}` |
| Validation failed | Run `specs/scripts/validate.ps1 -Target {CHANGE_ID}` and fix errors |
| Incomplete tasks | Mark remaining tasks `[X]` in `tasks.md` or use `-Force` (not recommended) |
| Delta merge conflict | Review merge markers in target spec; manual resolution may be needed |
| Git uncommitted changes | Commit or stash changes: `git stash` |



