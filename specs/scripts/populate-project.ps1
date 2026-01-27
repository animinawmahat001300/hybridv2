#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Updates project.md with feature information on create or archive.

.DESCRIPTION
    The populate-project.ps1 script manages the project registry (project.md):
    - On create: Adds new feature to Active Features table
    - On complete: Moves feature from Active to Completed Features table
    - Updates frontmatter counts and timestamps

.PARAMETER Action
    Required. The operation to perform: "add" or "complete"

.PARAMETER FeatureBranch
    Required. The feature branch name (e.g., "001-openspec-integration")

.PARAMETER FeatureName
    Optional. Display name for the feature. Auto-derived from branch if omitted.

.PARAMETER ProjectPath
    Optional. Path to project.md. Default: specs/project.md

.PARAMETER Json
    Output results in JSON format.

.EXAMPLE
    ./populate-project.ps1 -Action add -FeatureBranch "001-new-feature" -FeatureName "New Feature"
    Adds a new feature to the Active Features table.

.EXAMPLE
    ./populate-project.ps1 -Action complete -FeatureBranch "001-new-feature"
    Moves the feature to Completed Features and marks as Archived.

.NOTES
Exit Codes:
    0 - Success (project.md updated)
    1 - Error (project.md not found or update failed)
#>

param(
    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("add", "complete")]
    [string]$Action,

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$FeatureBranch,

    [string]$FeatureName,

    [string]$ProjectPath,

    [switch]$Json,

    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Host @"
Usage: populate-project.ps1 -Action <add|complete> -FeatureBranch <branch> [-FeatureName <name>] [-Json]

Updates project.md with feature information.

ACTIONS:
  add       Add new feature to Active Features table
  complete  Move feature to Completed Features table (marks as Archived)

PARAMETERS:
  -Action <add|complete>     Required. Operation to perform
  -FeatureBranch <branch>    Required. Feature branch name
  -FeatureName <name>        Optional. Display name (derived from branch if omitted)
  -ProjectPath <path>        Optional. Path to project.md (default: specs/project.md)
  -Json                      Output results in JSON format

EXAMPLES:
  ./populate-project.ps1 -Action add -FeatureBranch "001-feature"
  ./populate-project.ps1 -Action complete -FeatureBranch "001-feature" -Json

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

