#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Merges delta specifications from a feature into the truth specifications.

.DESCRIPTION
    Automates the process of merging delta specs into main truth files.
    Handles versioning, section parsing (ADDED, MODIFIED, REMOVED), and changelog updates.

.PARAMETER FeatureId
    The ID of the feature containing the deltas.
.PARAMETER Json
    Output results as JSON.
.PARAMETER WhatIf
    Dry-run mode.

.NOTES
Exit Codes:
    0 - Success (deltas merged successfully)
    1 - Validation failure or merge error
#>

param(
    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [string]$FeatureId,

    [switch]$Json,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$ExitCodes = @{ Success = 0; Validation = 1; Operation = 2 }

# Source common helpers
$ScriptDir = $PSScriptRoot
$CommonPath = Join-Path $ScriptDir "common.ps1"
if (-not (Test-Path $CommonPath)) {
    Write-Error "common.ps1 not found at $CommonPath"
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

$Script:AuditRun = New-WorkflowScriptRunMetadata -ScriptName 'merge-deltas.ps1'
$Script:AuditContext = New-WorkflowAuditContext -ScriptName 'merge-deltas.ps1' -Action 'merge-deltas' -ChangeId $FeatureId `
    -RunId $Script:AuditRun.run_id
$Script:AuditStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

if (-not (Test-SafePathSegment -Segment $FeatureId)) {
    if ($Json) {
        Write-JsonResult -Result (New-JsonResult -Status "validation_error" -ScriptName "merge-deltas.ps1" -Data @{ feature_id = $FeatureId } -Errors @("Invalid feature ID"))
    } else {
        Write-Error "Invalid feature ID: $FeatureId"
    }
    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'failure' -ErrorRecord "Invalid feature ID: $FeatureId" `
        -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null
    exit $ExitCodes.Validation
}

# 1. Detect Workspace Root
try {
    $RepoRoot = Get-RepositoryRoot
    if (-not $RepoRoot) {
        throw "Could not determine repository root."
    }
} catch {
    Write-Error "Failed to detect repository root: $_"
    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'failure' -ErrorRecord $_ `
        -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null
    exit $ExitCodes.Operation
}

$SpecRoot = Join-Path $RepoRoot "specs"
$DeltaSpecsRoot = Join-Path $SpecRoot "changes" $FeatureId "specs"

function ConvertTo-RequirementId {
    <#
    .SYNOPSIS
        Normalizes a requirement ID value.
    .PARAMETER Id
        Requirement identifier to normalize.
    .OUTPUTS
        Normalized ID string.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Id
    )
    return (
        ($Id -replace '^[\[\(]\s*', '') -replace '\s*[\]\)]$', ''
    ).Trim().ToUpperInvariant()
}

function Get-RequirementIdsFromBlocks {
    <#
    .SYNOPSIS
        Extracts requirement IDs from delta blocks.
    .PARAMETER Blocks
        Delta requirement blocks to scan.
    .OUTPUTS
        Array of requirement IDs.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Blocks
    )
    $Ids = @()
    foreach ($Block in $Blocks) {
        if ($Block -match '(?m)^###\s*Requirement:\s*([\[\(]?REQ[-_][^\s\]]+[\]\)]?)') {
            $Ids += $Matches[1].Trim()
        }
    }
    return $Ids
}

function Test-RequirementExistsInContent {
    <#
    .SYNOPSIS
        Tests whether a requirement ID exists in content.
    .PARAMETER Content
        Content to scan.
    .PARAMETER RequirementId
        Requirement identifier to locate.
    .OUTPUTS
        Boolean indicating presence.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Content,
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RequirementId
    )

    $NormalizedId = ConvertTo-RequirementId $RequirementId
    $Upper = $Content.ToUpperInvariant()
    return $Upper.Contains($NormalizedId)
}

function Backup-TargetFile {
    <#
    .SYNOPSIS
        Creates a backup of a target file for rollback.
    .PARAMETER Path
        File path to back up.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (Test-Path $Path -and -not $Tracker.Backups.ContainsKey($Path)) {
        $BackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("merge-deltas-backup-{0}.bak" -f ([Guid]::NewGuid().ToString()))
        Copy-Item -LiteralPath $Path -Destination $BackupPath -Force -ErrorAction Stop
        Add-TrackedBackup -Tracker $Tracker -Destination $Path -Backup $BackupPath
    }
}

if (-not (Test-Path $DeltaSpecsRoot)) {
    if ($Json) {
        Write-JsonResult -Result (New-JsonResult -Status "success" -ScriptName "merge-deltas.ps1" -Data @{ feature_id = $FeatureId; processed = @(); status = "no_deltas" })
    } else {
        Write-Host "No delta specs found at $DeltaSpecsRoot" -ForegroundColor Yellow
    }
    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'success' -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null
    exit $ExitCodes.Success
}

$Results = @{
    feature_id = $FeatureId
    timestamp = Get-StandardTimestamp
    processed = @()
    errors    = @()
}

# 2. Locate delta files
$DeltaFiles = Get-ChildItem -Path $DeltaSpecsRoot -Filter "spec.md" -Recurse

foreach ($DeltaFile in $DeltaFiles) {
    # Identify target capability (parent directory of spec.md)
    $Capability = $DeltaFile.Directory.Name
    $TargetTruthDir = Join-Path $SpecRoot $Capability
    $TargetTruthFile = Join-Path $TargetTruthDir "spec.md"
    $ChangelogFile = Join-Path $TargetTruthDir "CHANGELOG.md"

    Write-Host "Processing capability: $Capability" -ForegroundColor Cyan

    try {
        $Counts = @{ added = 0; modified = 0; removed = 0 }
        $Action = "none"
        $ValidationErrors = @()

        # --- Parse delta sections
        $DeltaContent = Get-FileContentCached -Path $DeltaFile.FullName -Raw
        $AddedContent    = if ($DeltaContent -match '(?si)##\s*ADDED\b[^\r\n]*\r?\n(.*?)(?=\r?\n##(?![#])|$)') { $Matches[1].Trim() } else { "" }
        $ModifiedContent = if ($DeltaContent -match '(?si)##\s*MODIFIED\b[^\r\n]*\r?\n(.*?)(?=\r?\n##(?![#])|$)') { $Matches[1].Trim() } else { "" }
        $RemovedContent  = if ($DeltaContent -match '(?si)##\s*REMOVED\b[^\r\n]*\r?\n(.*?)(?=\r?\n##(?![#])|$)') { $Matches[1].Trim() } else { "" }

        $ModBlocks = if ($ModifiedContent) { $ModifiedContent -split '(?m)^(?=### Requirement:)' | Where-Object { $_.Trim() } } else { @() }
        $RemBlocks = if ($RemovedContent) { $RemovedContent -split '(?m)^(?=### Requirement:)' | Where-Object { $_.Trim() } } else { @() }

        $ModReqIds = Get-RequirementIdsFromBlocks -Blocks $ModBlocks
        $RemReqIds = Get-RequirementIdsFromBlocks -Blocks $RemBlocks
        $NormalizedModIds = $ModReqIds | ForEach-Object { ConvertTo-RequirementId $_ }
        $NormalizedRemIds = $RemReqIds | ForEach-Object { ConvertTo-RequirementId $_ }

        # --- Validations (A.3)
        if (-not (Test-Path $TargetTruthDir)) {
            $ValidationErrors += "Capability directory not found: $TargetTruthDir"
        }

        if ([string]::IsNullOrWhiteSpace($AddedContent) -and [string]::IsNullOrWhiteSpace($ModifiedContent) -and [string]::IsNullOrWhiteSpace($RemovedContent)) {
            $ValidationErrors += "Delta file has no ADDED/MODIFIED/REMOVED sections: $($DeltaFile.FullName)"
        }

        $DupModIds = ($NormalizedModIds | Group-Object | Where-Object { $_.Count -gt 1 } | Select-Object -ExpandProperty Name)
        if ($DupModIds) {
            $ValidationErrors += "Duplicate requirement IDs in MODIFIED: $($DupModIds -join ', ')"
        }

        $DupRemIds = ($NormalizedRemIds | Group-Object | Where-Object { $_.Count -gt 1 } | Select-Object -ExpandProperty Name)
        if ($DupRemIds) {
            $ValidationErrors += "Duplicate requirement IDs in REMOVED: $($DupRemIds -join ', ')"
        }

        $ConflictingIds = $NormalizedModIds | Where-Object { $NormalizedRemIds -contains $_ } | Select-Object -Unique
        if ($ConflictingIds) {
            $ValidationErrors += "Requirement IDs cannot appear in both MODIFIED and REMOVED: $($ConflictingIds -join ', ')"
        }

        $TruthExists = Test-Path $TargetTruthFile
        $TruthContent = $Null
        if (-not $TruthExists -and (($NormalizedModIds.Count -gt 0) -or ($NormalizedRemIds.Count -gt 0))) {
            $ValidationErrors += "Cannot apply MODIFIED/REMOVED because truth file is missing: $TargetTruthFile"
        }

        if ($TruthExists -and (($NormalizedModIds + $NormalizedRemIds | Select-Object -Unique).Count -gt 0)) {
            $TruthContent = Get-FileContentCached -Path $TargetTruthFile -Raw
            $MissingIds = @()
            foreach ($Id in ($NormalizedModIds + $NormalizedRemIds | Select-Object -Unique)) {
                if (-not (Test-RequirementExistsInContent -Content $TruthContent -RequirementId $Id)) {
                    $MissingIds += $Id
                }
            }
            if ($MissingIds) {
                Write-Warning "Missing requirement IDs in truth ($TargetTruthFile): $($MissingIds -join ', ')"
            }
        }

        if ($ValidationErrors.Count -gt 0) {
            foreach ($Msg in $ValidationErrors) {
                Write-Error "Validation failed for ${capability}: $Msg" -ErrorAction Continue
                $Results.errors += "[$Capability] $Msg"
            }
            $Results.processed += @{ capability = $Capability; action = "validation_failed"; counts = $Counts }
            continue
        }

        # --- Merge / Initialize
        if ($TruthExists) {
            # Version current truth
            $V = 1
            while (Test-Path (Join-Path $TargetTruthDir "spec.v$V.md")) { $V++ }
            $BackupFile = Join-Path $TargetTruthDir "spec.v$V.md"
            if ($WhatIf) {
                Write-Host "  [WhatIf] Would backup to $(Split-Path $BackupFile -Leaf)" -ForegroundColor Gray
            } else {
                Copy-ItemAtomic -Source $TargetTruthFile -Destination $BackupFile
                Add-TrackedFile -Tracker $Tracker -Path $BackupFile
                Add-TrackedBackup -Tracker $Tracker -Destination $TargetTruthFile -Backup $BackupFile
            }

            $UpdatedContent = $TruthContent
            $ReqIdPattern = '###\s*Requirement:\s*([\[\(]?REQ[-_].+?[\]\)]?.*)'

            if ($ModifiedContent) {
                $ModBlocks = $ModifiedContent -split '(?m)^(?=### Requirement:)' | Where-Object { $_.Trim() }
                foreach ($Block in $ModBlocks) {
                    if ($Block -match $ReqIdPattern) {
                        $ReqHeader = $Matches[1].Trim()
                        $EscapedHeader = [Regex]::Escape($ReqHeader)
                        $Pattern = "(?si)### Requirement:\s*$EscapedHeader.*?(?=\r?\n### Requirement:|\r?\n## |\r?\n# |$)"
                        if ($UpdatedContent -match $Pattern) {
                            $UpdatedContent = [Regex]::Replace($UpdatedContent, $Pattern, $Block.Trim())
                            $Counts.modified++
                        }
                    }
                }
            }

            if ($RemovedContent) {
                $RemBlocks = $RemovedContent -split '(?m)^(?=### Requirement:)' | Where-Object { $_.Trim() }
                foreach ($Block in $RemBlocks) {
                    if ($Block -match $ReqIdPattern) {
                        $ReqHeader = $Matches[1].Trim()
                        $EscapedHeader = [Regex]::Escape($ReqHeader)
                        $Pattern = "(?si)### Requirement:\s*$EscapedHeader.*?(?=\r?\n### Requirement:|\r?\n## |\r?\n# |$)"
                        if ($UpdatedContent -match $Pattern) {
                            $UpdatedContent = [Regex]::Replace($UpdatedContent, $Pattern, "")
                            $Counts.removed++
                        }
                    }
                }
            }

            if ($AddedContent) {
                $AddedContentClean = $AddedContent.Trim()
                if ($UpdatedContent -match '## Requirements') {
                    $UpdatedContent = $UpdatedContent.TrimEnd() + "`n`n" + $AddedContentClean
                } else {
                    $UpdatedContent = $UpdatedContent.TrimEnd() + "`n`n## Requirements (Added)`n" + $AddedContentClean
                }
                $Counts.added = ([Regex]::Matches($AddedContentClean, '### Requirement:')).Count
            }

            if (-not $WhatIf) {
                $UpdatedContent = $UpdatedContent -replace '(\r?\n){3,}', "`n`n"
                Backup-TargetFile -Path $TargetTruthFile
                Write-CacheFileAtomic -Path $TargetTruthFile -Content $UpdatedContent.Trim()
                $Action = "merged"
            } else {
                Write-Host "  [WhatIf] Would merge deltas into $Capability/spec.md" -ForegroundColor Gray
                $Action = "would_merge"
            }

            # Log change
            $LogDate = Get-StandardDate
            $LogEntry = @"

