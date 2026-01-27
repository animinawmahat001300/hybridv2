#!/usr/bin/env pwsh

<#
.SYNOPSIS
Archives a completed SpecKit feature by merging delta specs and moving files to archive.

.DESCRIPTION
The archive-feature.ps1 script safely archives a completed feature change. It performs:
1. Validates the feature directory exists
2. Runs validate.ps1 -Strict before archiving (unless -SkipValidation)
3. Checks all tasks in tasks.md are complete (marked [X])
4. Merges delta specs if specs/ subfolder exists (unless -SkipMerge)
5. Moves to specs/changes/archive/YYYY-MM-DD-{feature-id}/

Safety features include automatic backup creation, integrity validation,
rollback capability on failure, and -WhatIf support for dry-run testing.

.PARAMETER FeatureId
Required. The feature ID (directory name) to archive.
Example: "001-user-auth" or "add-login-system"

.PARAMETER SkipValidation
Optional. Skip running validate.ps1 -Strict before archiving.

.PARAMETER SkipMerge
Optional. Skip merging delta specifications into truth files.
Use when you want to archive without spec updates.

.PARAMETER Force
Optional. Skip confirmation prompts and proceed automatically.

.PARAMETER WhatIf
Optional. Perform a dry-run showing what would happen without making changes.
Use this to preview archive operations safely.

.PARAMETER Json
Optional. Output results in JSON format for CI/CD integration.

.PARAMETER Help
Optional. Display this help message.

.EXAMPLE
.\archive-feature.ps1 -FeatureId "001-user-auth"
Archives the feature "001-user-auth" with validation and confirmation prompts.

.EXAMPLE
.\archive-feature.ps1 -FeatureId "001-user-auth" -WhatIf
Shows what would happen during archive without making changes.

.EXAMPLE
.\archive-feature.ps1 -FeatureId "001-user-auth" -Force -SkipValidation
Archives without confirmation and skips pre-archive validation.

.EXAMPLE
.\archive-feature.ps1 -FeatureId "001-user-auth" -Json
Archives and outputs results in JSON format.

.NOTES
File: archive-feature.ps1
Author: SpecKit Consolidated

Exit Codes:
    0 - Success (feature archived)
    1 - Validation failure
    2 - Archive operation failed
Requires: PowerShell 7+
Safety: Creates backups before destructive operations; use -WhatIf to preview
#>

param(
    [Parameter(Mandatory = $false, Position = 0)]
    [Alias("Slug")]
    [string]$FeatureId,
    [switch]$SkipValidation,
    [switch]$SkipMerge,
    [Alias("Yes")]
    [switch]$Force,
    [switch]$WhatIf,
    [switch]$Json,
    [switch]$Help
)

# Show help if requested
if ($Help) {
    @"

SYNOPSIS
    Archives a completed SpecKit feature by merging delta specs and moving to archive.

PARAMETERS
    -FeatureId <string>
        Required. The feature ID to archive (e.g., "001-user-auth")

    -SkipValidation
        Skip running validate.ps1 -Strict before archiving.

    -SkipMerge
        Skip merging delta specifications into truth files.

    -Force
        Skip confirmation prompts and proceed automatically.

    -WhatIf
        Perform a dry-run showing what would happen without making changes.

    -Json
        Output results in JSON format for CI/CD integration.

    -Help
        Display this help message.

EXAMPLES
    .\archive-feature.ps1 -FeatureId "001-user-auth"
        Archives with full validation and confirmation prompts.

    .\archive-feature.ps1 -FeatureId "001-user-auth" -WhatIf
        Shows what would happen without making changes.

    .\archive-feature.ps1 -FeatureId "001-user-auth" -Force -SkipValidation
        Archives without confirmation and skips validation.

    .\archive-feature.ps1 -FeatureId "001-user-auth" -Json
        Archives and outputs structured JSON results.

"@
    exit 0
}

# Validate FeatureId is provided if not showing help
if (-not $FeatureId) {
    Write-Error "The -FeatureId parameter is required. Use -Help for usage information."
    exit $ExitCodes.Validation
}

$ErrorActionPreference = "Stop"
$ExitCodes = @{ Success = 0; Validation = 1; Operation = 2 }

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { $ScriptDir = Get-Location }

