#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generates an OpenSpec-compliant proposal.md from SpecKit feature artifacts.

.DESCRIPTION
    The generate-proposal.ps1 script creates a proposal.md document by:
    - Extracting problem context from spec.md
    - Extracting solution summary from plan.md
    - Generating delta summary from file changes
    - Assembling into OpenSpec proposal format

.PARAMETER FeatureDir
    Path to feature directory containing spec.md and plan.md.

.PARAMETER OutputPath
    Optional. Where to write the proposal. Default: {FeatureDir}/proposal.md

.PARAMETER Author
    Optional. Proposal author name. Default: from git config user.name

.PARAMETER Template
    Optional. Template file path. Default: specs/templates/proposal-template.example.md

.PARAMETER Json
    Output generation status in JSON format.

.PARAMETER Help
    Display help message.

.OUTPUTS
    Generated proposal.md file. Returns JSON status if -Json specified.

.EXAMPLE
    ./generate-proposal.ps1 -FeatureDir "specs/001-feature"
    Generates proposal.md in the feature directory.

.EXAMPLE
    ./generate-proposal.ps1 -FeatureDir "specs/001-feature" -OutputPath "changes/proposal.md"
    Generates proposal at custom output path.

.NOTES
Exit Codes:
    0 - Success (proposal generated)
    1 - Error (missing required files or generation failed)
#>

param(
    [Parameter(Mandatory=$False, Position=0)]
    [string]$FeatureDir,

    [string]$OutputPath,

    [string]$Author,

    [string]$Template,

    [switch]$Json,

    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Host @"
Usage: generate-proposal.ps1 -FeatureDir <path> [-OutputPath <path>] [-Author <name>] [-Json]

Generates an OpenSpec-compliant proposal.md from SpecKit feature artifacts.

PARAMETERS:
  -FeatureDir <path>   Required. Path to feature directory
  -OutputPath <path>   Optional. Output file path (default: FeatureDir/proposal.md)
  -Author <name>       Optional. Author name (default: git config user.name)
  -Template <path>     Optional. Template file path
  -Json                Output generation status in JSON format
  -Help                Display this help message

EXAMPLES:
  ./generate-proposal.ps1 -FeatureDir "specs/001-feature"
  ./generate-proposal.ps1 -FeatureDir "specs/001-feature" -Author "Jane Doe" -Json

"@
    exit 0
}

# Import common functions
$ExitCodes = @{ Success = 0; Validation = 1; Operation = 2 }
$ScriptDir = $PSScriptRoot
$CommonPath = Join-Path $ScriptDir "common.ps1"
if (-not (Test-Path $CommonPath)) {
    Write-Error "Required file not found: $CommonPath"
    exit $ExitCodes.Operation
}

try {
    . $CommonPath
} catch {
    $LoadError = $_.Exception
    Write-Error "Failed to load common.ps1 from '$CommonPath'. Ensure the SpecKit scripts directory is intact. Error: $($LoadError.Message)"
    exit $ExitCodes.Operation
}

$ExitCodes = Get-ExitCodes
Set-StrictErrorActionPreference | Out-Null
$Tracker = New-OperationTracker

$Script:AuditRun = New-WorkflowScriptRunMetadata -ScriptName 'generate-proposal.ps1'
$Script:AuditContext = New-WorkflowAuditContext -ScriptName 'generate-proposal.ps1' -Action 'generate-proposal' `
    -ChangeId (Get-CurrentChangeId) -RunId $Script:AuditRun.run_id
$Script:AuditStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Initialize result object
$Result = @{
    status = "SUCCESS"
    message = ""
    output_path = ""
    extracted = @{
        title = ""
        why_section = ""
        what_section = ""
        benefits = @()
        risks = @()
        dependencies = @()
    }
    deltas = @{
        added = 0
        modified = 0
        removed = 0
        renamed = 0
        total = 0
        files = @()
    }
    timestamp = Get-StandardTimestamp
}

function Exit-WithError {
    <#
    .SYNOPSIS
        Writes an error response and exits with the given code.
    .PARAMETER Message
        Error message to report.
    .PARAMETER Data
        Structured data to include in JSON output.
    .PARAMETER ExitCode
        Exit code to return.
    .PARAMETER Status
        Status string for JSON output.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$Data,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [int]$ExitCode,

        [string]$Status = "validation_error"
    )

    if ($Json) {
        Write-JsonResult -Result (New-JsonResult -Status $Status -ScriptName "generate-proposal.ps1" -Data $Data -Errors @($Message))
    } else {
        Write-Error $Message
    }

    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'failure' -ErrorRecord $Message `
        -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null

    exit $ExitCode
}

