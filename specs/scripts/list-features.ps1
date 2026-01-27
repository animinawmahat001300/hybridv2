#!/usr/bin/env pwsh
<#
.SYNOPSIS
List all active features and changes with their workflow status.

.DESCRIPTION
The list-features.ps1 script scans the specs/changes/ directory and reports all
active features with their current status in the SpecKit workflow. Status is
determined by the presence of key workflow artifacts:

- Draft: Only feature directory exists
- Specified: Has spec.md
- Planned: Has spec.md and plan.md
- Ready: Has spec.md, plan.md, and tasks.md

Each feature shows which workflow artifacts are present:
- spec.md: Feature specification (from specify phase)
- plan.md: Technical implementation plan (from plan phase)
- tasks.md: Task breakdown (from tasks phase)

Archived features in specs/changes/archive/ are excluded from the listing.

.PARAMETER Json
Output the feature list in JSON format for programmatic consumption.
Without this flag, outputs a human-readable table.

.PARAMETER Help
Display this help message and exit.

.EXAMPLE
./list-features.ps1

Displays a formatted table of all active features with status and artifact indicators.

Output:
[speckit] Active Changes
========================

| Change ID | Status | Spec | Plan | Tasks |
| --------- | ------ | ---- | ---- | ----- |
| 001-auth  | Ready  | ✓    | ✓    | ✓     |
| 002-ui    | Planned| ✓    | ✓    | ✗     |

.EXAMPLE
./list-features.ps1 -Json

Outputs feature list in JSON format:
[
  {
    "Name": "001-auth",
    "Status": "Ready",
    "HasSpec": true,
    "HasPlan": true,
    "HasTasks": true,
    "Path": "C:\\repo\\specs\\changes\\001-auth"
  }
]

.EXAMPLE
./list-features.ps1 -Json | ConvertFrom-Json | Where-Object Status -eq 'Ready'

Filter for only features that are ready for implementation.

.EXAMPLE
$Features = ./list-features.ps1 -Json | ConvertFrom-Json
$Incomplete = $Features | Where-Object { -not $_.HasTasks }
Write-Host "Features needing tasks: $($Incomplete.Count)"

Count how many features still need task breakdown.

.EXAMPLE
cd hybrid
./specs/scripts/list-features.ps1

Run from the hybrid folder (recommended location). Script auto-detects specs/changes/
folder structure.

.NOTES
Exit Codes:
  0 - Success (feature list generated, even if empty)

Prerequisites:
  - common.ps1 in same directory (for helper functions)
  - specs/changes/ directory (auto-created if missing)

Status Determination:
  - Draft: Feature directory exists, no artifacts
  - Specified: spec.md exists
  - Planned: spec.md + plan.md exist
  - Ready: spec.md + plan.md + tasks.md exist

Architecture References:
  - SpecKit Architecture: docs/speckit/ARCHITECTURE_OVERVIEW.md
  - File-Based State: docs/speckit/architecture/ADR-0002-file-based-state.md
  - Multi-Agent Pipeline: docs/speckit/architecture/ADR-0001-multi-agent-pipeline.md

Workflow Phases:
  1. specify: Creates spec.md
  2. clarify: Refines spec.md
  3. plan: Creates plan.md
  4. tasks: Creates tasks.md
  5-11. Further workflow phases

Enhanced Display:
  The table output now includes:
  - Change ID (feature folder name)
  - Status (Draft/Specified/Planned/Ready)
  - Spec indicator (✓/✗)
  - Plan indicator (✓/✗)
  - Tasks indicator (✓/✗)

Issues:
  - Issue #6: Help system implementation (COMPLETE)
  - Issue #6: Enhanced status display (COMPLETE)

.LINK
https://github.com/rephlex/speckit

.LINK
docs/speckit/ARCHITECTURE_OVERVIEW.md
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Output feature list in JSON format")]
    [switch]$Json,

    [Parameter(HelpMessage="Display help message")]
    [switch]$Help
)
$ErrorActionPreference = 'Stop'
$ExitCodes = @{ Success = 0; Validation = 1; Operation = 2 }

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# Source common functions
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
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

$EnvData = Get-FeaturePathsEnv
$RepoRoot = $EnvData.REPO_ROOT
$ChangesDir = Join-Path $RepoRoot "specs" "changes"

$Features = @()

if (Test-Path $ChangesDir) {
    Get-ChildItem -Path $ChangesDir -Directory | Where-Object { $_.Name -ne 'archive' } | ForEach-Object {
        $FeatureDir = $_.FullName
        $FeatureName = $_.Name

        # Enhanced status detection with content-based analysis
        $SpecPath = Join-Path $FeatureDir "spec.md"
        $PlanPath = Join-Path $FeatureDir "plan.md"
        $TasksPath = Join-Path $FeatureDir "tasks.md"
        $ChecklistsDir = Join-Path $FeatureDir "checklists"

        $HasSpec = Test-Path $SpecPath
        $HasPlan = Test-Path $PlanPath
        $HasTasks = Test-Path $TasksPath
        $HasChecklists = Test-Path $ChecklistsDir

        $Status = "Draft"
        $StatusReason = "No spec.md found"

        if ($HasSpec) {
            $SpecContent = Get-FileContentCached -Path $SpecPath -Raw

            # Check for clarification markers
            if ($SpecContent -match '\[NEEDS CLARIFICATION') {
                $Status = "Needs Clarification"
                $StatusReason = "Spec has unresolved clarification markers"
            }
            elseif ($HasTasks) {
                $TasksContent = Get-FileContentCached -Path $TasksPath -Raw

                # Check if any tasks are completed
                if ($TasksContent -match '- \[x\]') {
                    $Status = "In Implementation"
                    $StatusReason = "Tasks have checked items"
                }
                else {
                    $Status = "Ready"
                    $StatusReason = "Tasks defined, none started"
                }
            }
            elseif ($HasChecklists) {
                $Status = "In Checklist Review"
                $StatusReason = "Checklists directory exists"
            }
            elseif ($HasPlan) {
                $Status = "Planned"
                $StatusReason = "Plan exists, no tasks yet"
            }
            else {
                $Status = "Specified"
                $StatusReason = "Spec exists, no plan yet"
            }
        }

        $Features += [PSCustomObject]@{
            Name          = $FeatureName
            Status        = $Status
            StatusReason  = $StatusReason
            HasSpec       = $HasSpec
            HasPlan       = $HasPlan
            HasTasks      = $HasTasks
            HasChecklists = $HasChecklists
            Path          = $FeatureDir
        }
    }
}

