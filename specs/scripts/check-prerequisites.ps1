#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Check prerequisites for SpecKit consolidated workflow.

.DESCRIPTION
    Validates that the current environment meets requirements for running SpecKit agents.
    Checks for:
    - Feature branch context (not on main/master/develop)
    - Feature directory existence (specs/changes/<branch-name>/)
    - Available documentation files (spec.md, plan.md, tasks.md, etc.)

    This script is used by speckit.tasks, speckit.analyze, and speckit.implement agents
    to verify the environment before performing operations.

.PARAMETER Json
    Output results in JSON format (single line, compressed).
    Useful for automation and agent consumption.

.PARAMETER PathsOnly
    Return only the core paths (FEATURE_DIR, FEATURE_SPEC, IMPL_PLAN, TASKS).
    Reduces output to essential file locations.

.PARAMETER RequireTasks
    Require tasks.md to exist. Exits with error if not found.
    Use this when tasks.md is mandatory for the operation.

.PARAMETER IncludeTasks
    Include the full content of tasks.md in the output (as TASKS_CONTENT property).
    Only applies if tasks.md exists.

.PARAMETER Help
    Display this help message and exit.

.EXAMPLE
    .\check-prerequisites.ps1

    Performs standard prerequisite check and displays results in human-readable format.
    Shows repository root, branch name, feature directory, and available documents.

.EXAMPLE
    .\check-prerequisites.ps1 -Json

    Returns prerequisite information as JSON for agent consumption:
    {"REPO_ROOT":"C:\\repo","CURRENT_BRANCH":"feat/new-feature",...}

.EXAMPLE
    .\check-prerequisites.ps1 -RequireTasks -Json

    Validates that tasks.md exists before returning results.
    Exits with error if tasks.md is missing.

.EXAMPLE
    .\check-prerequisites.ps1 -PathsOnly

    Returns only essential paths without full environment details.

.EXAMPLE
    .\check-prerequisites.ps1 -IncludeTasks -Json

    Includes the full content of tasks.md in the JSON output as TASKS_CONTENT property.

.NOTES
    File Name      : check-prerequisites.ps1
    Prerequisite   : common.ps1 must be in the same directory
    Used By        : speckit.tasks, speckit.analyze, speckit.implement agents

    Exit Codes:
    - 0: Success (all prerequisites met)
    - 1: Failure (not on feature branch, missing directory, or missing required files)

    Required Environment:
    - Must be on a feature branch (not main/master/develop)
    - Feature directory must exist at specs/changes/<branch-name>/

    This script uses file-based state detection per ADR-0002.

.LINK
    docs/speckit/ARCHITECTURE_OVERVIEW.md
    docs/speckit/architecture/ADR-0002-file-based-state.md
#>

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$PathsOnly,
    [switch]$RequireTasks,
    [switch]$IncludeTasks,
    [switch]$Help
)

# Display help if requested
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

$ErrorActionPreference = 'Stop'
$ExitCodes = @{ Success = 0; Validation = 1; Operation = 2 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not [System.IO.Path]::IsPathRooted($ScriptDir)) {
    $ScriptDir = (Resolve-Path $ScriptDir -ErrorAction Stop).Path
}

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
$CurrentBranch = $EnvData.CURRENT_BRANCH
$HasGit = $EnvData.HAS_GIT
$FeatureDir = $EnvData.FEATURE_DIR

# Normalize working directory to repo root to avoid positional parameter parsing when invoked from subfolders (e.g., specs/memory)
if ($RepoRoot -and (Test-Path $RepoRoot)) {
    $CurrentPath = (Resolve-Path . -ErrorAction SilentlyContinue).Path
    $RootPath = (Resolve-Path $RepoRoot -ErrorAction Stop).Path
    if ($CurrentPath -ne $RootPath) {
        Set-Location -Path $RootPath
    }
}

if (-not (Test-FeatureBranch -Branch $CurrentBranch -HasGit:$HasGit)) {
    $ErrorDetails = @{
        error = "Not on a feature branch: $CurrentBranch"
        context = "SpecKit requires a feature branch (not main/master/develop)"
        current_branch = $CurrentBranch
        suggestion = "Create or checkout a feature branch: git checkout -b feat/your-feature-name"
    }
    if ($Json) {
        Write-JsonResult -Result (New-JsonResult -Status "validation_error" -ScriptName "check-prerequisites.ps1" -Data $ErrorDetails -Errors @("Not on a feature branch") )
    } else {
        Write-Error "Not on a feature branch: $CurrentBranch`nSpecKit requires a feature branch (not main/master/develop)`nSuggestion: git checkout -b feat/your-feature-name"
    }
    exit $ExitCodes.Validation
}

if (-not (Test-Path $FeatureDir)) {
    $ErrorDetails = @{
        error = "Feature directory not found"
        context = "Expected feature directory does not exist"
        expected_path = $FeatureDir
        current_branch = $CurrentBranch
        suggestion = "Initialize feature: .\create-new-feature.ps1 or ensure you're on the correct branch"
    }
    if ($Json) {
        Write-JsonResult -Result (New-JsonResult -Status "validation_error" -ScriptName "check-prerequisites.ps1" -Data $ErrorDetails -Errors @("Feature directory not found") )
    } else {
        Write-Error "Feature directory not found: $FeatureDir`nExpected directory for branch: $CurrentBranch`nSuggestion: Run .\create-new-feature.ps1 to initialize the feature"
    }
    exit $ExitCodes.Validation
}