## [$LogDate] - Feature: $FeatureId
- Merged deltas from feature branch.
- Added: $($Counts.added)
- Modified: $($Counts.modified)
- Removed: $($Counts.removed)
"@
            if (-not $WhatIf) {
                Backup-TargetFile -Path $ChangelogFile
                if (-not (Test-Path $ChangelogFile)) {
                    Write-CacheFileAtomic -Path $ChangelogFile -Content "# CHANGELOG - $Capability"
                    Add-TrackedFile -Tracker $Tracker -Path $ChangelogFile
                }

                $ExistingLog = Get-FileContentCached -Path $ChangelogFile -Raw
                $UpdatedLog = ($ExistingLog.TrimEnd() + "`n" + $LogEntry).TrimEnd()
                Write-CacheFileAtomic -Path $ChangelogFile -Content $UpdatedLog
            }
        } else {
            # Initialize new capability (ADDED-only)
            if ($WhatIf) {
                Write-Host "  [WhatIf] Would create $TargetTruthDir and initialize spec.md" -ForegroundColor Gray
                $Action = "would_initialize"
            } else {
                if (-not (Test-Path $TargetTruthDir)) {
                    New-Item -ItemType Directory -Path $TargetTruthDir -Force | Out-Null
                    Add-TrackedDirectory -Tracker $Tracker -Path $TargetTruthDir
                }
                Copy-ItemAtomic -Source $DeltaFile.FullName -Destination $TargetTruthFile
                Add-TrackedFile -Tracker $Tracker -Path $TargetTruthFile

                $LogDate = Get-StandardDate
                $InitLog = @"
# CHANGELOG - $Capability

## [$LogDate] - Feature: $FeatureId
- Initial specification baseline from feature delta.
"@
                Write-CacheFileAtomic -Path $ChangelogFile -Content $InitLog
                Add-TrackedFile -Tracker $Tracker -Path $ChangelogFile
                $Action = "initialized"
            }
        }

        $Results.processed += @{ capability = $Capability; action = $Action; counts = $Counts }

    } catch {
        $Err = "Error processing $($Capability): $_"
        Write-Error $Err
        $Results.errors += $Err
    }
}

if ($Results.errors.Count -gt 0) {
    if ($Json) {
        Write-JsonResult -Result (New-JsonResult -Status "operation_error" -ScriptName "merge-deltas.ps1" -Data $Results -Errors $Results.errors)
    } else {
        Write-Host "`nMerge completed with validation errors." -ForegroundColor Yellow
    }
    Invoke-TrackedRollback -Tracker $Tracker
    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'failure' -ErrorRecord ($Results.errors -join '; ') `
        -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null
    exit $ExitCodes.Operation
}

if ($Json) {
    Write-JsonResult -Result (New-JsonResult -Status "success" -ScriptName "merge-deltas.ps1" -Data $Results)
} else {
    Write-Host "`nMerge process completed." -ForegroundColor Green
}

Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'success' -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null

exit $ExitCodes.Success