$Script:AuditRun = New-WorkflowScriptRunMetadata -ScriptName 'populate-project.ps1'
$Script:AuditContext = New-WorkflowAuditContext -ScriptName 'populate-project.ps1' -Action "populate-project-$Action" `
    -ChangeId $FeatureBranch -RunId $Script:AuditRun.run_id
$Script:AuditStopwatch = [System.Diagnostics.Stopwatch]::StartNew()


# Set default project path
if (-not $ProjectPath) {
    $EnvData = Get-FeaturePathsEnv
    $RepoRoot = $EnvData.REPO_ROOT
    if (-not $RepoRoot) {
        $RepoRoot = Get-WorkspaceRoot
    }
    if ($RepoRoot) {
        $ProjectPath = Join-Path $RepoRoot "specs" "project.md"
    } else {
        $ProjectPath = "specs/project.md"
    }
}

# Derive feature name from branch if not provided
if (-not $FeatureName) {
    # Convert "001-openspec-integration" to "Openspec Integration"
    $FeatureName = $FeatureBranch -replace '^\d+-', '' -replace '-', ' '
    $FeatureName = (Get-Culture).TextInfo.ToTitleCase($FeatureName)
}

# Extract feature ID from branch
$FeatureId = if ($FeatureBranch -match '^(\d+)-') { $Matches[1] } else { "???" }

$Today = Get-StandardDate
$Timestamp = Get-StandardTimestamp

function Backup-ProjectFile {
    <#
    .SYNOPSIS
        Creates a rollback backup for project.md.
    .PARAMETER Path
        Path to the project file.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (Test-Path $Path -and -not $Tracker.Backups.ContainsKey($Path)) {
        $BackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("populate-project-backup-{0}.bak" -f ([Guid]::NewGuid().ToString()))
        Copy-Item -LiteralPath $Path -Destination $BackupPath -Force -ErrorAction Stop
        Add-TrackedBackup -Tracker $Tracker -Destination $Path -Backup $BackupPath
    }
}

function Write-ProjectContent {
    <#
    .SYNOPSIS
        Writes project.md content and tracks newly created files.
    .PARAMETER Path
        Target file path.
    .PARAMETER Content
        File content to write.
    .PARAMETER TrackNewFile
        Indicates whether to track new file creation.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Content,

        [switch]$TrackNewFile
    )

    Write-CacheFileAtomic -Path $Path -Content $Content
    if ($TrackNewFile) {
        Add-TrackedFile -Tracker $Tracker -Path $Path
    }
}

# =============================================================================
# CREATE PROJECT.MD IF MISSING (T059)
# =============================================================================

function Initialize-ProjectFile {
    <#
    .SYNOPSIS
        Creates a new project.md file if missing.
    .PARAMETER Path
        Target file path.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $Template = @"
---
project_name: "SpecKit Project"
last_updated: "$Timestamp"
total_features: 0
active_features: 0
completed_features: 0
---

# Project Registry

This file tracks all features in the project.

## Active Features

| ID | Name | Branch | Created | Status | Last Updated |
|----|------|--------|---------|--------|--------------|

## Completed Features

| ID | Name | Branch | Created | Completed | Status |
|----|------|--------|---------|-----------|--------|
"@

    # Ensure parent directory exists
    $ParentDir = Split-Path $Path -Parent
    if (-not (Test-Path $ParentDir)) {
        New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
        Add-TrackedDirectory -Tracker $Tracker -Path $ParentDir
    }

    Write-ProjectContent -Path $Path -Content $Template -TrackNewFile
    Write-Verbose "Created project.md at: $Path"
}

# =============================================================================
# ADD FEATURE (T056)
# =============================================================================

function Add-FeatureToProject {
    <#
    .SYNOPSIS
        Adds a feature to the Active Features table.
    .PARAMETER Path
        Project file path.
    .PARAMETER Id
        Feature ID value.
    .PARAMETER Name
        Feature display name.
    .PARAMETER Branch
        Feature branch name.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Branch
    )

    $Content = Get-FileContentCached -Path $Path -Raw

    # Check if feature already exists
    if ($Content -match [regex]::Escape($Branch)) {
        return @{
            success = $False
            message = "Feature '$Branch' already exists in project.md"
        }
    }

    # Create new row
    $NewRow = "| $Id | $Name | $Branch | $Today | In Progress | $Today |"

    # Find Active Features table and insert after header
    # Pattern: table header row followed by separator row
    $TablePattern = '(\| ID \| Name \| Branch \| Created \| Status \| Last Updated \|\r?\n\|[-|]+\|)'

    if ($Content -match $TablePattern) {
        $Content = $Content -replace $TablePattern, "`$1`n$NewRow"
    } else {
        # Table structure missing - exit with error
        return @{
            success = $False
            message = "Active Features table not found in project.md"
        }
    }

    # Update frontmatter counts
    $Content = Update-FrontmatterCounts -Content $Content

    Backup-ProjectFile -Path $Path
    Write-ProjectContent -Path $Path -Content $Content

    return @{
        success = $True
        message = "Feature '$Name' ($Branch) added to Active Features"
    }
}

# =============================================================================
# COMPLETE FEATURE (T057)
# =============================================================================

function Complete-FeatureInProject {
    <#
    .SYNOPSIS
        Moves a feature from Active to Completed in project.md.
    .PARAMETER Path
        Project file path.
    .PARAMETER Id
        Feature ID value.
    .PARAMETER Name
        Feature display name.
    .PARAMETER Branch
        Feature branch name.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Branch
    )

    $Content = Get-FileContentCached -Path $Path -Raw

    # Find feature in Active Features
    $ActivePattern = "\| ([^|]+) \| ([^|]+) \| $([regex]::Escape($Branch)) \| ([^|]+) \| [^|]+ \| [^|]+ \|"

    if ($Content -notmatch $ActivePattern) {
        return @{
            success = $False
            message = "Feature '$Branch' not found in Active Features"
        }
    }

    $FeatureId = $Matches[1].Trim()
    $FeatureName = $Matches[2].Trim()
    $CreatedDate = $Matches[3]

    # Create completed row (includes Created date)
    $CompletedRow = "| $FeatureId | $FeatureName | $Branch | $CreatedDate | $Today | Archived |"

    # Remove from Active Features (escape ID for regex)
    $Content = $Content -replace "(?m)^\| $([regex]::Escape($FeatureId.Trim())) \| [^|]+ \| $([regex]::Escape($Branch)) \| [^\r\n]+\r?\n", ""

    # Add to Completed Features table
    $CompletedTablePattern = '(\| ID \| Name \| Branch \| Created \| Completed \| Status \|\r?\n\|[-|]+\|)'

    if ($Content -match $CompletedTablePattern) {
        $Content = $Content -replace $CompletedTablePattern, "`$1`n$CompletedRow"
    } else {
        # Fallback: append to Completed Features section
        $Content = $Content -replace '(## Completed Features\s*\r?\n)', "`$1`n$CompletedRow`n"
    }

    # Update frontmatter counts
    $Content = Update-FrontmatterCounts -Content $Content

    Backup-ProjectFile -Path $Path
    Write-ProjectContent -Path $Path -Content $Content

    return @{
        success = $True
        message = "Feature '$FeatureName' ($Branch) moved to Completed Features"
    }
}