$SpecFile = $EnvData.FEATURE_SPEC
$PlanFile = $EnvData.IMPL_PLAN
$TasksFile = $EnvData.TASKS

$AvailableDocs = @()
if (Test-Path $SpecFile) { $AvailableDocs += $SpecFile }
if (Test-Path $PlanFile) { $AvailableDocs += $PlanFile }
if (Test-Path $TasksFile) { $AvailableDocs += $TasksFile }
if (Test-Path $EnvData.RESEARCH) { $AvailableDocs += $EnvData.RESEARCH }
if (Test-Path $EnvData.DATA_MODEL) { $AvailableDocs += $EnvData.DATA_MODEL }
if (Test-Path $EnvData.QUICKSTART) { $AvailableDocs += $EnvData.QUICKSTART }
if (Test-Path $EnvData.CHECKLIST) { $AvailableDocs += $EnvData.CHECKLIST }

# Check contracts directory (only if it exists and has YAML files)
if (Test-Path $EnvData.CONTRACTS_DIR) {
    $Contracts = Get-ChildItem -Path $EnvData.CONTRACTS_DIR -Filter "*.yaml" -File -ErrorAction SilentlyContinue
    if ($Contracts.Count -gt 0) { $AvailableDocs += "contracts/" }
}

# Check checklists directory (only if it exists and has markdown files) - T1.4
if (Test-Path $EnvData.CHECKLISTS_DIR) {
    $Checklists = Get-ChildItem -Path $EnvData.CHECKLISTS_DIR -Filter "*.md" -File -ErrorAction SilentlyContinue
    if ($Checklists.Count -gt 0) { $AvailableDocs += "checklists/ ($($Checklists.Count) files)" }
}

if ($RequireTasks -and -not (Test-Path $TasksFile)) {
    $ErrorDetails = @{
        error = "Required file missing: tasks.md"
        context = "The -RequireTasks flag was specified but tasks.md does not exist"
        expected_path = $TasksFile
        current_branch = $CurrentBranch
        suggestion = "Generate tasks.md by running: /speckit.tasks agent with spec.md and plan.md"
        alternative = "Remove -RequireTasks flag if tasks.md is not mandatory for your operation"
    }
    if ($Json) {
        Write-JsonResult -Result (New-JsonResult -Status "validation_error" -ScriptName "check-prerequisites.ps1" -Data $ErrorDetails -Errors @("Required file missing: tasks.md") )
    } else {
        Write-Error "tasks.md not found at: $TasksFile`nThe -RequireTasks flag was specified but tasks.md does not exist.`nSuggestion: Run /speckit.tasks agent to generate tasks.md from spec.md and plan.md"
    }
    exit $ExitCodes.Validation
}

$Output = @{
    REPO_ROOT      = $RepoRoot
    CURRENT_BRANCH = $CurrentBranch
    HAS_GIT        = $HasGit
    FEATURE_DIR    = $FeatureDir
    FEATURE_SPEC   = $SpecFile
    IMPL_PLAN      = $PlanFile
    TASKS          = $TasksFile
    AVAILABLE_DOCS = $AvailableDocs
    SPECS_DIR      = $EnvData.SPECS_DIR
    CHANGES_DIR    = $EnvData.CHANGES_DIR
    CHECKLISTS_DIR = if ($EnvData.CHECKLISTS_DIR -and (Test-Path $EnvData.CHECKLISTS_DIR)) { $EnvData.CHECKLISTS_DIR } else { $Null }
    CONTRACTS_DIR  = if ($EnvData.CONTRACTS_DIR -and (Test-Path $EnvData.CONTRACTS_DIR)) { $EnvData.CONTRACTS_DIR } else { $Null }
    RESEARCH       = if ($EnvData.RESEARCH -and (Test-Path $EnvData.RESEARCH)) { $EnvData.RESEARCH } else { $Null }
    DATA_MODEL     = if ($EnvData.DATA_MODEL -and (Test-Path $EnvData.DATA_MODEL)) { $EnvData.DATA_MODEL } else { $Null }
    QUICKSTART     = if ($EnvData.QUICKSTART -and (Test-Path $EnvData.QUICKSTART)) { $EnvData.QUICKSTART } else { $Null }
    CHANGE_ID      = $EnvData.CHANGE_ID
}

if ($IncludeTasks -and (Test-Path $TasksFile)) {
    $Output.TASKS_CONTENT = Get-FileContentCached -Path $TasksFile -Raw
}

if ($PathsOnly) {
    $Output = @{
        FEATURE_DIR  = $FeatureDir
        FEATURE_SPEC = $SpecFile
        IMPL_PLAN    = $PlanFile
        TASKS        = $TasksFile
    }
}

if ($Json) {
    Write-JsonResult -Result (New-JsonResult -Status "success" -ScriptName "check-prerequisites.ps1" -Data $Output)
}
else {
    Write-Output "[speckit] Prerequisites Check"
    Write-Output "============================="
    Write-Output "Repository Root: $RepoRoot"
    Write-Output "Current Branch: $CurrentBranch"
    Write-Output "Has Git: $HasGit"
    Write-Output "Feature Directory: $FeatureDir"
    Write-Output ""
    Write-Output "Available Documents:"
    foreach ($Doc in $AvailableDocs) { Write-Output "  - $Doc" }
}

exit $ExitCodes.Success