# Source common functions
$CommonPath = Join-Path $ScriptDir "common.ps1"
if (Test-Path $CommonPath) {
    try {
        . $CommonPath
    } catch {
        $LoadError = $_.Exception
        Write-Error "Failed to load common.ps1 from '$CommonPath'. Ensure the SpecKit scripts directory is intact. Error: $($LoadError.Message)"
        exit $ExitCodes.Operation
    }
} else {
    Write-Error "Could not find common.ps1 in $ScriptDir"
    exit $ExitCodes.Operation
}

$ExitCodes = Get-ExitCodes
Set-StrictErrorActionPreference | Out-Null

# Use absolute path resolution from common.ps1
$RepoRoot = Get-RepositoryRoot

# Fallback to current directory if specs/ folder exists (hybrid subfolder case)
if (-not $RepoRoot) {
    if (Test-Path (Join-Path (Get-Location).Path "specs")) {
        $RepoRoot = (Get-Location).Path
    }
}

if (-not $RepoRoot) {
    Write-Error "Could not detect SpecKit workspace root. Ensure you are running within a valid SpecKit repository."
    exit $ExitCodes.Operation
}

# Ensure RepoRoot is an absolute path and change directory for consistency
$RepoRoot = (Resolve-Path $RepoRoot).Path
Push-Location $RepoRoot -ErrorAction SilentlyContinue

# Use common helper to find the feature directory (checks specs/id and specs/changes/id)
$ChangesDir = Get-ChangeDir -RepoRoot $RepoRoot -ChangeId $FeatureId
if (Test-Path $ChangesDir) {
    $ChangesDir = (Resolve-Path $ChangesDir).Path
}

# Standard archive location from common environment
$envData = Get-FeaturePathsEnv
$ArchiveBase = $envData.ARCHIVE_DIR

# If ARCHIVE_DIR not set in env, fall back to default
if (-not $ArchiveBase) {
    $ArchiveBase = Join-Path $RepoRoot "specs" "changes" "archive"
}
# Ensure ArchiveBase is absolute
if (-not [System.IO.Path]::IsPathRooted($ArchiveBase)) {
    $ArchiveBase = Join-Path $RepoRoot $ArchiveBase
}
if (Test-Path $ArchiveBase) {
    $ArchiveBase = (Resolve-Path $ArchiveBase).Path
}

# Initialize result object for structured output
$result = @{
    success = $false
    feature_id = $FeatureId
    source_path = $ChangesDir
    archive_path = ""
    repo_root = $RepoRoot
    validation = @{ passed = $false; errors = @(); warnings = @() }
    tasks_check = @{ passed = $false; total = 0; complete = 0; incomplete = @() }
    merged_specs = @()
    snapshot_path = $Null
    snapshot_captured = $false
    snapshot_git_available = $false
    snapshot_dirty = $false
    actions = @()
}

