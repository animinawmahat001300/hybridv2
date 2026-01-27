# Style Guide

This document defines the style and conventions used in this project.
All contributions should follow these rules unless otherwise noted.

## 1. General Code Style

- Favor clarity over brevity.
- Keep functions and methods small and focused.
- Avoid repeating logic; prefer shared helpers/utilities (source from `common.ps1`).
- Remove unused variables, imports, code paths, and files.
- End all files with a newline character.
- Use UTF-8 encoding without BOM.

## 2. PowerShell Coding Standards

### 2.1 File Structure

Every PowerShell script should follow this structure:

```powershell
#!/usr/bin/env pwsh
# Brief description of the script purpose
# Additional context or change history

<#
.SYNOPSIS
    One-line description of what the script does.

.DESCRIPTION
    Detailed description of functionality, behavior, and use cases.

.PARAMETER ParameterName
    Description of each parameter.

.EXAMPLE
    .\script-name.ps1 -Parameter "value"
    Description of what this example does.

.NOTES
File: script-name.ps1
Author: SpecKit Consolidated
Requires: PowerShell 7+
Exit Codes:
    0 - Success
    1 - Error (validation failed)
    2 - Error (operation failed)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$RequiredParam,

    [switch]$Json,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Show help if requested
if ($Help) {
    # Display formatted help text
    exit 0
}

# Source common functions
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $ScriptDir "common.ps1")

# Main script logic here
```

### 2.2 Naming Conventions

| Item              | Convention         | Example                    |
|-------------------|--------------------|----------------------------|
| Variables         | `PascalCase`       | `$FeatureId`, `$RepoRoot`  |
| Functions         | `Verb-Noun`        | `Get-WorkspaceRoot`        |
| Script Parameters | `PascalCase`       | `$FeatureDir`, `$OutputPath` |
| Script Files      | `kebab-case.ps1`   | `create-new-feature.ps1`   |
| Constants         | `PascalCase`       | `$MaxRetries`, `$DefaultTimeout` |
| Script-scoped     | `$Script:VarName`  | `$Script:GovernanceDataCache` |

**Approved PowerShell Verbs:** Use standard approved verbs from `Get-Verb`:
- `Get-`, `Set-`, `New-`, `Remove-`, `Test-`, `Invoke-`, `Write-`, `Read-`

### 2.3 Formatting Rules

- **Indentation:** 4 spaces (no tabs)
- **Line length:** Maximum 120 characters
- **Braces:** K&R style (opening brace on same line)

```powershell
# Good - K&R style
if ($Condition) {
    Do-Something
} else {
    Do-SomethingElse
}

# Good - function definition
function Get-FeatureDir {
    param(
        [Parameter(Position=0)]
        [string]$FeatureId
    )
    # Function body
}
```

- **Spacing:**
  - One space after keywords: `if ($x)`, not `if($x)`
  - One space around operators: `$a = $b + $c`
  - One blank line between functions
  - No trailing whitespace

### 2.4 Parameter Handling

```powershell
# Standard parameter pattern with typed parameters
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [Alias("Slug")]
    [string]$FeatureId,

    [Parameter(ValueFromRemainingArguments = $True)]
    [string[]]$Description,

    [switch]$Force,
    [switch]$WhatIf,
    [switch]$Json,
    [switch]$Help
)

# Always include -Help and -Json switches for user-facing scripts
```

### 2.5 Error Handling

```powershell
# Set error action preference at script start
$ErrorActionPreference = 'Stop'

# Use try-catch for critical operations
try {
    $Result = Some-RiskyOperation -ErrorAction Stop
}
catch {
    Write-Error "Operation failed: $_"
    exit 1
}

# Use -ErrorAction for individual commands
New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null

# Suppress expected errors with SilentlyContinue
$GitResult = git rev-parse --show-toplevel 2>$Null
if ($LASTEXITCODE -ne 0) {
    # Handle git not available
}
```

### 2.6 Output Patterns

```powershell
# JSON output for automation
$Result = @{
    status = "SUCCESS"
    message = ""
    timestamp = Get-StandardTimestamp
}

if ($Json) {
    $Result | ConvertTo-Json -Depth 10
} else {
    Write-Host $Result.message
}

# Colored console output
Write-Host "=== SECTION HEADER ===" -ForegroundColor Cyan
Write-Host "Success!" -ForegroundColor Green
Write-Host "Warning: something" -ForegroundColor Yellow
Write-Error "Error message"  # Goes to stderr
```