# =============================================================================
# UPDATE FRONTMATTER (T058)
# =============================================================================

function Update-FrontmatterCounts {
    <#
    .SYNOPSIS
        Updates project frontmatter counts and timestamps.
    .PARAMETER Content
        Project file content.
    .PARAMETER ActiveCount
        Updated active feature count.
    .PARAMETER CompletedCount
        Updated completed feature count.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Content
    )

    # Count active features (In Progress rows)
    $ActiveCount = ([regex]::Matches($Content, '\| In Progress \|')).Count

    # Count completed features (Archived rows)
    $CompletedCount = ([regex]::Matches($Content, '\| Archived \|')).Count

    $TotalCount = $ActiveCount + $CompletedCount

    # Update frontmatter
    $Content = $Content -replace 'last_updated: "[^"]+"', "last_updated: `"$Timestamp`""
    $Content = $Content -replace 'total_features: \d+', "total_features: $TotalCount"
    $Content = $Content -replace 'active_features: \d+', "active_features: $ActiveCount"
    $Content = $Content -replace 'completed_features: \d+', "completed_features: $CompletedCount"

    return $Content
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

$OpResult = $Null
$Errors = @()

try {
    # Create project.md if it doesn't exist
    if (-not (Test-Path $ProjectPath)) {
        Initialize-ProjectFile -Path $ProjectPath
        Write-Verbose "Initialized new project.md"
    }

    # Execute action
    $OpResult = switch ($Action) {
        "add" {
            Add-FeatureToProject -Path $ProjectPath -Id $FeatureId -Name $FeatureName -Branch $FeatureBranch
        }
        "complete" {
            Complete-FeatureInProject -Path $ProjectPath -Branch $FeatureBranch
        }
    }

    if (-not $OpResult.success) {
        $Errors += $OpResult.message
    }
}
catch {
    $Errors += $_.ToString()
    Invoke-TrackedRollback -Tracker $Tracker
}

$ResultData = @{
    action = $Action
    feature_branch = $FeatureBranch
    feature_name = $FeatureName
    project_path = $ProjectPath
    message = if ($OpResult) { $OpResult.message } else { $Null }
    success = if ($OpResult) { [bool]$OpResult.success } else { $False }
}

$Status = if ($Errors.Count -eq 0) { "success" } else { "operation_error" }

if ($Json) {
    Write-JsonResult -Result (New-JsonResult -Status $Status -ScriptName "populate-project.ps1" -Data $ResultData -Errors $Errors)
} else {
    Write-Host ""
    Write-Host "=== Project Registry Update ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Action:  $Action"
    Write-Host "Feature: $FeatureBranch"
    Write-Host "Status:  $Status" -ForegroundColor $(if ($Errors.Count -eq 0) { "Green" } else { "Red" })
    Write-Host "Message: $($ResultData.message)"
    Write-Host ""
    Write-Host "Project file: $ProjectPath"
    Write-Host ""
}

if ($Errors.Count -eq 0) {
    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'success' -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null
    exit $ExitCodes.Success
}

Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'failure' -ErrorRecord ($Errors -join '; ') `
    -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null
exit $ExitCodes.Operation