if ($Json) {
    Write-JsonResult -Result (New-JsonResult -Status "success" -ScriptName "list-features.ps1" -Data @{ features = $Features })
}
else {
    Write-Host ""
    Write-Host "[speckit] Active Changes" -ForegroundColor Cyan
    Write-Host "========================" -ForegroundColor Cyan
    Write-Host ""

    if ($Features.Count -eq 0) {
        Write-Host "No active changes found." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Use '/speckit.specify <description>' to create a new feature." -ForegroundColor Gray
        Write-Host ""
    }
    else {
        # Summary statistics
        $InImplCount = ($Features | Where-Object Status -eq 'In Implementation').Count
        $ReadyCount = ($Features | Where-Object Status -eq 'Ready').Count
        $ChecklistCount = ($Features | Where-Object Status -eq 'In Checklist Review').Count
        $PlannedCount = ($Features | Where-Object Status -eq 'Planned').Count
        $ClarifyCount = ($Features | Where-Object Status -eq 'Needs Clarification').Count
        $SpecifiedCount = ($Features | Where-Object Status -eq 'Specified').Count
        $DraftCount = ($Features | Where-Object Status -eq 'Draft').Count

        Write-Host "Summary: $($Features.Count) active features" -ForegroundColor White
        Write-Host "  In Implementation: $InImplCount  |  Ready: $ReadyCount  |  In Checklist Review: $ChecklistCount" -ForegroundColor Gray
        Write-Host "  Planned: $PlannedCount  |  Needs Clarification: $ClarifyCount  |  Specified: $SpecifiedCount  |  Draft: $DraftCount" -ForegroundColor Gray
        Write-Host ""

        # Table header
        Write-Host "| Change ID | Status | Spec | Plan | Tasks | Path |" -ForegroundColor White
        Write-Host "| --------- | ------ | ---- | ---- | ----- | ---- |" -ForegroundColor White

        # Table rows with color-coded status
        foreach ($Feature in $Features) {
            $SpecMark = if ($Feature.HasSpec) { "✓" } else { "✗" }
            $PlanMark = if ($Feature.HasPlan) { "✓" } else { "✗" }
            $TaskMark = if ($Feature.HasTasks) { "✓" } else { "✗" }
            $RelativePath = "specs/changes/$($Feature.Name)"

            # Color-code by status
            $StatusColor = switch ($Feature.Status) {
                'In Implementation'   { 'Magenta' }
                'Ready'               { 'Green' }
                'In Checklist Review' { 'Blue' }
                'Planned'             { 'Cyan' }
                'Needs Clarification' { 'Red' }
                'Specified'           { 'Yellow' }
                'Draft'               { 'Gray' }
                default               { 'White' }
            }

            Write-Host "| " -NoNewline
            Write-Host $Feature.Name -NoNewline -ForegroundColor White
            Write-Host " | " -NoNewline
            Write-Host $Feature.Status -NoNewline -ForegroundColor $StatusColor
            # Pad status to longest status name (19 chars for "In Checklist Review" / "Needs Clarification")
            $PadAmount = [Math]::Max(0, 19 - $Feature.Status.Length)
            Write-Host (" " * $PadAmount) -NoNewline
            Write-Host " | $SpecMark    | $PlanMark    | $TaskMark     | $RelativePath |"
        }

        Write-Host ""
        Write-Host "Legend:" -ForegroundColor Gray
        Write-Host "  ✓ = Present  |  ✗ = Missing" -ForegroundColor Gray
        Write-Host "  " -NoNewline
        Write-Host "In Implementation" -NoNewline -ForegroundColor Magenta
        Write-Host " = Tasks started  |  " -NoNewline -ForegroundColor Gray
        Write-Host "Ready" -NoNewline -ForegroundColor Green
        Write-Host " = Tasks defined" -ForegroundColor Gray
        Write-Host "  " -NoNewline
        Write-Host "In Checklist Review" -NoNewline -ForegroundColor Blue
        Write-Host " = Reviewing checklists  |  " -NoNewline -ForegroundColor Gray
        Write-Host "Planned" -NoNewline -ForegroundColor Cyan
        Write-Host " = Has plan" -ForegroundColor Gray
        Write-Host "  " -NoNewline
        Write-Host "Needs Clarification" -NoNewline -ForegroundColor Red
        Write-Host " = Unresolved markers  |  " -NoNewline -ForegroundColor Gray
        Write-Host "Specified" -NoNewline -ForegroundColor Yellow
        Write-Host " = Has spec" -ForegroundColor Gray
        Write-Host ""
    }
}