### 2.7 Exit Codes

Document and use consistent exit codes:

| Code | Meaning                        |
|------|--------------------------------|
| `0`  | Success                        |
| `1`  | General error / validation failed |
| `2`  | Operation failed               |

```powershell
# Document in comment-based help
<#
.NOTES
Exit Codes:
    0 - Success (feature created)
    1 - Error (validation failed)
    2 - Error (operation failed)
#>

# Use consistently
if (-not $FeatureId) {
    Write-Error "FeatureId is required"
    exit 1
}
```

### 2.8 Common Functions

Source shared utilities from `common.ps1`:

```powershell
# Standard sourcing pattern
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { $ScriptDir = Get-Location }

if (Test-Path (Join-Path $ScriptDir "common.ps1")) {
    . (Join-Path $ScriptDir "common.ps1")
} else {
    Write-Error "Could not find common.ps1 in $ScriptDir"
    exit 1
}

# Use shared functions
$RepoRoot = Get-RepositoryRoot
$FeatureDir = Get-FeatureDir $FeatureId
$Timestamp = Get-StandardTimestamp
```

## 3. Markdown Documentation Standards

### 3.1 File Structure

```markdown
# Document Title

Brief introduction or purpose statement.

## Section 1

Content here.

### Subsection 1.1

More detailed content.

---

## Section 2

Additional sections as needed.
```

### 3.2 Naming Conventions

| Item              | Convention           | Example                    |
|-------------------|----------------------|----------------------------|
| File names        | `kebab-case.md`      | `spec-template.md`         |
| Placeholders      | `{UPPER_SNAKE_CASE}` | `{FEATURE_NAME}`           |
| Headings          | Sentence case        | `## User stories`          |
| Template vars     | `{DESCRIPTIVE_NAME}` | `{YYYY_MM_DD}`             |

### 3.3 Header Style

Use ATX-style headers (not Setext):

```markdown
# Good - ATX style
## Section
### Subsection

# Bad - Setext style (don't use)
Section
-------
```

- Use sentence case for headers (capitalize first word only)
- Don't skip heading levels (H1 → H2 → H3)
- Surround headers with blank lines
- Don't add trailing punctuation to headers

### 3.4 Lists

Use hyphens for unordered lists:

```markdown
# Good
- Item one
- Item two
- Item three

# Bad (don't use asterisks or plus)
* Item one
+ Item two
```

For ordered lists, use `1.` for all items:

```markdown
1. First step
1. Second step
1. Third step
```

### 3.5 Code Blocks

Always use fenced code blocks with language identifiers:

````markdown
```powershell
$Variable = "value"
Get-ChildItem -Path $Variable
```

```markdown
# Example markdown
- List item
```

```text
Plain text output
```
````

Use inline code for:
- File paths: `specs/scripts/common.ps1`
- Command names: `Get-WorkspaceRoot`
- Variable names: `$FeatureId`
- Parameter values: `-ErrorAction Stop`

### 3.6 Tables

Format tables with aligned columns:

```markdown
| Column 1   | Column 2    | Column 3       |
|------------|-------------|----------------|
| Value A    | Description | Additional     |
| Value B    | Description | Additional     |
```

### 3.7 Links

Use inline links with descriptive text:

```markdown
# Good - descriptive link text
See the [constitution](specs/memory/constitution.md) for governance rules.

# Good - reference to file paths
Edit `specs/templates/spec-template.md` to change the template.

# Avoid - raw URLs without context
https://example.com
```

### 3.8 Emphasis

```markdown
**Bold** for important terms and UI elements
*Italic* for emphasis or technical terms on first use
`code` for file names, commands, variables, and paths
```

### 3.9 AI Instructions Pattern

Use blockquotes for embedded instructions:

```markdown
> **AI Instructions - Section Name**:
> - Instruction one
> - Instruction two
> - Use `{PLACEHOLDER}` format for required values
```

### 3.10 Placeholders

Use `{UPPER_SNAKE_CASE}` for template placeholders:

```markdown
# Feature Specification: {FEATURE_NAME}

**Branch**: `{ISSUE_NUMBER}-{FEATURE_NAME}`
**Created**: {YYYY_MM_DD}
**Status**: Draft

{DESCRIPTION_OF_FEATURE}
```