$Script:AuditRun = New-WorkflowScriptRunMetadata -ScriptName 'archive-feature.ps1'
$Script:AuditContext = @{
    script_name = 'archive-feature.ps1'
    action = 'archive'
    change_id = $FeatureId
    run_id = $Script:AuditRun.run_id
}
$Script:AuditStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Write-ArchiveAuditEntry {
    <#
    .SYNOPSIS
        Writes a workflow audit entry for archive outcomes.
    .PARAMETER Outcome
        Outcome for the archive action.
    .PARAMETER ErrorRecord
        Optional error record or message.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateSet('success', 'failure')]
        [string]$Outcome,

        $ErrorRecord
    )

    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome $Outcome -ErrorRecord $ErrorRecord `
        -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null
}

function Write-ArchiveJson {
    <#
    .SYNOPSIS
        Writes standardized JSON output for archive-feature.ps1.
    .PARAMETER Status
        Result status string.
    .PARAMETER Errors
        Error list to include.
    .PARAMETER Warnings
        Warning list to include.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Status,

        [string[]]$Errors = @(),

        [string[]]$Warnings = @()
    )

    Write-JsonResult -Result (New-JsonResult -Status $Status -ScriptName "archive-feature.ps1" -Data $result -Errors $Errors -Warnings $Warnings)
}

if (-not (Test-Path $ChangesDir)) {
    $errorMsg = "Feature directory for '$FeatureId' not found: $ChangesDir"
    if ($Json) {
        $result.validation.errors += $errorMsg
        Write-ArchiveJson -Status "validation_error" -Errors $result.validation.errors
    } else {
        Write-Error $errorMsg
    }
    Write-ArchiveAuditEntry -Outcome 'failure' -ErrorRecord $errorMsg
    Pop-Location -ErrorAction SilentlyContinue
    exit $ExitCodes.Validation
}

# NEW: Validation function
function Test-ArchiveIntegrity {
    <#
    .SYNOPSIS
        Validates that archived files match the source contents.
    .PARAMETER SourcePath
        Source feature directory.
    .PARAMETER DestinationPath
        Archive destination directory.
    .OUTPUTS
        Boolean indicating integrity validation status.
    #>
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    $sourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File
    $destFiles = Get-ChildItem -Path $DestinationPath -Recurse -File

    if ($sourceFiles.Count -ne $destFiles.Count) {
        return $false
    }

    foreach ($srcFile in $sourceFiles) {
        $relativePath = $srcFile.FullName.Substring($SourcePath.Length)
        $destFile = Join-Path $DestinationPath $relativePath
        if (-not (Test-Path $destFile)) {
            return $false
        }
        if ($srcFile.Length -ne (Get-Item $destFile).Length) {
            return $false
        }
    }

    return $true
}

# NEW: Rollback function
function Restore-FromBackup {
    <#
    .SYNOPSIS
        Restores archived files from backup on failure.
    .PARAMETER BackupPath
        Backup archive path.
    .PARAMETER OriginalPath
        Original feature path.
    #>
    param(
        [string]$BackupPath,
        [string]$OriginalPath
    )

    try {
        Write-Warning "Rolling back changes..."
        if (Test-Path $OriginalPath) {
            Remove-Item -Path $OriginalPath -Recurse -Force -ErrorAction Stop
        }
        if (Test-Path $BackupPath) {
            Move-Item -Path $BackupPath -Destination $OriginalPath -Force -ErrorAction Stop
            Write-Host "Rollback successful. Original state restored." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "CRITICAL: Rollback failed! Backup at: $BackupPath. Error: $_"
    }
}

# NEW: Task completion checker
function Test-TasksComplete {
    <#
    .SYNOPSIS
        Validates that all tasks in tasks.md are completed.
    .PARAMETER FeatureDir
        Feature directory path.
    .OUTPUTS
        Hashtable with completion stats.
    #>
    param(
        [string]$FeatureDir
    )

    $tasksFile = Join-Path $FeatureDir "tasks.md"
    $checkResult = @{
        passed = $true
        total = 0
        complete = 0
        incomplete = @()
    }

    if (-not (Test-Path $tasksFile)) {
        # No tasks.md - assume tasks are in plan.md or not required
        $planFile = Join-Path $FeatureDir "plan.md"
        if (Test-Path $planFile) {
            $tasksFile = $planFile
        } else {
            $checkResult.passed = $true
            return $checkResult
        }
    }

    $content = Get-Content $tasksFile -ErrorAction SilentlyContinue
    if (-not $content) {
        return $checkResult
    }

    foreach ($line in $content) {
        # Match task lines: - [ ] T001 or - [X] T001 or - [x] T001
        if ($line -match '^\s*-\s*\[([ Xx])\]\s*(T\d+|[A-Z]{1,3}\d+)(.*)$') {
            $checkResult.total++
            $status = $Matches[1]
            $taskId = $Matches[2]
            $description = $Matches[3].Trim()

            if ($status -match '[Xx]') {
                $checkResult.complete++
            } else {
                $checkResult.incomplete += @{
                    id = $taskId
                    description = $description.Substring(0, [Math]::Min(50, $description.Length))
                }
            }
        }
    }

    if ($checkResult.incomplete.Count -gt 0) {
        $checkResult.passed = $false
    }

    return $checkResult
}

# =============================================================================
# STEP 1: PRE-ARCHIVE VALIDATION (unless -SkipValidation)
# =============================================================================

if (-not $SkipValidation) {
    if ($WhatIf) {
        Write-Host "[WhatIf] Would run validate.ps1 -Strict for feature: $FeatureId" -ForegroundColor Cyan
        $result.actions += "Validate: validate.ps1 -Target '$FeatureId' -Strict"
    } else {
        Write-Host "Running pre-archive validation..." -ForegroundColor Cyan
        $validateScript = Join-Path $ScriptDir "validate.ps1"

        if (Test-Path $validateScript) {
            try {
                $validateOutput = & $validateScript -Target $FeatureId -Strict -Json 2>&1
                $validateResult = $validateOutput | ConvertFrom-Json -ErrorAction SilentlyContinue

                if ($validateResult) {
                    $passed = $False
                    if ($validateResult.PSObject.Properties.Name -contains 'passed') {
                        $passed = [bool]$validateResult.passed
                    } elseif ($validateResult.status -eq 'success') {
                        $passed = $True
                    }

                    $result.validation.passed = $passed
                    $result.validation.errors = @($validateResult.errors | Where-Object { $_ })
                    $result.validation.warnings = @($validateResult.warnings | Where-Object { $_ })

                    if (-not $passed) {
                        $errorCount = $result.validation.errors.Count
                        $errorMsg = "Pre-archive validation failed with $errorCount error(s)"
                        if ($Json) {
                            $result.validation.errors = @($errorMsg) + $result.validation.errors
                            Write-ArchiveJson -Status "validation_error" -Errors $result.validation.errors
                        } else {
                            Write-Error $errorMsg
                            foreach ($err in $validateResult.errors) {
                                Write-Host "  - $err" -ForegroundColor Red
                            }
                        }
                        Write-ArchiveAuditEntry -Outcome 'failure' -ErrorRecord $errorMsg
                        Pop-Location -ErrorAction SilentlyContinue
                        exit $ExitCodes.Validation
                    }
                } else {
                    # Validation script ran but no JSON output - check exit code
                    if ($LASTEXITCODE -ne 0) {
                        $errorMsg = "Pre-archive validation failed"
                        if ($Json) {
                            $result.validation.errors += $errorMsg
                            Write-ArchiveJson -Status "validation_error" -Errors $result.validation.errors
                        } else {
                            Write-Error $errorMsg
                        }
                        Write-ArchiveAuditEntry -Outcome 'failure' -ErrorRecord $errorMsg
                        Pop-Location -ErrorAction SilentlyContinue
                        exit $ExitCodes.Validation
                    }
                    $result.validation.passed = $true
                }

                Write-Host "Validation passed." -ForegroundColor Green
                $result.actions += "Validated: validate.ps1 -Target '$FeatureId' -Strict (passed)"
            }
            catch {
                Write-Warning "Could not run validation: $_"
                $result.validation.warnings += "Validation script error: $_"
            }
        } else {
            Write-Warning "validate.ps1 not found - skipping pre-archive validation"
            $result.validation.warnings += "validate.ps1 not found"
        }
    }
} else {
    $result.validation.passed = $true
    $result.validation.warnings += "Validation skipped (-SkipValidation)"
    if (-not $Json -and -not $WhatIf) {
        Write-Host "Skipping pre-archive validation (-SkipValidation)" -ForegroundColor Yellow
    }
}

# =============================================================================
# STEP 2: CHECK ALL TASKS COMPLETE
# =============================================================================

if ($WhatIf) {
    Write-Host "[WhatIf] Would check tasks.md for incomplete tasks" -ForegroundColor Cyan
    $result.actions += "Check: tasks.md for incomplete tasks"
} else {
    Write-Host "Checking task completion..." -ForegroundColor Cyan
    $tasksCheck = Test-TasksComplete -FeatureDir $ChangesDir
    $result.tasks_check = $tasksCheck

    if (-not $tasksCheck.passed -and $tasksCheck.total -gt 0) {
        $incompleteCount = $tasksCheck.incomplete.Count
        $errorMsg = "Cannot archive: $incompleteCount of $($tasksCheck.total) tasks incomplete"

        if ($Force) {
            Write-Warning "$errorMsg (proceeding due to -Force)"
            $result.tasks_check.warnings = @("Forced archive with incomplete tasks")
        } else {
            if ($Json) {
                $result.validation.errors += $errorMsg
                foreach ($task in $tasksCheck.incomplete) {
                    $result.validation.errors += "Incomplete: $($task.id) - $($task.description)"
                }
                Write-ArchiveJson -Status "validation_error" -Errors $result.validation.errors
            } else {
                Write-Error $errorMsg
                foreach ($task in $tasksCheck.incomplete) {
                    Write-Host "  - [ ] $($task.id) $($task.description)..." -ForegroundColor Red
                }
            }
            Write-ArchiveAuditEntry -Outcome 'failure' -ErrorRecord $errorMsg
            Pop-Location -ErrorAction SilentlyContinue
            exit $ExitCodes.Validation
        }
    } elseif ($tasksCheck.total -eq 0) {
        Write-Host "No tasks found - proceeding with archive." -ForegroundColor Yellow
    } else {
        Write-Host "All $($tasksCheck.complete)/$($tasksCheck.total) tasks complete." -ForegroundColor Green
    }
    $result.actions += "Checked: $($tasksCheck.complete)/$($tasksCheck.total) tasks complete"
}

# =============================================================================
# STEP 3: MERGE DELTA SPECS (unless -SkipMerge)
# =============================================================================

if (-not $SkipMerge) {
    if ($WhatIf) {
        Write-Host "[WhatIf] Would merge delta specs for feature: $FeatureId" -ForegroundColor Cyan
    }

    $deltaSpecsDir = Join-Path $ChangesDir "specs"
    if (Test-Path $deltaSpecsDir) {
        Write-Host "Merging deltas via merge-deltas.ps1..." -ForegroundColor Cyan
        $mergeScript = Join-Path $ScriptDir "merge-deltas.ps1"
        if (Test-Path $mergeScript) {
            try {
                $mergeParams = @{ FeatureId = $FeatureId; Json = $true }
                if ($WhatIf) { $mergeParams.WhatIf = $true }

                $mergeOutput = & $mergeScript @mergeParams 2>&1
                $mergeOutputString = $mergeOutput | Out-String
                $mergeResult = $mergeOutputString | ConvertFrom-Json -ErrorAction Stop

                if ($LASTEXITCODE -ne 0) {
                    throw "merge-deltas.ps1 returned exit code $LASTEXITCODE"
                }

                # merge-deltas.ps1 returns { featureId, timestamp, processed, errors, status? }
                $result.merged_specs = $mergeResult.processed
                if ($mergeResult.processed) {
                    foreach ($MergeEntry in $mergeResult.processed) {
                        $result.actions += "Merged: $($MergeEntry.capability) ($($MergeEntry.action))"
                    }
                }

                if ($mergeResult.status -eq "no_deltas") {
                    $result.actions += "Skip: No delta specs found"
                }

                if ($mergeResult.errors -and $mergeResult.errors.Count -gt 0) {
                    Write-Warning "Some delta merges had errors."
                    $result.validation.warnings += $mergeResult.errors
                }
            } catch {
                Write-Warning "Failed to execute merge-deltas.ps1: $_"
                $result.validation.errors += "Merge script error: $_"
                throw
            }
        } else {
            Write-Warning "merge-deltas.ps1 not found - skipping merge."
            $result.validation.warnings += "merge-deltas.ps1 not found"
        }
    } else {
        if (-not $WhatIf -and -not $Json) {
            Write-Host "No delta specs directory found - skipping merge." -ForegroundColor Yellow
        }
        $result.actions += "Skip: No specs/ subfolder in feature"
    }
} else {
    $result.actions += "Skip: Delta merge skipped (-SkipMerge)"
    if (-not $Json -and -not $WhatIf) {
        Write-Host "Skipping delta spec merge (-SkipMerge)" -ForegroundColor Yellow
    }
}

# =============================================================================
# STEP 3.5: CAPTURE WORKSPACE SNAPSHOT
# =============================================================================

$Script:WorkspaceSnapshot = $Null
if (-not $WhatIf) {
    try {
        $Script:WorkspaceSnapshot = New-WorkspaceSnapshot -RepoRoot $RepoRoot -ChangeId $FeatureId -FeatureDir $ChangesDir
        $result.snapshot_git_available = [bool]$Script:WorkspaceSnapshot.git_available
        $hasChanges = ($Script:WorkspaceSnapshot.modified_files.Count -gt 0) -or ($Script:WorkspaceSnapshot.untracked_files.Count -gt 0)
        $gitDirty = $false
        if ($Script:WorkspaceSnapshot.git_status -and $Script:WorkspaceSnapshot.git_status.is_dirty) {
            $gitDirty = [bool]$Script:WorkspaceSnapshot.git_status.is_dirty
        }
        $result.snapshot_dirty = ($hasChanges -or $gitDirty)

        if ($result.snapshot_dirty) {
            $warning = "Workspace has uncommitted changes; snapshot will be captured during archive."
            $result.validation.warnings += $warning
            Write-Warning $warning
        }
    }
    catch {
        $snapshotError = "Workspace snapshot capture failed: $_"
        $result.validation.errors += $snapshotError
        Write-ArchiveAuditEntry -Outcome 'failure' -ErrorRecord $snapshotError
        throw $snapshotError
    }
}

# =============================================================================
# STEP 4: ARCHIVE TO specs/changes/archive/YYYY-MM-DD-{feature-id}/
# =============================================================================

if (-not (Test-Path $ArchiveBase)) {
    if ($WhatIf) {
        Write-Host "[WhatIf] Would create archive directory: $ArchiveBase" -ForegroundColor Cyan
    } else {
        New-Item -ItemType Directory -Path $ArchiveBase -Force -ErrorAction Stop | Out-Null
    }
}

$dateStr = Get-PathSafeTimestamp
$dest = Join-Path $ArchiveBase "$dateStr-$FeatureId"
$result.archive_path = $dest

# Create temporary backup location
$backupPath = "$dest.backup-temp"

if ($WhatIf) {
    Write-Host "[WhatIf] Would archive '$FeatureId' to '$dest'" -ForegroundColor Yellow
    Write-Host "[WhatIf]   Source: $ChangesDir" -ForegroundColor Gray
    Write-Host "[WhatIf]   Destination: $dest" -ForegroundColor Gray
    Write-Host "[WhatIf] Would write workspace-snapshot.json" -ForegroundColor Yellow
    $result.actions += "WouldMove: $ChangesDir -> $dest"
    $result.actions += "WouldSnapshot: workspace-snapshot.json"

    $result.success = $true
    if ($Json) {
        Write-ArchiveJson -Status "success"
    }
    Pop-Location -ErrorAction SilentlyContinue
    exit $ExitCodes.Success
}

if ((-not $Force) -and (-not $Json)) {
    Write-Host "Archiving '$FeatureId' to '$dest'..." -ForegroundColor Green
}

try {
    # Generate delta summary before archive (optional enhancement)
    Write-Verbose "Generating delta summary..."
    if (Get-Command Get-FileDeltas -ErrorAction SilentlyContinue) {
        try {
            $deltas = Get-FileDeltas -BaseRef "main" -FeatureDir $ChangesDir -IncludeDiffContent:$false
            $deltaMarkdown = Format-DeltaMarkdown -Deltas $deltas

            # Write delta summary to archive
            $deltaSummaryFile = Join-Path $ChangesDir "deltas.md"
            $deltaFileContent = @(
                "# Delta Summary: $FeatureId"
                ""
                "**Generated**: $(Get-StandardTimestamp)"
                "**Base Ref**: main"
                ""
                "## File Changes"
                ""
            )
            $deltaFileContent += $deltaMarkdown
            $deltaFileContent += ""
            $deltaFileContent += "---"
            $deltaFileContent += "*Generated by archive-feature.ps1*"

            if ($deltaMarkdown.Count -gt 0) {
                $deltaFileContent -join "`n" | Out-File -FilePath $deltaSummaryFile -Encoding utf8 -ErrorAction SilentlyContinue
                Write-Verbose "Delta summary written to: $deltaSummaryFile"
                $result.actions += "Generated: deltas.md"
            }
        } catch {
            Write-Verbose "Delta summary generation warning: $_"
            # Non-fatal - continue with archive
        }
    }

    # Generate proposal.md for OpenSpec integration (optional)
    Write-Verbose "Generating proposal.md..."
    $proposalScript = Join-Path $ScriptDir "generate-proposal.ps1"
    if (Test-Path $proposalScript) {
        try {
            & $proposalScript -FeatureDir $ChangesDir -ErrorAction SilentlyContinue
            Write-Verbose "Proposal generated: $(Join-Path $ChangesDir 'proposal.md')"
            $result.actions += "Generated: proposal.md"
        } catch {
            Write-Verbose "Proposal generation warning: $_"
            # Non-fatal - continue with archive
        }
    }

    # Create backup AFTER all pre-archive modifications
    Write-Verbose "Creating backup before archive operation..."
    Copy-Item -Path $ChangesDir -Destination $backupPath -Recurse -Force -ErrorAction Stop
    Write-Verbose "Backup created: $backupPath"
    $result.actions += "Backup: Created at $backupPath"

    # Perform archive (atomic move to destination)
    Move-Item -Path $ChangesDir -Destination $dest -Force -ErrorAction Stop
    $result.actions += "Moved: $ChangesDir -> $dest"

    # Validate archive against backup
    if (-not (Test-ArchiveIntegrity -SourcePath $backupPath -DestinationPath $dest)) {
        throw "Archive validation failed. Files may be corrupted."
    }
    Write-Verbose "Archive validated: $dest"
    $result.actions += "Validated: Archive integrity check passed"

    # Write workspace snapshot into archive
    if ($Script:WorkspaceSnapshot) {
        $snapshotPath = Join-Path $dest 'workspace-snapshot.json'
        $snapshotTimer = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Write-WorkspaceSnapshot -Snapshot $Script:WorkspaceSnapshot -Path $snapshotPath
            $snapshotTimer.Stop()
            $result.snapshot_path = $snapshotPath
            $result.snapshot_captured = $true
            $result.actions += "Snapshot: $snapshotPath"

            $snapshotAuditContext = New-WorkflowAuditContext -ScriptName 'archive-feature.ps1' -Action 'snapshot' -ChangeId $FeatureId -RunId $Script:AuditRun.run_id -DurationMs ([int]$snapshotTimer.ElapsedMilliseconds)
            Write-WorkflowAuditEntry -Context $snapshotAuditContext -Outcome 'success' | Out-Null
        }
        catch {
            $snapshotTimer.Stop()
            $snapshotAuditContext = New-WorkflowAuditContext -ScriptName 'archive-feature.ps1' -Action 'snapshot' -ChangeId $FeatureId -RunId $Script:AuditRun.run_id -DurationMs ([int]$snapshotTimer.ElapsedMilliseconds)
            Write-WorkflowAuditEntry -Context $snapshotAuditContext -Outcome 'failure' -ErrorRecord $_ | Out-Null
            throw "Workspace snapshot write failed: $_"
        }
    }

    # Clean up backup after successful archive
    if (Test-Path $backupPath) {
        Remove-Item -Path $backupPath -Recurse -Force -ErrorAction Stop
        Write-Verbose "Cleaned up temporary backup"
        $result.actions += "Cleanup: Removed temporary backup"
    }

    # Update project.md to mark feature as completed (optional)
    $populateScript = Join-Path $ScriptDir "populate-project.ps1"
    if (Test-Path $populateScript) {
        try {
            & $populateScript -Action complete -FeatureBranch $FeatureId -ErrorAction SilentlyContinue
            Write-Verbose "Updated project.md: marked feature as completed"
            $result.actions += "Updated: project.md (marked complete)"
        } catch {
            Write-Verbose "Could not update project.md: $_"
            # Non-fatal - archive already succeeded
        }
    }

    $result.success = $true

    if ($Json) {
        Write-ArchiveJson -Status "success"
    }
    else {
        Write-Host "Archived $FeatureId to $dest" -ForegroundColor Green
    }
    Write-ArchiveAuditEntry -Outcome 'success'
    Pop-Location -ErrorAction SilentlyContinue
    exit $ExitCodes.Success
}
catch {
    Write-Error "Archive operation failed: $_"

    # Rollback - restore from backup if archive partially completed
    if (Test-Path $backupPath) {
        if (Test-Path $dest) {
            Write-Warning "Removing incomplete archive..."
            Remove-Item -Path $dest -Recurse -Force -ErrorAction SilentlyContinue
        }

        if (-not (Test-Path $ChangesDir)) {
            Write-Warning "Restoring original change directory from backup..."
            Move-Item -Path $backupPath -Destination $ChangesDir -Force -ErrorAction Stop
            Write-Host "Rollback successful. Original state restored." -ForegroundColor Yellow
            $result.actions += "Rollback: Restored from backup"
        } else {
            Remove-Item -Path $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $result.success = $false
    $result.validation.errors += $_.Exception.Message

    if ($Json) {
        Write-ArchiveJson -Status "operation_error" -Errors $result.validation.errors
    }

    Write-ArchiveAuditEntry -Outcome 'failure' -ErrorRecord $_
    Pop-Location -ErrorAction SilentlyContinue
    exit $ExitCodes.Operation
}