# =============================================================================
# VALIDATION
# =============================================================================

# Auto-detect feature directory if not provided
if (-not $FeatureDir) {
    $EnvData = Get-FeaturePathsEnv
    $FeatureDir = $EnvData.FEATURE_DIR

    if (-not $FeatureDir -or -not (Test-Path $FeatureDir)) {
        Exit-WithError -Message "Could not auto-detect feature directory. Please specify -FeatureDir." -Data @{ feature_dir = $FeatureDir } -ExitCode $ExitCodes.Validation
    }
}

# Validate feature directory exists
if (-not (Test-Path $FeatureDir)) {
    Exit-WithError -Message "Feature directory not found: $FeatureDir" -Data @{ feature_dir = $FeatureDir } -ExitCode $ExitCodes.Validation
}

$Script:AuditContext.change_id = Split-Path -Path $FeatureDir -Leaf

# Validate required files exist
$SpecFile = Join-Path $FeatureDir "spec.md"
$PlanFile = Join-Path $FeatureDir "plan.md"

if (-not (Test-Path $SpecFile)) {
    Exit-WithError -Message "Cannot generate proposal: spec.md not found in $FeatureDir" -Data @{ spec_file = $SpecFile } -ExitCode $ExitCodes.Validation
}

if (-not (Test-Path $PlanFile)) {
    Exit-WithError -Message "Cannot generate proposal: plan.md not found in $FeatureDir" -Data @{ plan_file = $PlanFile } -ExitCode $ExitCodes.Validation
}

# Set default output path
if (-not $OutputPath) {
    $OutputPath = Join-Path $FeatureDir "proposal.md"
}
$Result.output_path = $OutputPath

# =============================================================================
# EXTRACTION FUNCTIONS
# =============================================================================

function Get-TitleFromSpec {
    <#
    .SYNOPSIS
        Extracts the title from a spec.md file.
    .PARAMETER Content
        Spec content to parse.
    .OUTPUTS
        Title string or $Null.
    #>
    param([string]$Content)

    # Pattern: # Feature Specification: Title OR # Proposal: Title OR # Title
    # Use multiline mode with (?m) and match at start of string
    if ($Content -match '(?m)^# (?:Feature Specification: |Proposal: )?(.+)$' ) {
        return $Matches[1].Trim()
    }
    return "Untitled Feature"
}

function Get-WhySection {
    <#
    .SYNOPSIS
        Extracts the "Why" section from spec.md content.
    .PARAMETER Content
        Spec content to parse.
    .OUTPUTS
        Section content string.
    #>
    param([string]$Content)

    $Why = ""

    # Try extraction in order of preference
    # 1. ## Problem Statement section
    if ($Content -match '(?ms)^## Problem Statement\s*\n(.+?)(?=^## |\z)') {
        $Why = $Matches[1].Trim()
    }
    # 2. ## Why section
    elseif ($Content -match '(?ms)^## Why\s*\n(.+?)(?=^## |\z)') {
        $Why = $Matches[1].Trim()
    }
    # 3. ## System Context (first paragraph)
    elseif ($Content -match '(?ms)^## System Context\s*\n(.+?)(?:\n\n|^## |\z)') {
        $Why = $Matches[1].Trim()
    }
    # 4. First paragraph after title
    elseif ($Content -match '^# .+?\n\n(.+?)(?:\n\n|^## )') {
        $Why = $Matches[1].Trim()
    }

    return $Why
}