## 4. Comments & Documentation

### 4.1 PowerShell Comments

```powershell
# Single-line comments explain WHY, not WHAT
# Good: Fallback to script location if git root detection fails
# Bad:  Set variable to path

<#
Multi-line comments for complex explanations
or temporarily disabling code blocks
#>

# Use these tags consistently:
# TODO: follow-up work needed
# FIXME: known incorrect behavior
# NOTE: non-obvious design decision
# CORRECTED: documents a fix (with reference)
```

### 4.2 Function Documentation

All public functions require comment-based help:

```powershell
function Get-FeatureDir {
    <#
    .SYNOPSIS
        Gets the directory for a specific feature or the current feature
    .PARAMETER FeatureId
        Optional. The feature ID (e.g., "001-openspec-integration").
        If not provided, uses Get-CurrentChangeId to detect current feature.
    .OUTPUTS
        String path to feature directory, or $Null if not found
    #>
    param(
        [Parameter(Position=0)]
        [string]$FeatureId
    )
    # Implementation
}
```

## 5. Best Practices and Anti-Patterns

### 5.1 Do

- ✅ Use `$ErrorActionPreference = 'Stop'` at script start
- ✅ Provide `-Help` and `-Json` switches for user-facing scripts
- ✅ Source `common.ps1` for shared utilities
- ✅ Document exit codes in comment-based help
- ✅ Use try-catch for operations that can fail
- ✅ Return structured objects for JSON output
- ✅ Use `Test-Path` before accessing files
- ✅ Use absolute paths via `Get-RepositoryRoot`

### 5.2 Don't

- ❌ Use global variables (prefer script-scoped `$Script:`)
- ❌ Hardcode paths (use `Join-Path` and root detection)
- ❌ Ignore errors silently without handling
- ❌ Use aliases in scripts (`%` → `ForEach-Object`, `?` → `Where-Object`)
- ❌ Skip comment-based help on public functions
- ❌ Use tabs for indentation
- ❌ Leave debug/test code in commits

### 5.3 Common Patterns

**Path Construction:**
```powershell
# Good - cross-platform path handling
$SpecFile = Join-Path $FeatureDir "spec.md"
$ChangesDir = Join-Path $RepoRoot "specs" "changes"

# Bad - hardcoded separators
$SpecFile = "$FeatureDir\spec.md"
```

**Null Checking:**
```powershell
# Good - explicit null check
if (-not $FeatureId) {
    Write-Warning "No feature ID provided"
    return $Null
}

# Good - null coalescing pattern
$SearchPath = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
```

**Git Operations:**
```powershell
# Good - handle git not available
try {
    $Result = git rev-parse --abbrev-ref HEAD 2>$Null
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed"
    }
}
catch {
    Write-Verbose "Git not available: $_"
}
```

## 6. Commit & Review Practices

### 6.1 Commits

- One logical change per commit
- Write clear commit messages:

```text
Short summary (max ~50 chars)

Optional longer explanation of context and rationale.
Reference issue numbers where applicable.

Fixes #123
```

### 6.2 Branch Naming

Follow the pattern: `{NUMBER}-{short-description}`

```text
001-user-authentication
002-api-endpoints
fix-validation-error
```

### 6.3 Reviews

- Keep pull requests reasonably small
- Be respectful and constructive in review discussions
- Address requested changes or explain if you disagree
- Verify scripts run without errors before submitting

## 7. Testing

- Run `.\validate.ps1` before committing changes
- Test scripts with `-WhatIf` when available
- Use `-Json` output to verify structured data
- Test both success and error paths

```powershell
# Test success path
.\create-new-feature.ps1 "Test feature" -Json

# Test error handling
.\archive-feature.ps1 -FeatureId "nonexistent" -WhatIf
```

## 8. Changes to This Guide

Style evolves. Propose improvements by:
1. Opening an issue describing the proposed change
2. Submitting a pull request updating this document
3. Including rationale for the change

---

**References:**
- [PowerShell Practice and Style Guide](https://github.com/PoshCode/PowerShellPracticeAndStyle)
- [Markdown Style Guide](https://cirosantilli.com/markdown-style-guide/)
- Project constitution: `specs/memory/constitution.md`
