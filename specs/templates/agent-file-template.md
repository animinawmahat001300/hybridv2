# {PROJECT_NAME} Development Guidelines

Auto-generated from all feature plans. Last updated: {YYYY_MM_DD}

# # Active Technologies

{EXTRACTED_TECHNOLOGIES}

| Technology | Version | Purpose |
|------------|---------|----------|
| {LANGUAGE} | {VERSION} | Primary language |
| {FRAMEWORK} | {VERSION} | {PURPOSE} |

# # Project Structure

```text
{PROJECT_STRUCTURE}
```

# # Commands

{COMMANDS}

```pwsh
# Development
{COMMAND}

# Testing
{COMMAND}

# Build
{COMMAND}
```

# # Code Style

{CODE_STYLE}

# # Recent Changes

{RECENT_CHANGES}

| Date | Feature | Description |
|------|---------|-------------|
| {YYYY_MM_DD} | {FEATURE_NAME} | {SUMMARY} |

<!-- BEGIN MANUAL ADDITIONS -->
<!-- 
  Add custom guidelines below that should persist across regenerations.
  This section is preserved by update-agent-context.ps1 when regenerating this file.
  
  Examples of content to add here:
  - Team-specific conventions
  - Tool configurations
  - Special workflows
  - External service integrations
  - Deployment procedures
-->

# # PowerShell Script Error Handling Pattern

When agent files execute PowerShell scripts in `specs/scripts/`, they **MUST** check `$LASTEXITCODE` after EVERY script call:

## # Standard Error Handling Pattern

```powershell
# Execute the script
specs/scripts/script-name.ps1 -Param1 Value1 -Param2 Value2

# Check script execution status
if ($LASTEXITCODE -ne 0) {
    throw "script-name.ps1 failed with exit code $LASTEXITCODE. Review output above for details."
}
```

## # Full Example with Documentation

```powershell
# Run prerequisite checks and parse JSON output
specs/scripts/check-prerequisites.ps1 -Json

# Validation: After running the script, check the exit code
if ($LASTEXITCODE -ne 0) {
    throw "check-prerequisites.ps1 failed with exit code $LASTEXITCODE. Review output above for details."
}

# If $LASTEXITCODE -ne 0, **STOP** workflow immediately. Report error with context:
# script name, exit code, and any error output. Do NOT proceed to next step until error is resolved.
```

## # Why This Matters

- **Prevents silent failures**: Scripts may fail without raising PowerShell exceptions
- **Early error detection**: Stops workflow immediately when scripts fail
- **Clear error context**: Provides script name, exit code, and directs user to output
- **Workflow safety**: Ensures agents don't proceed with invalid/incomplete data

## # Implementation Status (V5-6)

All SpecKit agent files now implement this pattern:
- ✅ speckit.specify.agent.md - 4 script calls, 5 exit code checks
- ✅ speckit.clarify.agent.md - 1 script call, 3 exit code checks
- ✅ speckit.plan.agent.md - 3 script calls, 4 exit code checks
- ✅ speckit.tasks.agent.md - 1 script call, 3 exit code checks
- ✅ speckit.checklist.agent.md - 1 script call, 1 exit code check
- ✅ speckit.implement.agent.md - 1 script call, 3 exit code checks
- ✅ speckit.document.agent.md - 2 script calls, 3 exit code checks
- ✅ speckit.analyze.agent.md - 1 script call, 1 exit code check
- ✅ speckit.archive.agent.md - 6 script calls, 12 exit code checks
- ✅ speckit.taskstoissues.agent.md - 1 script call, 3 exit code checks

**Last verified**: 2026-01-14

<!-- END MANUAL ADDITIONS -->

---