function Get-WhatSection {
    <#
    .SYNOPSIS
        Extracts the "What" section from plan.md content.
    .PARAMETER Content
        Plan content to parse.
    .OUTPUTS
        Section content string.
    #>
    param([string]$Content)

    $What = ""

    # Try extraction in order of preference
    # 1. ## Summary section
    if ($Content -match '(?ms)^## Summary\s*\n(.+?)(?=^## |\z)') {
        $What = $Matches[1].Trim()
    }
    # 2. ## What section
    elseif ($Content -match '(?ms)^## What\s*\n(.+?)(?=^## |\z)') {
        $What = $Matches[1].Trim()
    }
    # 3. ## Solution section
    elseif ($Content -match '(?ms)^## Solution\s*\n(.+?)(?=^## |\z)') {
        $What = $Matches[1].Trim()
    }
    # 4. First section of plan.md (after title)
    elseif ($Content -match '(?ms)^## .+?\s*\n(.+?)(?=^## |\z)') {
        $What = $Matches[1].Trim()
    }

    return $What
}

function Get-SuccessCriteria {
    <#
    .SYNOPSIS
        Extracts success criteria bullets from spec.md.
    .PARAMETER Content
        Spec content to parse.
    .OUTPUTS
        Array of criteria strings.
    #>
    param([string]$Content)

    $Criteria = @()

    # Pattern: - **SC-###**: Description
    $Matches = [regex]::Matches($Content, '(?m)^- \*\*SC-\d+\*\*: (.+)$')
    foreach ($Match in $Matches) {
        $Criteria += $Match.Groups[1].Value.Trim()
    }

    return $Criteria
}

function Get-Constraints {
    <#
    .SYNOPSIS
        Extracts constraint bullets from spec.md.
    .PARAMETER Content
        Spec content to parse.
    .OUTPUTS
        Array of constraint strings.
    #>
    param([string]$Content)

    $Constraints = @()

    # Extract from ## Constraints or ## Constraints & Tradeoffs section
    if ($Content -match '(?ms)^## Constraints(?: & Tradeoffs)?\s*\n(.+?)(?=^## |\z)') {
        $Section = $Matches[1]
        # Get bullet points
        $BulletMatches = [regex]::Matches($Section, '(?m)^- (.+)$')
        foreach ($Match in $BulletMatches) {
            $Constraints += $Match.Groups[1].Value.Trim()
        }
    }

    return $Constraints
}

function Get-Assumptions {
    <#
    .SYNOPSIS
        Extracts assumption bullets from spec.md.
    .PARAMETER Content
        Spec content to parse.
    .OUTPUTS
        Array of assumption strings.
    #>
    param([string]$Content)

    $Assumptions = @()

    # Extract from ## Assumptions section
    if ($Content -match '(?ms)^## Assumptions\s*\n(.+?)(?=^## |\z)') {
        $Section = $Matches[1]
        # Get bullet points
        $BulletMatches = [regex]::Matches($Section, '(?m)^- (.+)$')
        foreach ($Match in $BulletMatches) {
            $Assumptions += $Match.Groups[1].Value.Trim()
        }
    }

    return $Assumptions
}

function Get-GitAuthor {
    <#
    .SYNOPSIS
        Retrieves the git user.name author or a fallback value.
    .OUTPUTS
        Author name string.
    #>
    try {
        $Result = Invoke-GitCommand -GitArgs @('config', 'user.name') -IgnoreErrors
        if ($Result.Success -and $Result.Output) {
            return ($Result.Output | Select-Object -First 1).Trim()
        }
    } catch {}
    return "Unknown Author"
}

function Get-FeatureBranch {
    <#
    .SYNOPSIS
        Retrieves the current git branch name or falls back to directory name.
    .OUTPUTS
        Branch name string.
    #>
    try {
        $Result = Invoke-GitCommand -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD') -IgnoreErrors
        if ($Result.Success -and $Result.Output) {
            return ($Result.Output | Select-Object -First 1).Trim()
        }
    } catch {}

    # Fall back to directory name
    return (Split-Path $FeatureDir -Leaf)
}

# =============================================================================
# EXTRACTION
# =============================================================================

# Read source files
$SpecContent = Get-FileContentCached -Path $SpecFile -Raw
$PlanContent = Get-FileContentCached -Path $PlanFile -Raw

