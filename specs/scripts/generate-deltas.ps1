#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generate delta entries for a feature showing all file changes.

.DESCRIPTION
    Analyzes Git history to detect ADDED, MODIFIED, REMOVED, and RENAMED files
    for a feature. Outputs delta entries in Markdown or JSON format.

.PARAMETER FeatureDir
    Path to the feature directory to analyze.

.PARAMETER BaseRef
    Git ref to compare against (branch, tag, or commit). Default: "main"

.PARAMETER Strict
    Include diff content and summary for MODIFIED files.

.PARAMETER Json
    Output results in JSON format.

.PARAMETER OutputFile
    Optional. Write output to this file instead of stdout.

.OUTPUTS
    Delta entries in Markdown or JSON format.

.EXAMPLE
    ./generate-deltas.ps1 -FeatureDir "specs/001-feature"
    Lists all deltas for the feature in Markdown format.

.EXAMPLE
    ./generate-deltas.ps1 -FeatureDir "specs/001-feature" -Strict -Json
    Lists deltas with diff content in JSON format.

.NOTES
Exit Codes:
    0 - Success (deltas generated)
    1 - Error (invalid feature directory or git operation failed)
#>

param(
    [Parameter(Mandatory=$True, Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$FeatureDir,

    [string]$BaseRef,

    [switch]$Strict,

    [switch]$Json,

    [string]$OutputFile
)

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

$Script:AuditRun = New-WorkflowScriptRunMetadata -ScriptName 'generate-deltas.ps1'
$Script:AuditContext = New-WorkflowAuditContext -ScriptName 'generate-deltas.ps1' -Action 'generate-deltas' `
    -ChangeId (Get-CurrentChangeId) -RunId $Script:AuditRun.run_id
$Script:AuditStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Exit-WithAuditError {
    <#
    .SYNOPSIS
        Writes an error message, logs an audit entry, and exits.
    .PARAMETER Message
        Error message to emit.
    .PARAMETER ExitCode
        Exit code to return.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [int]$ExitCode
    )

    Write-Error $Message
    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'failure' -ErrorRecord $Message `
        -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null
    exit $ExitCode
}

if (-not $BaseRef) {
    $BaseRef = Get-DefaultGitBaseRef
}

if (-not (Test-GitRef -BaseRef $BaseRef)) {
    Exit-WithAuditError -Message "Invalid BaseRef: $BaseRef" -ExitCode $ExitCodes.Validation
}

# Validate feature directory
if (-not (Test-Path $FeatureDir)) {
    Exit-WithAuditError -Message "Feature directory not found: $FeatureDir" -ExitCode $ExitCodes.Validation
}

$Script:AuditContext.change_id = Split-Path -Path $FeatureDir -Leaf

# Check Git availability
$HasGit = Test-HasGit
if (-not $HasGit) {
    Write-Warning "[speckit] Git not available - delta detection will use filesystem snapshots"
}

# Get deltas
$Deltas = Get-FileDeltas -BaseRef $BaseRef -FeatureDir $FeatureDir -IncludeDiffContent:$Strict

# Filter by allowed extensions (Task K.12)
$AllowedExtensions = Get-AllowedExtensions
$Deltas = $Deltas | Where-Object {
    $ItemPath = if ($_.Operation -eq "RENAMED") { $_.TargetPath } else { $_.Path }
    $Matched = $False
    foreach ($Ext in $AllowedExtensions) {
        if ($ItemPath.EndsWith($Ext, [System.StringComparison]::OrdinalIgnoreCase)) {
            $Matched = $True
            break
        }
    }
    $Matched
}

# Build output
if ($Json) {
    $FeatureName = Split-Path $FeatureDir -Leaf
    $Output = @{
        feature = $FeatureName
        base_ref = $BaseRef
        summary = @{
            added = ($Deltas | Where-Object { $_.Operation -eq "ADDED" } | Measure-Object).Count
            modified = ($Deltas | Where-Object { $_.Operation -eq "MODIFIED" } | Measure-Object).Count
            removed = ($Deltas | Where-Object { $_.Operation -eq "REMOVED" } | Measure-Object).Count
            renamed = ($Deltas | Where-Object { $_.Operation -eq "RENAMED" } | Measure-Object).Count
            trivial = ($Deltas | Where-Object { $_.IsTrivial } | Measure-Object).Count
            total = $Deltas.Count
        }
        deltas = $Deltas | ForEach-Object {
            @{
                operation = $_.Operation
                path = $_.Path
                target_path = $_.TargetPath
                diff_summary = $_.DiffSummary
                diff_content = $_.DiffContent
                is_trivial = $_.IsTrivial
            }
        }
    }

    $Result = New-JsonResult -Status "success" -ScriptName "generate-deltas.ps1" -Data $Output

    if ($OutputFile) {
        $JsonPayload = $Result | ConvertTo-Json -Depth 10
        $Schema = Get-JsonSchema
        $SchemaValid = $True
        try {
            $SchemaValid = Test-Json -Json $JsonPayload -Schema $Schema
        } catch {
            $SchemaValid = $False
        }
        if (-not $SchemaValid) {
            Write-Warning "[speckit] JSON output failed schema validation"
        }
        $JsonPayload | Out-File -FilePath $OutputFile -Encoding utf8
        Write-Host "Delta output written to: $OutputFile"
    } else {
        Write-JsonResult -Result $Result
    }
} else {
    # Markdown format
    $Lines = @()
    $Lines += "## Delta Summary"
    $Lines += ""
    $Lines += "**Feature**: $(Split-Path $FeatureDir -Leaf)"
    $Lines += "**Base Ref**: $BaseRef"
    $Lines += "**Generated**: $(Get-StandardTimestamp)"
    $Lines += ""

    $AddedCount = ($Deltas | Where-Object { $_.Operation -eq "ADDED" } | Measure-Object).Count
    $ModifiedCount = ($Deltas | Where-Object { $_.Operation -eq "MODIFIED" } | Measure-Object).Count
    $RemovedCount = ($Deltas | Where-Object { $_.Operation -eq "REMOVED" } | Measure-Object).Count
    $RenamedCount = ($Deltas | Where-Object { $_.Operation -eq "RENAMED" } | Measure-Object).Count

    $Lines += "| Operation | Count |"
    $Lines += "|-----------|-------|"
    $Lines += "| ADDED | $AddedCount |"
    $Lines += "| MODIFIED | $ModifiedCount |"
    $Lines += "| REMOVED | $RemovedCount |"
    $Lines += "| RENAMED | $RenamedCount |"
    $Lines += "| **Total** | $(if ($Deltas) { $Deltas.Count } else { 0 }) |"
    $Lines += ""
    $Lines += "### File Changes"
    $Lines += ""

    # Format deltas as markdown
    if ($Deltas -and $Deltas.Count -gt 0) {
        $DeltaLines = Format-DeltaMarkdown -Deltas $Deltas
        $Lines += $DeltaLines
    } else {
        $Lines += "_No file changes detected._"
    }

    if (-not $HasGit) {
        $Lines += ""
        $Lines += "> **Note**: Git not available. Filesystem snapshot used for deltas."
    }

    $Output = $Lines -join "`n"

    if ($OutputFile) {
        $Output | Out-File -FilePath $OutputFile -Encoding utf8
        Write-Host "Delta output written to: $OutputFile"
    } else {
        Write-Output $Output
    }
}

Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'success' -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null

exit $ExitCodes.Success