# Extract title
$Result.extracted.title = Get-TitleFromSpec -Content $SpecContent
if (-not $Result.extracted.title) {
    $Result.extracted.title = Get-FeatureBranch
}

# Extract Why section from spec.md
$Result.extracted.why_section = Get-WhySection -Content $SpecContent

# Extract What section from plan.md
$Result.extracted.what_section = Get-WhatSection -Content $PlanContent

# Extract benefits (success criteria)
$Result.extracted.benefits = Get-SuccessCriteria -Content $SpecContent

# Extract risks (constraints)
$Result.extracted.risks = Get-Constraints -Content $SpecContent

# Extract dependencies (assumptions)
$Result.extracted.dependencies = Get-Assumptions -Content $SpecContent

# =============================================================================
# DELTA DETECTION
# =============================================================================

# Use Get-FileDeltas from common.ps1 if available
try {
    $Deltas = Get-FileDeltas -FeatureDir $FeatureDir

    foreach ($Delta in $Deltas) {
        $Result.deltas.total++
        $Result.deltas.files += $Delta

        switch ($Delta.Type) {
            "ADDED"    { $Result.deltas.added++ }
            "MODIFIED" { $Result.deltas.modified++ }
            "REMOVED"  { $Result.deltas.removed++ }
            "RENAMED"  { $Result.deltas.renamed++ }
        }
    }
} catch {
    # Fall back to simple git status
    if (Test-HasGit) {
        try {
            $StatusResult = Invoke-GitCommand -GitArgs @('status', '--porcelain', '--', $FeatureDir) -IgnoreErrors
            if ($StatusResult.Success -and $StatusResult.Output) {
                $Lines = $StatusResult.Output -split "`n" | Where-Object { $_ -match '\S' }
                foreach ($Line in $Lines) {
                    $Result.deltas.total++
                    $Result.deltas.modified++
                    $Result.deltas.files += @{
                        Type = "MODIFIED"
                        Path = $Line.Substring(3).Trim()
                    }
                }
            } elseif (-not $StatusResult.Success) {
                Write-LogWarning "[speckit] Git status fallback failed: $($StatusResult.Error)"
            }
        } catch {}
    }
}

# Validate we have deltas
if ($Result.deltas.total -eq 0) {
    $Result.status = "WARN"
    $Result.message = "No deltas found - proposal may be incomplete"
}

# =============================================================================
# GENERATE PROPOSAL
# =============================================================================

# Get author and change_id
if (-not $Author) {
    $Author = Get-GitAuthor
}
$ChangeId = Get-FeatureBranch

# Generate proposal content
$ProposalContent = @"
---
change_id: "$ChangeId"
author: "$Author"
date: "$(Get-StandardDate)"
status: "proposed"
---

# Proposal: $($Result.extracted.title)

## Why

$($Result.extracted.why_section)

$(if ($Result.extracted.benefits.Count -gt 0) {
"### Pain Points"
$Result.extracted.benefits | ForEach-Object { "- $_" }
} else { "" })

## What

$($Result.extracted.what_section)

## Impact

### Benefits
$(if ($Result.extracted.benefits.Count -gt 0) {
    $Result.extracted.benefits | ForEach-Object { "- $_" }
} else {
    "- [Benefits extracted from success criteria]"
})

### Risks
$(if ($Result.extracted.risks.Count -gt 0) {
    "| Risk | Mitigation |"
    "|------|------------|"
    $Result.extracted.risks | ForEach-Object { "| $_ | [To be defined] |" }
} else {
    "No critical risks identified."
})

### Dependencies
$(if ($Result.extracted.dependencies.Count -gt 0) {
    $Result.extracted.dependencies | ForEach-Object { "- $_" }
} else {
    "- PowerShell 7+"
    "- Git (optional)"
})

### Affected Components
| Component | Change Type | Notes |
|-----------|-------------|-------|
$(foreach ($File in $Result.deltas.files) {
    $Path = if ($File.Path) { $File.Path } else { $File }
    $Type = if ($File.Type) { $File.Type } else { "Modified" }
    "| $Path | $Type | |"
})

## Delta Summary

| Operation | Count |
|-----------|-------|
| ADDED | $($Result.deltas.added) |
| MODIFIED | $($Result.deltas.modified) |
| REMOVED | $($Result.deltas.removed) |
| RENAMED | $($Result.deltas.renamed) |
| **Total** | **$($Result.deltas.total)** |

### File Changes
$(foreach ($File in $Result.deltas.files) {
    $Path = if ($File.Path) { $File.Path } else { $File }
    $Type = if ($File.Type) { $File.Type } else { "MODIFIED" }
    if ($File.NewPath) {
        "- **$Type**: $Path → $($File.NewPath)"
    } else {
        "- **$Type**: $Path"
    }
})

## Approval

- [ ] Technical review complete
- [ ] Stakeholder sign-off
- [ ] Ready for implementation
"@

if ($ProposalContent -is [System.Array]) {
    $ProposalContent = ($ProposalContent | ForEach-Object { $_.ToString() }) -join "`n"
}

# Write proposal
try {
    if ((Test-Path $OutputPath) -and -not $Tracker.Backups.ContainsKey($OutputPath)) {
        $BackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("generate-proposal-backup-{0}.bak" -f ([Guid]::NewGuid().ToString()))
        Copy-Item -LiteralPath $OutputPath -Destination $BackupPath -Force -ErrorAction Stop
        Add-TrackedBackup -Tracker $Tracker -Destination $OutputPath -Backup $BackupPath
    }

    Write-CacheFileAtomic -Path $OutputPath -Content $ProposalContent
    if (-not $Tracker.Backups.ContainsKey($OutputPath)) {
        Add-TrackedFile -Tracker $Tracker -Path $OutputPath
    }

    if ($Result.status -ne "WARN") {
        $Result.status = "SUCCESS"
    }
    $Result.message = "Proposal generated successfully at $OutputPath"
} catch {
    Invoke-TrackedRollback -Tracker $Tracker
    Exit-WithError -Message "Failed to write proposal: $_" -Data @{ output_path = $OutputPath } -ExitCode $ExitCodes.Operation -Status "operation_error"
}

# =============================================================================
# OUTPUT
# =============================================================================

if ($Json) {
    $Status = if ($Result.status -eq "ERROR") { "operation_error" } else { "success" }
    $Warnings = if ($Result.status -eq "WARN") { @($Result.message) } else { @() }
    Write-JsonResult -Result (New-JsonResult -Status $Status -ScriptName "generate-proposal.ps1" -Data $Result -Warnings $Warnings)
} else {
    Write-Host ""
    Write-Host "=== Proposal Generation ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Feature: $FeatureDir"
    Write-Host "Output:  $OutputPath"
    Write-Host "Status:  $($Result.status)" -ForegroundColor $(if ($Result.status -eq "SUCCESS") { "Green" } elseif ($Result.status -eq "WARN") { "Yellow" } else { "Red" })
    Write-Host ""
    Write-Host "Extracted:"
    Write-Host "  Title: $($Result.extracted.title)"
    Write-Host "  Benefits: $($Result.extracted.benefits.Count)"
    Write-Host "  Risks: $($Result.extracted.risks.Count)"
    Write-Host "  Dependencies: $($Result.extracted.dependencies.Count)"
    Write-Host ""
    Write-Host "Deltas:"
    Write-Host "  Added:    $($Result.deltas.added)"
    Write-Host "  Modified: $($Result.deltas.modified)"
    Write-Host "  Removed:  $($Result.deltas.removed)"
    Write-Host "  Renamed:  $($Result.deltas.renamed)"
    Write-Host "  Total:    $($Result.deltas.total)"
    Write-Host ""

    if ($Result.status -eq "SUCCESS" -or $Result.status -eq "WARN") {
        Write-Host "Proposal saved to: $OutputPath" -ForegroundColor Green
    }
}

# Exit code
if ($Result.status -eq "ERROR") {
    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'failure' -ErrorRecord $Result.message `
        -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null
    exit $ExitCodes.Operation
}

Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'success' -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null

exit $ExitCodes.Success

