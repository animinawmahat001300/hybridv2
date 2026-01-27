#!/usr/bin/env pwsh
# SpecKit Consolidated - common PowerShell functions
# Source: hybrid/scripts/common.ps1 (ported into specs/scripts)

# =============================================================================
# WORKSPACE ROOT DETECTION (T005, T006 - 001-openspec-integration)
# =============================================================================

# Cache for governance data extraction (K.2 / v4 Issue #1)
$Script:GovernanceDataCache = $Null
$Script:GovernanceDataCacheProjectPath = $Null

# =============================================================================
# SCRIPT CONSTANTS & CACHES (WL-15, WL-18, WL-19, WL-20, WL-30)
# =============================================================================
$Script:WorkspaceRootCache = $Null
$Script:WorkspaceRootCacheTimestamp = [DateTime]::MinValue
$Script:WorkspaceRootCacheTtlMinutes = 5
$Script:WorkspaceRootResolving = $False

$Script:FileContentCache = @{}
$Script:FileContentCacheHashes = @{}
$Script:FileContentCacheTimestamps = @{}

$Script:CacheExpiryHours = 1
$Script:WorkspaceRootSearchDepth = 10
$Script:GitRetryCount = 3
$Script:GitRetryBaseDelayMs = 200
$Script:ClarificationLimitDefault = 3
$Script:MaxBranchNameLength = 244
$Script:DefaultAllowedExtensions = @(
    '.md', '.agent.md', '.prompt.md', '.instructions.md',
    '.ps1', '.json', '.yaml', '.yml'
)
$Script:SnapshotSchemaVersion = 1
$Script:DefaultVerbosityMode = 'summary'
$Script:DefaultVerbosityMaxLines = 30

$Script:ExitCodes = @{
    Success = 0
    Validation = 1
    Operation = 2
}

# =============================================================================
# PRECOMPILED REGEX (WL-21, WL-22)
# =============================================================================
$Script:RegexNewLine = '\r?\n'
$Script:RegexCorePrinciplesSection = [regex]::new('(?s)## Core Principles\s*\r?\n(.+?)(?=\r?\n## |\z)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$Script:RegexPrincipleEntry = [regex]::new('### ([IVX]+\. [^\r\n]+)\s*\r?\n+([^#]+?)(?=\r?\n###|\z)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$Script:RegexQualityStandardsSection = [regex]::new('(?s)## Quality Standards\s*\r?\n(.+?)(?=\r?\n## |\z)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$Script:RegexDecisionFrameworkSection = [regex]::new('(?s)## Decision Framework\s*\r?\n(.+?)(?=\r?\n## |\z)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$Script:RegexCodeStyleSection = [regex]::new('(?s)### Code Style\s*\r?\n(.+?)(?=\r?\n### |\z)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$Script:RegexArchitecturePatternsSection = [regex]::new('(?s)### Architecture Patterns\s*\r?\n(.+?)(?=\r?\n### |\z)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$Script:RegexRequirementId = [regex]::new('\bREQ-[A-Z0-9]{3,}\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

# =============================================================================
# COMMON HELPERS (WL-10, WL-11, WL-12, WL-13, WL-15)
# =============================================================================
function Set-StrictErrorActionPreference {
    <#
    .SYNOPSIS
        Sets $ErrorActionPreference to a consistent value and returns the previous.
    .PARAMETER Preference
        Desired ErrorActionPreference value.
    .OUTPUTS
        The previous ErrorActionPreference value.
    #>
    param(
        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [string]$Preference = 'Stop'
    )

    $PreviousPreference = $ErrorActionPreference
    $ErrorActionPreference = $Preference
    return $PreviousPreference
}

function Write-LogInfo {
    <#
    .SYNOPSIS
        Writes a standard informational message.
    .PARAMETER Message
        Message text to display.
    .PARAMETER ForegroundColor
        Optional foreground color for Write-Host.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [System.ConsoleColor]$ForegroundColor
    )

    if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
        Write-Host $Message -ForegroundColor $ForegroundColor
    } else {
        Write-Host $Message
    }
}

function Write-LogWarning {
    <#
    .SYNOPSIS
        Writes a standardized warning message.
    .PARAMETER Message
        Message text to display.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Warning $Message
}

function Write-LogError {
    <#
    .SYNOPSIS
        Writes a standardized error message.
    .PARAMETER Message
        Message text to display.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Error $Message
}

function Write-LogVerbose {
    <#
    .SYNOPSIS
        Writes a standardized verbose message.
    .PARAMETER Message
        Message text to display.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Verbose $Message
}

function Resolve-AbsolutePath {
    <#
    .SYNOPSIS
        Returns a normalized absolute path or $Null when resolution fails.
    .PARAMETER Path
        Path to normalize.
    .OUTPUTS
        Normalized absolute path.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        return [System.IO.Path]::GetFullPath($Path)
    } catch {
        return $Null
    }
}

function Get-IsoTimestamp {
    <#
    .SYNOPSIS
        Returns the current timestamp in ISO 8601 format.
    #>
    return (Get-Date -Format 'o')
}

function Get-PathSafeTimestamp {
    <#
    .SYNOPSIS
        Returns an ISO 8601 timestamp safe for filesystem paths.
    #>
    return (Get-Date -Format 'o').Replace(':', '-')
}

# =============================================================================
# WORKFLOW AUDIT LOGGING HELPERS (003-workflow-audit-logging)
# =============================================================================

function Resolve-WorkflowAuditLogPath {
    <#
    .SYNOPSIS
        Resolves the absolute path to specs/logs/workflow-audit.jsonl.
    .PARAMETER RepoRoot
        Optional repository root override.
    .OUTPUTS
        String absolute log path or $Null when resolution fails.
    #>
    param(
        [string]$RepoRoot
    )

    if (-not $RepoRoot) {
        $RepoRoot = Get-RepositoryRoot
    }

    if (-not $RepoRoot) {
        return $Null
    }

    return (Join-Path $RepoRoot 'specs' 'logs' 'workflow-audit.jsonl')
}

function Ensure-WorkflowAuditLogDirectory {
    <#
    .SYNOPSIS
        Ensures the audit log directory exists and returns its path.
    .PARAMETER LogPath
        Full audit log file path.
    .OUTPUTS
        String directory path.
    #>
    param(
        [string]$LogPath
    )

    if (-not $LogPath) {
        $LogPath = Resolve-WorkflowAuditLogPath
    }

    if (-not $LogPath) {
        return $Null
    }

    $logDirectory = Split-Path -Parent $LogPath
    if (-not (Test-Path $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null
    }

    return $logDirectory
}

function ConvertTo-WorkflowAuditErrorSummary {
    <#
    .SYNOPSIS
        Produces a sanitized error summary for audit logs.
    .PARAMETER ErrorRecord
        Error record, exception, or message to sanitize.
    .PARAMETER MaxLength
        Maximum length for error_summary (default 512).
    .OUTPUTS
        Sanitized string or $Null.
    #>
    param(
        [Parameter(Mandatory = $True)]
        $ErrorRecord,

        [int]$MaxLength = 512
    )

    if (-not $ErrorRecord) {
        return $Null
    }

    $message = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
        $ErrorRecord.Exception.Message
    } elseif ($ErrorRecord -is [System.Exception]) {
        $ErrorRecord.Message
    } else {
        [string]$ErrorRecord
    }

    if (-not $message) {
        return $Null
    }

    # Sanitization per error rules in specs/changes/003-workflow-audit-logging/research.md#error-sanitization
    $summary = ($message -replace '\s+', ' ').Trim()

    $redactionPatterns = @(
        '(?i)(password|passphrase|secret|token|api[_-]?key|access[_-]?key|client[_-]?secret)\s*[:=]\s*\S+',
        '(?i)Bearer\s+[A-Za-z0-9\-\._~\+/]+=*',
        '(?i)(connection|string|connstring)\s*[:=]\s*\S+'
    )

    foreach ($pattern in $redactionPatterns) {
        if ($pattern -match 'Bearer') {
            $summary = [regex]::Replace($summary, $pattern, 'Bearer [REDACTED]')
        } else {
            $summary = [regex]::Replace($summary, $pattern, '$1=[REDACTED]')
        }
    }

    if ($summary.Length -gt $MaxLength) {
        $trimLength = [Math]::Max(0, $MaxLength - 3)
        $summary = $summary.Substring(0, $trimLength)
        if ($summary.Length -gt 0) {
            $summary = "$summary..."
        }
    }

    return $summary
}

function New-WorkflowAuditEntry {
    <#
    .SYNOPSIS
        Builds a WorkflowAuditEntry payload.
    .PARAMETER ScriptName
        Name of the workflow script.
    .PARAMETER Action
        Action label for the entry.
    .PARAMETER Outcome
        Outcome for the action (success/failure).
    .PARAMETER ChangeId
        Optional change identifier.
    .PARAMETER RunId
        Optional run identifier.
    .PARAMETER DurationMs
        Optional action duration in milliseconds.
    .PARAMETER ErrorSummary
        Optional sanitized error summary for failures.
    .OUTPUTS
        Hashtable representing WorkflowAuditEntry.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptName,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Action,

        [Parameter(Mandatory = $True)]
        [ValidateSet('success', 'failure')]
        [string]$Outcome,

        [string]$ChangeId,

        [string]$RunId,

        [int]$DurationMs,

        [string]$ErrorSummary
    )

    # Implements WorkflowAuditEntry schema per specs/changes/003-workflow-audit-logging/data-model.md#workflowauditentry
    return [ordered]@{
        timestamp = Get-IsoTimestamp
        script_name = $ScriptName
        action = $Action
        change_id = $ChangeId
        outcome = $Outcome
        error_summary = $ErrorSummary
        run_id = $RunId
        duration_ms = $DurationMs
    }
}

function Test-WorkflowAuditEntrySchema {
    <#
    .SYNOPSIS
        Validates a WorkflowAuditEntry payload against schema constraints.
    .PARAMETER Entry
        WorkflowAuditEntry hashtable to validate.
    .OUTPUTS
        PSCustomObject with IsValid and Errors collection.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$Entry
    )

    # Schema validation per specs/changes/003-workflow-audit-logging/data-model.md#workflowauditentry
    $errors = @()
    $requiredFields = @('timestamp', 'script_name', 'action', 'outcome')

    foreach ($field in $requiredFields) {
        if (-not $Entry.ContainsKey($field) -or [string]::IsNullOrWhiteSpace([string]$Entry[$field])) {
            $errors += "Missing required field: $field"
        }
    }

    if ($Entry.outcome -and ($Entry.outcome -notin @('success', 'failure'))) {
        $errors += "Invalid outcome value: $($Entry.outcome)"
    }

    if ($Entry.timestamp) {
        try {
            [DateTime]::Parse($Entry.timestamp) | Out-Null
        } catch {
            $errors += "Invalid timestamp value: $($Entry.timestamp)"
        }
    }

    if ($Entry.error_summary -and $Entry.error_summary.Length -gt 512) {
        $errors += "error_summary exceeds maximum length (512 chars)"
    }

    if ($Entry.duration_ms -ne $Null -and [int]$Entry.duration_ms -lt 0) {
        $errors += "duration_ms must be greater than or equal to 0"
    }

    return [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = $errors
    }
}

function Append-WorkflowAuditJsonLine {
    <#
    .SYNOPSIS
        Appends a JSONL entry with retry/backoff and append-only guard.
    .PARAMETER LogPath
        Full audit log file path.
    .PARAMETER Entry
        Audit entry hashtable.
    .PARAMETER RetryCount
        Number of retry attempts on failure.
    .PARAMETER BaseDelayMs
        Base delay in milliseconds for exponential backoff.
    .OUTPUTS
        PSCustomObject with Success, Path, Attempts, Error.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$Entry,

        [int]$RetryCount = 3,

        [int]$BaseDelayMs = 100
    )

    # Concurrency handling per specs/changes/003-workflow-audit-logging/research.md#concurrency-handling
    Ensure-WorkflowAuditLogDirectory -LogPath $LogPath | Out-Null

    $jsonLine = $Entry | ConvertTo-Json -Depth 10 -Compress
    if ([string]::IsNullOrWhiteSpace($jsonLine)) {
        return [PSCustomObject]@{
            Success = $False
            Path = $LogPath
            Attempts = 0
            Error = 'Audit entry serialized to empty JSON.'
        }
    }

    $attempt = 0
    $lastError = $Null

    while ($attempt -lt $RetryCount) {
        $attempt++
        try {
            $preLength = if (Test-Path $LogPath) { (Get-Item -LiteralPath $LogPath).Length } else { 0 }
            [System.IO.File]::AppendAllText($LogPath, "$jsonLine$([Environment]::NewLine)", [System.Text.Encoding]::UTF8)
            $postLength = (Get-Item -LiteralPath $LogPath).Length
            if ($postLength -le $preLength) {
                throw "Append-only guard failed: audit log size did not increase."
            }

            return [PSCustomObject]@{
                Success = $True
                Path = $LogPath
                Attempts = $attempt
                Error = $Null
            }
        } catch {
            $lastError = $_
            if ($attempt -lt $RetryCount) {
                $delay = [Math]::Min($BaseDelayMs * [Math]::Pow(2, ($attempt - 1)), 2000)
                Start-Sleep -Milliseconds $delay
            }
        }
    }

    return [PSCustomObject]@{
        Success = $False
        Path = $LogPath
        Attempts = $RetryCount
        Error = $lastError.ToString()
    }
}

function Write-WorkflowAuditEntry {
    <#
    .SYNOPSIS
        Writes a workflow audit entry to the JSONL log.
    .PARAMETER Context
        Hashtable containing script_name, action, change_id, run_id, and optional log_path.
    .PARAMETER Outcome
        Outcome for the entry (success/failure).
    .PARAMETER ErrorRecord
        Error record or message to sanitize for failure entries.
    .PARAMETER DurationMs
        Optional duration in milliseconds.
    .PARAMETER ThrowOnFailure
        When set, throws if the append fails.
    .OUTPUTS
        PSCustomObject with Success, Entry, Path, Error.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$Context,

        [Parameter(Mandatory = $True)]
        [ValidateSet('success', 'failure')]
        [string]$Outcome,

        $ErrorRecord,

        [int]$DurationMs,

        [switch]$ThrowOnFailure
    )

    if (-not $Context.script_name -or -not $Context.action) {
        $missing = @()
        if (-not $Context.script_name) { $missing += 'script_name' }
        if (-not $Context.action) { $missing += 'action' }
        $message = "Workflow audit context missing required fields: $($missing -join ', ')"
        if ($ThrowOnFailure) {
            throw $message
        }
        return [PSCustomObject]@{
            Success = $False
            Entry = $Null
            Path = $Null
            Error = $message
        }
    }

    $logPath = if ($Context.log_path) { $Context.log_path } else { Resolve-WorkflowAuditLogPath }
    if (-not $logPath) {
        $message = 'Unable to resolve workflow audit log path.'
        if ($ThrowOnFailure) {
            throw $message
        }
        return [PSCustomObject]@{
            Success = $False
            Entry = $Null
            Path = $Null
            Error = $message
        }
    }

    $summary = $Null
    if ($Outcome -eq 'failure') {
        if ($Context.error_summary) {
            $summary = ConvertTo-WorkflowAuditErrorSummary -ErrorRecord $Context.error_summary
        } elseif ($ErrorRecord) {
            $summary = ConvertTo-WorkflowAuditErrorSummary -ErrorRecord $ErrorRecord
        }
    }

    # Endpoint implementation for POST /api/workflow-audit (specs/changes/003-workflow-audit-logging/contracts/workflow-audit/create.yaml#L6)
    $durationMs = if ($PSBoundParameters.ContainsKey('DurationMs')) {
        $DurationMs
    } elseif ($Context.duration_ms) {
        $Context.duration_ms
    } else {
        $Null
    }

    $entryParams = @{
        ScriptName = $Context.script_name
        Action = $Context.action
        Outcome = $Outcome
        ChangeId = $Context.change_id
        RunId = $Context.run_id
        DurationMs = $durationMs
        ErrorSummary = $summary
    }

    $Entry = New-WorkflowAuditEntry @entryParams

    $schemaResult = Test-WorkflowAuditEntrySchema -Entry $Entry
    if (-not $schemaResult.IsValid) {
        $message = "Workflow audit entry validation failed: $($schemaResult.Errors -join '; ')"
        if ($ThrowOnFailure) {
            throw $message
        }
        return [PSCustomObject]@{
            Success = $False
            Entry = $Entry
            Path = $logPath
            Error = $message
        }
    }

    $appendResult = Append-WorkflowAuditJsonLine -LogPath $logPath -Entry $Entry

    if (-not $appendResult.Success) {
        Write-Warning "[speckit] Audit log append failed: $($appendResult.Error)"
        if ($ThrowOnFailure) {
            throw $appendResult.Error
        }
    }

    return [PSCustomObject]@{
        Success = $appendResult.Success
        Entry = $Entry
        Path = $appendResult.Path
        Error = $appendResult.Error
    }
}

function New-WorkflowScriptRunMetadata {
    <#
    .SYNOPSIS
        Builds WorkflowScriptRun metadata for audit correlation.
    .PARAMETER ScriptName
        Name of the workflow script.
    .PARAMETER RunId
        Optional run identifier override.
    .PARAMETER StartedAt
        Optional start timestamp override (ISO 8601).
    .PARAMETER FinishedAt
        Optional finish timestamp.
    .PARAMETER Outcome
        Optional aggregate outcome.
    .PARAMETER EntryCount
        Optional entry count.
    .OUTPUTS
        Hashtable representing WorkflowScriptRun metadata.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptName,

        [string]$RunId,

        [string]$StartedAt,

        [string]$FinishedAt,

        [ValidateSet('success', 'failure')]
        [string]$Outcome,

        [int]$EntryCount
    )

    # Implements WorkflowScriptRun schema per specs/changes/003-workflow-audit-logging/data-model.md#workflowscriptrun
    return [ordered]@{
        run_id = if ($RunId) { $RunId } else { ([Guid]::NewGuid().ToString()) }
        script_name = $ScriptName
        started_at = if ($StartedAt) { $StartedAt } else { Get-IsoTimestamp }
        finished_at = $FinishedAt
        outcome = $Outcome
        entry_count = $EntryCount
    }
}

function New-WorkflowAuditContext {
    <#
    .SYNOPSIS
        Builds a standard workflow audit context payload.
    .PARAMETER ScriptName
        Name of the workflow script.
    .PARAMETER Action
        Action label for the audit entry.
    .PARAMETER ChangeId
        Optional change identifier.
    .PARAMETER RunId
        Optional run identifier.
    .PARAMETER LogPath
        Optional log path override.
    .PARAMETER DurationMs
        Optional duration in milliseconds.
    .OUTPUTS
        Hashtable suitable for Write-WorkflowAuditEntry.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptName,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Action,

        [string]$ChangeId,

        [string]$RunId,

        [string]$LogPath,

        [int]$DurationMs
    )

    return @{
        script_name = $ScriptName
        action = $Action
        change_id = $ChangeId
        run_id = $RunId
        log_path = $LogPath
        duration_ms = $DurationMs
    }
}

function Get-WorkflowAuditEntries {
    <#
    .SYNOPSIS
        Reads workflow audit entries from the JSONL log.
    .PARAMETER ChangeId
        Optional change ID filter.
    .PARAMETER Outcome
        Optional outcome filter.
    .PARAMETER Limit
        Optional maximum number of entries to return.
    .OUTPUTS
        Array of audit entry objects.
    #>
    param(
        [string]$ChangeId,

        [ValidateSet('success', 'failure')]
        [string]$Outcome,

        [int]$Limit
    )

    # Endpoint implementation for GET /api/workflow-audit (specs/changes/003-workflow-audit-logging/contracts/workflow-audit/list.yaml#L6)
    $logPath = Resolve-WorkflowAuditLogPath
    if (-not $logPath -or -not (Test-Path $logPath)) {
        return @()
    }

    $lines = Get-Content -LiteralPath $logPath -ErrorAction Stop
    $entries = foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warning "[speckit] Skipping invalid audit log line: $line"
        }
    }

    if ($ChangeId) {
        $entries = $entries | Where-Object { $_.change_id -eq $ChangeId }
    }
    if ($Outcome) {
        $entries = $entries | Where-Object { $_.outcome -eq $Outcome }
    }
    if ($Limit -and $Limit -gt 0) {
        $entries = $entries | Select-Object -Last $Limit
    }

    return @($entries)
}

function Test-SafePathSegment {
    <#
    .SYNOPSIS
        Validates that a path segment is safe for Join-Path usage.
    .PARAMETER Segment
        The path segment to validate.
    .OUTPUTS
        Boolean - $True if safe, $False otherwise.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Segment
    )

    if ($Segment -match '[\\/]' -or $Segment -match '\.\.' ) {
        return $False
    }

    $InvalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    if ($Segment.IndexOfAny($InvalidChars) -ge 0) {
        return $False
    }

    return $True
}

function Invoke-GitCommand {
    <#
    .SYNOPSIS
        Executes a git command with retry/backoff and returns structured results.
    .PARAMETER GitArgs
        Argument list passed to git.
    .PARAMETER Retries
        Number of retries for transient failures.
    .PARAMETER IgnoreErrors
        Suppress warnings on failure when set.
    .OUTPUTS
        PSCustomObject with Success, Output, ExitCode, Error.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string[]]$GitArgs,

        [int]$Retries = $Script:GitRetryCount,

        [switch]$IgnoreErrors
    )

    $Attempt = 0
    $Output = $Null
    $ExitCode = 0
    while ($Attempt -lt $Retries) {
        $Attempt++
        $Output = & git @GitArgs 2>$Null
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -eq 0) {
            return [PSCustomObject]@{
                Success = $True
                Output = $Output
                ExitCode = $ExitCode
                Error = $Null
            }
        }

        if ($Attempt -lt $Retries) {
            $Delay = $Script:GitRetryBaseDelayMs * [Math]::Pow(2, ($Attempt - 1))
            Start-Sleep -Milliseconds $Delay
        }
    }

    if (-not $IgnoreErrors) {
        Write-Warning "[speckit] Git command failed (exit $ExitCode): git $($GitArgs -join ' ')"
    }

    return [PSCustomObject]@{
        Success = $False
        Output = $Output
        ExitCode = $ExitCode
        Error = "Git command failed with exit code $ExitCode"
    }
}

function Test-GitRef {
    <#
    .SYNOPSIS
        Validates a git ref string to prevent command injection.
    .PARAMETER BaseRef
        Git ref to validate.
    .OUTPUTS
        Boolean - $True if valid.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseRef
    )

    return ($BaseRef -match '^[A-Za-z0-9][A-Za-z0-9._/\-]*$')
}

function Get-DefaultGitBaseRef {
    <#
    .SYNOPSIS
        Detects the default Git base branch.
    .OUTPUTS
        String base ref (e.g., "main").
    #>
    if (-not (Test-HasGit)) {
        return 'main'
    }

    $RefResult = Invoke-GitCommand -GitArgs @('symbolic-ref', '--short', 'refs/remotes/origin/HEAD') -IgnoreErrors
    if ($RefResult.Success -and $RefResult.Output) {
        $RefValue = ($RefResult.Output | Select-Object -First 1).Trim()
        if ($RefValue -match '.+/(?<branch>[^/]+)$') {
            return $Matches['branch']
        }
    }

    $RemoteResult = Invoke-GitCommand -GitArgs @('remote', 'show', 'origin') -IgnoreErrors
    if ($RemoteResult.Success -and $RemoteResult.Output) {
        $Line = $RemoteResult.Output | Where-Object { $_ -match 'HEAD branch:' } | Select-Object -First 1
        if ($Line -match 'HEAD branch:\s*(?<branch>\S+)') {
            return $Matches['branch']
        }
    }

    return 'main'
}

function Get-JsonSchema {
    <#
    .SYNOPSIS
        Returns JSON schema for standardized script output.
    #>
    return @'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["status", "timestamp", "script", "data", "errors", "warnings"],
  "properties": {
    "status": { "type": "string" },
    "timestamp": { "type": "string" },
    "script": { "type": "string" },
    "data": { "type": "object" },
    "errors": { "type": "array" },
    "warnings": { "type": "array" }
  }
}
'@
}

function New-JsonResult {
    <#
    .SYNOPSIS
        Builds a standardized JSON output payload.
    .PARAMETER Status
        Result status (success, validation_error, operation_error).
    .PARAMETER ScriptName
        Script name emitting the payload.
    .PARAMETER Data
        Payload data object.
    .PARAMETER Errors
        Array of error strings.
    .PARAMETER Warnings
        Array of warning strings.
    .OUTPUTS
        Hashtable representing the standardized output.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Status,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptName,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$Data,

        [string[]]$Errors = @(),

        [string[]]$Warnings = @()
    )

    return @{
        status = $Status
        timestamp = Get-IsoTimestamp
        script = $ScriptName
        data = $Data
        errors = @($Errors)
        warnings = @($Warnings)
    }
}

function Write-JsonResult {
    <#
    .SYNOPSIS
        Writes standardized JSON output with schema validation.
    .PARAMETER Result
        Hashtable from New-JsonResult.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$Result
    )

    $JsonOutput = $Result | ConvertTo-Json -Depth 10 -Compress
    $Schema = Get-JsonSchema
    $SchemaValid = $True

    try {
        $SchemaValid = Test-Json -Json $JsonOutput -Schema $Schema
    } catch {
        $SchemaValid = $False
    }

    if (-not $SchemaValid) {
        Write-Warning "[speckit] JSON output failed schema validation"
    }

    Write-Output $JsonOutput
}

function Get-ExitCodes {
    <#
    .SYNOPSIS
        Returns standardized exit code map.
    #>
    return $Script:ExitCodes
}

function Get-SpeckitConstants {
    <#
    .SYNOPSIS
        Returns shared script constants.
    #>
    return @{
        CacheExpiryHours = $Script:CacheExpiryHours
        WorkspaceRootSearchDepth = $Script:WorkspaceRootSearchDepth
        ClarificationLimitDefault = $Script:ClarificationLimitDefault
        MaxBranchNameLength = $Script:MaxBranchNameLength
        DefaultAllowedExtensions = $Script:DefaultAllowedExtensions
        SnapshotSchemaVersion = $Script:SnapshotSchemaVersion
        DefaultVerbosityMode = $Script:DefaultVerbosityMode
        DefaultVerbosityMaxLines = $Script:DefaultVerbosityMaxLines
    }
}

function Ensure-ArchiveDirectory {
    <#
    .SYNOPSIS
        Ensures the specs/changes/archive directory exists and returns its path.
    .PARAMETER RepoRoot
        Optional repository root override.
    .OUTPUTS
        String archive directory path or $Null.
    #>
    param(
        [string]$RepoRoot
    )

    if (-not $RepoRoot) {
        $RepoRoot = Get-RepositoryRoot
    }

    if (-not $RepoRoot) {
        return $Null
    }

    $ArchiveDir = Join-Path $RepoRoot 'specs' 'changes' 'archive'
    if (-not (Test-Path $ArchiveDir)) {
        New-Item -ItemType Directory -Path $ArchiveDir -Force -ErrorAction Stop | Out-Null
    }

    return $ArchiveDir
}

function Get-FileContentCached {
    <#
    .SYNOPSIS
        Reads file content with in-memory hash caching.
    .PARAMETER Path
        File path to read.
    .PARAMETER Raw
        Return raw content when set.
    .PARAMETER Encoding
        File encoding.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$Raw,

        [string]$Encoding = 'UTF8'
    )

    if (-not (Test-Path $Path)) {
        return $Null
    }

    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Script:FileContentCacheHashes.ContainsKey($Path) -and $Script:FileContentCacheHashes[$Path] -eq $Hash) {
        return $Script:FileContentCache[$Path]
    }

    $Content = if ($Raw) {
        Get-Content -LiteralPath $Path -Raw -Encoding $Encoding
    } else {
        Get-Content -LiteralPath $Path -Encoding $Encoding
    }

    $Script:FileContentCache[$Path] = $Content
    $Script:FileContentCacheHashes[$Path] = $Hash
    $Script:FileContentCacheTimestamps[$Path] = Get-IsoTimestamp
    return $Content
}

function Write-CacheFileAtomic {
    <#
    .SYNOPSIS
        Writes content to a cache file atomically.
    .PARAMETER Path
        Destination cache file path.
    .PARAMETER Content
        Content string to write.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Content
    )

    $TempPath = "{0}.{1}.tmp" -f $Path, ([Guid]::NewGuid().ToString())
    Set-Content -LiteralPath $TempPath -Value $Content -Encoding UTF8
    Move-Item -LiteralPath $TempPath -Destination $Path -Force
}

function New-OperationTracker {
    <#
    .SYNOPSIS
        Creates a tracker for created files/directories and backups.
    #>
    return [PSCustomObject]@{
        CreatedFiles = New-Object System.Collections.Generic.List[string]
        CreatedDirectories = New-Object System.Collections.Generic.List[string]
        Backups = @{}
    }
}

function Add-TrackedFile {
    <#
    .SYNOPSIS
        Records a created file for rollback tracking.
    .PARAMETER Tracker
        Operation tracker instance.
    .PARAMETER Path
        File path to record.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        $Tracker,
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not $Tracker.CreatedFiles.Contains($Path)) {
        $Tracker.CreatedFiles.Add($Path)
    }
}

function Add-TrackedDirectory {
    <#
    .SYNOPSIS
        Records a created directory for rollback tracking.
    .PARAMETER Tracker
        Operation tracker instance.
    .PARAMETER Path
        Directory path to record.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        $Tracker,
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not $Tracker.CreatedDirectories.Contains($Path)) {
        $Tracker.CreatedDirectories.Add($Path)
    }
}

function Add-TrackedBackup {
    <#
    .SYNOPSIS
        Records a backup created for rollback.
    .PARAMETER Tracker
        Operation tracker instance.
    .PARAMETER Destination
        Destination path that can be restored.
    .PARAMETER Backup
        Backup file path.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        $Tracker,
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Backup
    )

    $Tracker.Backups[$Destination] = $Backup
}

function Invoke-TrackedRollback {
    <#
    .SYNOPSIS
        Removes created artifacts and restores backups.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        $Tracker
    )

    foreach ($FilePath in $Tracker.CreatedFiles) {
        if (Test-Path $FilePath) {
            Remove-Item -LiteralPath $FilePath -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($DirectoryPath in $Tracker.CreatedDirectories) {
        if (Test-Path $DirectoryPath) {
            Remove-Item -LiteralPath $DirectoryPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($Entry in $Tracker.Backups.GetEnumerator()) {
        $Destination = $Entry.Key
        $Backup = $Entry.Value
        if (Test-Path $Backup) {
            Copy-Item -LiteralPath $Backup -Destination $Destination -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $Backup -Force -ErrorAction SilentlyContinue
        }
    }
}

function Copy-ItemAtomic {
    <#
    .SYNOPSIS
        Copies a file using an atomic temp + move strategy.
    .PARAMETER Source
        Source file path.
    .PARAMETER Destination
        Destination file path.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
    )

    $TempDestination = "{0}.{1}.tmp" -f $Destination, ([Guid]::NewGuid().ToString())
    Copy-Item -LiteralPath $Source -Destination $TempDestination -Force -ErrorAction Stop
    Move-Item -LiteralPath $TempDestination -Destination $Destination -Force -ErrorAction Stop
}

function Get-WorkspaceRoot {
    <#
    .SYNOPSIS
        Detects the workspace root by finding the SpecKit workspace directory
    .DESCRIPTION
        Uses multiple strategies to find workspace root:
        1. Script location: Go up 2 levels from specs/scripts/ and verify specs/memory/constitution.md exists
        2. Git root: Only if it contains specs/memory/constitution.md (valid SpecKit workspace)
        3. Walk-up search: From current directory looking for specs/memory/constitution.md
        This order ensures hybrid/ is detected when it's a subfolder of another git repo.

        SAFE FROM RECURSION (Issue #27):
        This function is a leaf-node for workspace detection and does not call any other functions
        that might source common.ps1 or call back into this function (like Test-HasGit).
    .OUTPUTS
        String path to workspace root, or $Null if not found
    #>

    if ($Script:WorkspaceRootCache -and ((Get-Date) - $Script:WorkspaceRootCacheTimestamp).TotalMinutes -lt $Script:WorkspaceRootCacheTtlMinutes) {
        return $Script:WorkspaceRootCache
    }

    if ($Script:WorkspaceRootResolving) {
        return $Script:WorkspaceRootCache
    }

    $Script:WorkspaceRootResolving = $True
    try {
        # Helper to validate a SpecKit workspace root
        function Test-SpecKitRoot {
            param([string]$Path)
            if (-not $Path -or -not (Test-Path $Path)) { return $False }
            $Constitution = Join-Path $Path "specs" "memory" "constitution.md"
            return (Test-Path $Constitution)
        }

        function Set-WorkspaceRootCache {
            param([string]$RootPath)
            $ResolvedRoot = if ($RootPath) { Resolve-AbsolutePath $RootPath } else { $Null }
            if ($ResolvedRoot) {
                $Script:WorkspaceRootCache = $ResolvedRoot
                $Script:WorkspaceRootCacheTimestamp = Get-Date
                return $ResolvedRoot
            }
            return $Null
        }

        # Strategy 1: Script location - go up 2 levels from specs/scripts/
        # This is the most reliable when running from within the workspace
        if ($PSScriptRoot) {
            try {
                $CandidateRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot ".." "..")
                if (Test-SpecKitRoot $CandidateRoot) {
                    return (Set-WorkspaceRootCache -RootPath $CandidateRoot)
                }
            } catch {
                # Fall through to next strategy
            }
        }

        # Strategy 2: Git repository root - only if it's a valid SpecKit workspace
        # This handles the case where the SpecKit workspace IS the git root
        $SearchPath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $Current = $SearchPath
        for ($DepthIndex = 0; $DepthIndex -lt $Script:WorkspaceRootSearchDepth; $DepthIndex++) {
            $GitDir = Join-Path $Current ".git"
            if (Test-Path $GitDir) {
                try {
                    $GitRootResult = Invoke-GitCommand -GitArgs @('rev-parse', '--show-toplevel') -IgnoreErrors
                    if ($GitRootResult.Success -and $GitRootResult.Output) {
                        $GitRootClean = ($GitRootResult.Output | Select-Object -First 1).Trim()
                        $GitRootClean = Resolve-AbsolutePath $GitRootClean
                        # Only use git root if it's a valid SpecKit workspace
                        if (Test-SpecKitRoot $GitRootClean) {
                            return (Set-WorkspaceRootCache -RootPath $GitRootClean)
                        }
                    }
                } catch {
                    # Fall through to next strategy
                }
                break
            }
            $Parent = Split-Path $Current -Parent
            if (-not $Parent -or $Parent -eq $Current) { break }
            $Current = $Parent
        }

        # Strategy 3: Walk up from current location looking for specs/memory/constitution.md
        $SearchPath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $Current = $SearchPath
        for ($DepthIndex = 0; $DepthIndex -lt $Script:WorkspaceRootSearchDepth; $DepthIndex++) {
            if (Test-SpecKitRoot $Current) {
                return (Set-WorkspaceRootCache -RootPath $Current)
            }
            $Parent = Split-Path $Current -Parent
            if (-not $Parent -or $Parent -eq $Current) {
                break
            }
            $Current = $Parent
        }

        # Strategy 4: Last resort - script location parent (original fallback)
        if ($PSScriptRoot) {
            $Fallback = Resolve-AbsolutePath (Join-Path $PSScriptRoot ".." "..")
            if ($Fallback) {
                return (Set-WorkspaceRootCache -RootPath $Fallback)
            }
        }

        return $Null
    }
    finally {
        $Script:WorkspaceRootResolving = $False
    }
}

function Get-StandardDate {
    <#
    .SYNOPSIS
        Returns the current date/time in ISO 8601 format.
    #>
    return Get-IsoTimestamp
}

function Get-StandardTimestamp {
    <#
    .SYNOPSIS
        Returns the current timestamp in ISO 8601 format.
    #>
    return Get-IsoTimestamp
}

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

    $WorkspaceRoot = Get-WorkspaceRoot
    if (-not $WorkspaceRoot) {
        Write-Warning "[speckit] Could not determine workspace root"
        return $Null
    }

    if (-not $FeatureId) {
        $FeatureId = Get-CurrentChangeId
    }

    if (-not $FeatureId) {
        Write-Warning "[speckit] No feature ID provided and could not detect current feature"
        return $Null
    }

    if (-not (Test-SafePathSegment -Segment $FeatureId)) {
        Write-Warning "[speckit] Invalid feature ID '$FeatureId' - refusing to resolve feature directory"
        return $Null
    }

    # Check in specs/changes/{feature}/ first (primary location for active features)
    $ChangesFeatureDir = Join-Path $WorkspaceRoot "specs" "changes" $FeatureId
    if (Test-Path $ChangesFeatureDir) {
        return $ChangesFeatureDir
    }

    # Check in specs/{feature}/ (legacy or alternative location)
    $SpecsFeatureDir = Join-Path $WorkspaceRoot "specs" $FeatureId
    if (Test-Path $SpecsFeatureDir) {
        return $SpecsFeatureDir
    }

    # Return expected path even if doesn't exist yet (for creation)
    return $ChangesFeatureDir
}

function Get-RepoRoot {
    <#
    .SYNOPSIS
        Legacy repository root accessor (delegates to Get-WorkspaceRoot).
    .OUTPUTS
        String path to workspace root.
    #>
    # Delegate to Get-WorkspaceRoot which has proper SpecKit detection
    return Get-WorkspaceRoot
}

function Get-RepositoryRoot {
    <#
    .SYNOPSIS
        Canonical repository root accessor for hybrid SpecKit.
    .DESCRIPTION
        Wrapper around Get-WorkspaceRoot to provide a single, clear API name.
        Existing callers of Get-RepoRoot/Get-WorkspaceRoot remain supported.
    #>
    return Get-WorkspaceRoot
}

function Resolve-ChangeId {
    <#
    .SYNOPSIS
        Resolves the active change ID using env, git, or filesystem.
    .PARAMETER RepoRoot
        Optional repository root override.
    .OUTPUTS
        PSCustomObject with ChangeId, Source, Warnings, Errors, Candidates.
    #>
    param(
        [string]$RepoRoot
    )

    $result = [ordered]@{
        ChangeId = $Null
        Source = $Null
        Warnings = @()
        Errors = @()
        Candidates = @()
    }

    if ($Env:SPECIFY_CHANGE_ID) {
        $result.ChangeId = $Env:SPECIFY_CHANGE_ID
        $result.Source = 'env'
        return $result
    }

    if ($Env:SPECIFY_FEATURE) {
        if (-not $Env:SPECIFY_CHANGE_ID) {
            $Env:SPECIFY_CHANGE_ID = $Env:SPECIFY_FEATURE
        }
        $result.Warnings += 'SPECIFY_FEATURE is deprecated. Auto-migrated to SPECIFY_CHANGE_ID.'
        $result.ChangeId = $Env:SPECIFY_CHANGE_ID
        $result.Source = 'env'
        return $result
    }

    $hasGit = Test-HasGit
    if ($hasGit) {
        $branch = Get-CurrentBranch
        if ($branch -and $branch -ne 'none') {
            $result.ChangeId = $branch
            $result.Source = 'git'
            return $result
        }
    }

    if (-not $RepoRoot) {
        $RepoRoot = Get-RepositoryRoot
    }

    if (-not $RepoRoot) {
        $result.Errors += 'Repository root not found.'
        return $result
    }

    $changesDir = Join-Path $RepoRoot 'specs' 'changes'
    if (-not (Test-Path $changesDir)) {
        $result.Errors += "Changes directory not found: $changesDir"
        return $result
    }

    $candidates = Get-ChildItem -Path $changesDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'archive' }
    if (-not $candidates -or $candidates.Count -eq 0) {
        $result.Errors += "No change folders found under $changesDir"
        return $result
    }

    if ($candidates.Count -eq 1) {
        $result.ChangeId = $candidates[0].Name
        $result.Source = 'filesystem'
        return $result
    }

    $result.Candidates = $candidates | Select-Object -ExpandProperty Name
    $result.Errors += "Multiple change folders detected: $($result.Candidates -join ', '). Set SPECIFY_CHANGE_ID."
    return $result
}

function Get-CurrentChangeId {
    <#
    .SYNOPSIS
        Detects the current change ID from environment, git branch, or filesystem.
    .OUTPUTS
        String change ID or $Null when not found.
    #>
    # Preferred
    if ($Env:SPECIFY_CHANGE_ID) {
        return $Env:SPECIFY_CHANGE_ID
    }

    # Legacy support (deprecated)
    if ($Env:SPECIFY_FEATURE) {
        if (-not $Env:SPECIFY_CHANGE_ID) {
            $Env:SPECIFY_CHANGE_ID = $Env:SPECIFY_FEATURE
        }
        Write-Warning "[speckit] SPECIFY_FEATURE is deprecated. Auto-migrated to SPECIFY_CHANGE_ID. This will be an error in the next major release."
        return $Env:SPECIFY_CHANGE_ID
    }

    $resolution = Resolve-ChangeId
    if ($resolution.ChangeId) {
        return $resolution.ChangeId
    }

    return $Null
}

function Get-VerbosityMode {
    <#
    .SYNOPSIS
        Returns the active verbosity mode for the current session.
    .OUTPUTS
        String: summary or verbose.
    #>
    if ($VerbosePreference -eq 'Continue') {
        return 'verbose'
    }
    return $Script:DefaultVerbosityMode
}

function New-WorkflowExecutionContext {
    <#
    .SYNOPSIS
        Builds a WorkflowExecutionContext payload.
    .PARAMETER ChangeId
        Resolved change identifier.
    .PARAMETER RepoRoot
        Resolved workspace root.
    .PARAMETER GitAvailable
        Indicates whether Git is available.
    .PARAMETER VerbosityMode
        summary or verbose.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$ChangeId,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $True)]
        [bool]$GitAvailable,

        [string]$VerbosityMode
    )

    $mode = if ($VerbosityMode) { $VerbosityMode } else { Get-VerbosityMode }

    return [ordered]@{
        execution_id = ([Guid]::NewGuid().ToString())
        change_id = $ChangeId
        repo_root = $RepoRoot
        git_available = $GitAvailable
        verbosity_mode = $mode
        started_at = Get-IsoTimestamp
    }
}

function New-WorkspaceFileMetadata {
    <#
    .SYNOPSIS
        Builds file metadata for workspace snapshot entries.
    .PARAMETER RepoRoot
        Repository root.
    .PARAMETER RelativePath
        File path relative to repo root.
    .OUTPUTS
        Hashtable with path, size_bytes, last_write_time.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RelativePath
    )

    $fullPath = Join-Path $RepoRoot $RelativePath
    $item = Get-Item -LiteralPath $fullPath -ErrorAction SilentlyContinue
    return [ordered]@{
        path = $RelativePath
        size_bytes = if ($item) { [int64]$item.Length } else { $Null }
        last_write_time = if ($item) { $item.LastWriteTimeUtc.ToString('o') } else { $Null }
    }
}

function New-WorkspaceSnapshot {
    <#
    .SYNOPSIS
        Builds a workspace snapshot payload for archive.
    .PARAMETER RepoRoot
        Workspace root path.
    .PARAMETER ChangeId
        Active change identifier.
    .PARAMETER FeatureDir
        Active change directory for gitless capture.
    .OUTPUTS
        Hashtable representing the snapshot.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$ChangeId,

        [string]$FeatureDir
    )

    $notes = @()
    $modifiedFiles = @()
    $untrackedFiles = @()
    $gitStatus = $Null
    $gitAvailable = Test-HasGit

    if ($gitAvailable) {
        $branch = Get-CurrentBranch
        $statusResult = Invoke-GitCommand -GitArgs @('status', '--porcelain') -IgnoreErrors
        if (-not $statusResult.Success) {
            $notes += "Git status command failed: $($statusResult.Error)"
            $gitAvailable = $False
        } else {
            $statusLines = @($statusResult.Output | Where-Object { $_ -match '\S' })
            $isDirty = $statusLines.Count -gt 0
            $summary = if ($isDirty) { "$($statusLines.Count) file(s) changed" } else { 'clean' }
            $gitStatus = [ordered]@{
                branch = $branch
                is_dirty = $isDirty
                status_summary = $summary
            }

            foreach ($line in $statusLines) {
                if ($line.Length -lt 3) { continue }
                $statusCode = $line.Substring(0, 2).Trim()
                $pathPart = $line.Substring(3).Trim()
                if ($pathPart -match '\s->\s') {
                    $pathPart = ($pathPart -split '\s->\s')[-1].Trim()
                }

                if ($statusCode -eq '??') {
                    $untrackedFiles += New-WorkspaceFileMetadata -RepoRoot $RepoRoot -RelativePath $pathPart
                } else {
                    $modifiedFiles += New-WorkspaceFileMetadata -RepoRoot $RepoRoot -RelativePath $pathPart
                }
            }
        }
    }

    if (-not $gitAvailable) {
        if ($FeatureDir -and (Test-Path $FeatureDir)) {
            $featureFiles = Get-ChildItem -Path $FeatureDir -Recurse -File -ErrorAction SilentlyContinue
            foreach ($file in $featureFiles) {
                $relativePath = $file.FullName.Replace($RepoRoot, '').TrimStart('\', '/')
                $untrackedFiles += New-WorkspaceFileMetadata -RepoRoot $RepoRoot -RelativePath $relativePath
            }
            if ($featureFiles.Count -gt 0) {
                $notes += 'Git unavailable; snapshot captured from change folder only.'
            }
        } else {
            $notes += 'Git unavailable; no feature directory available for snapshot.'
        }
    }

    return [ordered]@{
        schema_version = $Script:SnapshotSchemaVersion
        captured_at = Get-IsoTimestamp
        change_id = $ChangeId
        workspace_root = $RepoRoot
        git_available = $gitAvailable
        git_status = $gitStatus
        modified_files = @($modifiedFiles)
        untracked_files = @($untrackedFiles)
        notes = if ($notes.Count -gt 0) { ($notes -join '; ') } else { $Null }
    }
}

function Write-WorkspaceSnapshot {
    <#
    .SYNOPSIS
        Writes a workspace snapshot JSON file atomically.
    .PARAMETER Snapshot
        Snapshot hashtable to serialize.
    .PARAMETER Path
        Destination path for workspace-snapshot.json.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$Snapshot,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $content = $Snapshot | ConvertTo-Json -Depth 10
    Write-CacheFileAtomic -Path $Path -Content $content
}

function Test-HasGit {
    <#
    .SYNOPSIS
        Checks if the current directory is within a Git repository (T007 - graceful Git detection)
    .DESCRIPTION
        First checks if .git directory exists, then validates with git command.
        Returns $False gracefully without errors if Git is unavailable.
    .OUTPUTS
        Boolean - $True if in Git repo, $False otherwise
    #>

    # Validate with git command (worktree/submodule safe)
    try {
        $GitDirResult = Invoke-GitCommand -GitArgs @('rev-parse', '--git-dir') -IgnoreErrors
        if (-not $GitDirResult.Success) { return $False }

        $RootResult = Invoke-GitCommand -GitArgs @('rev-parse', '--show-toplevel') -IgnoreErrors
        return $RootResult.Success
    }
    catch {
        Write-Verbose "[speckit] Git command not available: $_"
        return $False
    }
}

function Get-SpecKitPaths {
    <#
    .SYNOPSIS
        Returns commonly used SpecKit paths for the current workspace.
    .OUTPUTS
        Hashtable of absolute paths.
    #>
    $Root = Get-WorkspaceRoot
    if (-not $Root) { return @{} }

    $SpecsDir = Join-Path $Root 'specs'
    $MemoryDir = Join-Path $SpecsDir 'memory'
    $TemplatesDir = Join-Path $SpecsDir 'templates'

    return @{
        REPO_ROOT = $Root
        SPECS_DIR = $SpecsDir
        MEMORY_DIR = $MemoryDir
        TEMPLATES_DIR = $TemplatesDir
        WORKFLOW_PATH = (Join-Path $SpecsDir 'workflows')
        PROPOSAL_PATH = (Join-Path $SpecsDir 'proposals')
        CONSTITUTION_PATH = (Join-Path $MemoryDir 'constitution.md')
        PROJECT_PATH = (Join-Path $SpecsDir 'project.md')
    }
}

function Get-CurrentBranch {
    <#
    .SYNOPSIS
        Returns the current git branch name or "none" when unavailable.
    .OUTPUTS
        String branch name.
    #>
    try {
        $Result = Invoke-GitCommand -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD') -IgnoreErrors
        if ($Result.Success -and $Result.Output) {
            return ($Result.Output | Select-Object -First 1).Trim()
        }
    }
    catch {
        # Ignore and fall back
    }

    return "none"
}

function Test-ChangeId {
    <#
    .SYNOPSIS
        Validates that a change ID matches SpecKit branch naming rules.
    .PARAMETER ChangeId
        Change ID or branch name to validate.
    .PARAMETER HasGit
        Indicates whether git validation should run.
    .OUTPUTS
        Boolean validation result.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$ChangeId,

        [switch]$HasGit = $True
    )

    if (-not $HasGit) {
        Write-Warning "[speckit] Warning: Git repository not detected; skipped branch validation"
        return $True
    }

    if ($ChangeId -notmatch '^(add|update|remove|fix|feat|refactor|[0-9]{3})[-/]') {
        Write-LogWarning "[speckit] Invalid change branch: $ChangeId"
        Write-LogInfo "[speckit] Use: add-feature-name, feat/feature-name, 001-feature-name, etc."
        return $False
    }
    return $True
}

function Test-FeatureBranch {
    <#
    .SYNOPSIS
        Validates the current feature branch naming convention.
    .PARAMETER Branch
        Branch name to validate.
    .PARAMETER HasGit
        Indicates whether git validation should run.
    .OUTPUTS
        Boolean validation result.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Branch,
        [switch]$HasGit = $True
    )
    return Test-ChangeId -ChangeId $Branch -HasGit:$HasGit
}

function Get-ChangeDir {
    <#
    .SYNOPSIS
        Resolves the directory for a given change ID.
    .PARAMETER RepoRoot
        Repository root path.
    .PARAMETER ChangeId
        Change ID to resolve.
    .OUTPUTS
        String path to the change directory.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$ChangeId
    )

    if (-not (Test-SafePathSegment -Segment $ChangeId)) {
        Write-Warning "[speckit] Invalid change ID '$ChangeId' - refusing to resolve change directory"
        return $Null
    }

    # Check in specs/changes/{id}/ first (primary location for active features)
    $ChangesFeatureDir = Join-Path $RepoRoot "specs" "changes" $ChangeId
    if (Test-Path $ChangesFeatureDir) {
        return $ChangesFeatureDir
    }

    # Check in specs/{id}/ (legacy or alternate location)
    $SpecsFeatureDir = Join-Path $RepoRoot "specs" $ChangeId
    if (Test-Path $SpecsFeatureDir) {
        return $SpecsFeatureDir
    }

    # Default to specs/changes/ for creation/compatibility
    return Join-Path $RepoRoot "specs" "changes" $ChangeId
}

function Get-FeaturePathsEnv {
    <#
    .SYNOPSIS
        Builds a standard object containing common SpecKit paths.
    .OUTPUTS
        PSCustomObject with key workspace paths and feature artifacts.
    #>
    $RepoRoot = Get-RepositoryRoot
    $ChangeId = Get-CurrentChangeId
    $HasGit = Test-HasGit
    $ChangeDir = if ($ChangeId) { Get-ChangeDir -RepoRoot $RepoRoot -ChangeId $ChangeId } else { $Null }

    $SpecsDir = Join-Path $RepoRoot "specs"
    $ChangesDir = Join-Path $SpecsDir "changes"
    $ArchiveDir = Join-Path $ChangesDir "archive"
    $MemoryDir = Join-Path $SpecsDir "memory"
    $TemplatesDir = Join-Path $SpecsDir "templates"

    [PSCustomObject]@{
        REPO_ROOT      = $RepoRoot
        CHANGE_ID      = $ChangeId
        CURRENT_BRANCH = $ChangeId
        HAS_GIT        = $HasGit

        SPECS_DIR      = $SpecsDir
        CHANGES_DIR    = $ChangesDir
        ARCHIVE_DIR    = $ArchiveDir
        TEMPLATES_DIR  = $TemplatesDir

        # Governance file paths (Issue #2 fix)
        CONSTITUTION   = Join-Path $MemoryDir "constitution.md"
        PROJECT        = Join-Path $SpecsDir "project.md"

        FEATURE_DIR    = $ChangeDir
        FEATURE_SPEC   = if ($ChangeDir) { Join-Path $ChangeDir 'spec.md' } else { $Null }
        IMPL_PLAN      = if ($ChangeDir) { Join-Path $ChangeDir 'plan.md' } else { $Null }
        TASKS          = if ($ChangeDir) { Join-Path $ChangeDir 'tasks.md' } else { $Null }
        RESEARCH       = if ($ChangeDir) { Join-Path $ChangeDir 'research.md' } else { $Null }
        DATA_MODEL     = if ($ChangeDir) { Join-Path $ChangeDir 'data-model.md' } else { $Null }
        QUICKSTART     = if ($ChangeDir) { Join-Path $ChangeDir 'quickstart.md' } else { $Null }
        CONTRACTS_DIR  = if ($ChangeDir) { Join-Path $ChangeDir 'contracts' } else { $Null }
        CHECKLISTS_DIR = if ($ChangeDir) { Join-Path $ChangeDir 'checklists' } else { $Null }
        CHECKLIST      = if ($ChangeDir) { Join-Path $ChangeDir 'checklist.md' } else { $Null }
        DELTA_SPECS    = if ($ChangeDir) { Join-Path $ChangeDir 'specs' } else { $Null }

        # Change-specific workflow paths (Issue #2 fix)
        WORKFLOW       = if ($ChangeDir) { Join-Path $ChangeDir 'workflow.md' } else { $Null }
        PROPOSAL       = if ($ChangeDir) { Join-Path $ChangeDir 'proposal.md' } else { $Null }
    }
}

# =============================================================================
# GOVERNANCE EXTRACTION FUNCTIONS (Issue #9 - Code Deduplication)
# =============================================================================
# These functions extract governance context from constitution.md and project.md
# Previously duplicated in setup-document.ps1 and update-agent-context.ps1
# =============================================================================

function Get-Principles {
    <#
    .SYNOPSIS
        Extracts Core Principles from constitution.md
    .DESCRIPTION
        Parses the Core Principles section and returns an array of principle objects
        with title and summary properties.
    .PARAMETER ConstitutionContent
        Raw content of constitution.md file
    .OUTPUTS
        Array of hashtables with 'title' and 'summary' keys
    #>
    param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$ConstitutionContent
    )

    $Principles = @()

    $CoreMatch = $Script:RegexCorePrinciplesSection.Match($ConstitutionContent)
    if ($CoreMatch.Success) {
        $PrinciplesSection = $CoreMatch.Groups[1].Value
        $Principles = $Script:RegexPrincipleEntry.Matches($PrinciplesSection) | ForEach-Object {
            @{
                title = $_.Groups[1].Value.Trim()
                summary = ($_.Groups[2].Value -split $Script:RegexNewLine | Where-Object { $_ -match '\S' } | Select-Object -First 2) -join ' '
            }
        }
    }

    return $Principles
}

function Get-TechStack {
    <#
    .SYNOPSIS
        Extracts tech stack information from project.md
    .DESCRIPTION
        Parses Frontend and Backend sections and returns a hashtable
        with frontend and backend arrays.
    .PARAMETER ProjectContent
        Raw content of project.md file
    .OUTPUTS
        Hashtable with 'frontend' and 'backend' arrays
    #>
    param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectContent
    )

    $TechStack = @{ frontend = @(); backend = @() }

    function Get-BulletsFromSection {
        param([string]$SectionContent)

        if (-not $SectionContent) { return @() }

        $Items = [regex]::Matches($SectionContent, '(?m)^\s*[-*]\s+(.+?)\s*$') | ForEach-Object {
            $_.Groups[1].Value.Trim()
        }

        # Prefer bolded label ("- **Scripting**: PowerShell") but keep full line if no bold.
        $Items = $Items | ForEach-Object {
            $Line = $_
            if ($Line -match '^\*\*([^*]+)\*\*\s*:\s*(.+)$') {
                $Label = $Matches[1].Trim()
                $Value = $Matches[2].Trim()
                if ($Value) { return "${label}: $Value" }
                return $Label
            }
            ($Line -replace '^\*\*(.+?)\*\*$', '$1').Trim()
        }

        return ($Items | Where-Object { $_ } | Select-Object -Unique)
    }

    function Add-Unique {
        param([string[]]$Target, [string[]]$Items)
        $List = @($Target)
        foreach ($Item in ($Items | Where-Object { $_ })) {
            if ($List -notcontains $Item) { $List += $Item }
        }
        return $List
    }

    # Match current hybrid/specs/project.md structure:
    # Supports: ## Tech Stack, ## Technology Stack, ## Development Tools
    $TopLevelPattern = '(?im)^##\s+(?:Tech Stack|Technology Stack|Development Tools)\s*[\r\n]+(?<section>(?s).+?)(?=\r?\n##\s|\z)'
    if ($ProjectContent -match $TopLevelPattern) {
        $TechSection = $Matches['section']

        # Explicit Frontend/Backend (future-proof)
        $SubPatterns = @{
            'frontend' = '(?im)^###\s+(?:Frontend|Frontend Tools)\s*[\r\n]+(?<sub>(?s).+?)(?=\r?\n###\s|\z)'
            'backend'  = '(?im)^###\s+(?:Backend|Tooling|Infrastructure|Development Tools|Specification Tooling)\s*[\r\n]+(?<sub>(?s).+?)(?=\r?\n###\s|\z)'
        }

        foreach ($Type in $SubPatterns.Keys) {
            $Pattern = $SubPatterns[$Type]
            $AllMatches = [regex]::Matches($TechSection, $Pattern)
            foreach ($MatchEntry in $AllMatches) {
                $SubContent = $MatchEntry.Groups['sub'].Value
                if ($Type -eq 'frontend') {
                    $TechStack.frontend = Add-Unique -Target $TechStack.frontend -Items (Get-BulletsFromSection $SubContent)
                } else {
                    $TechStack.backend = Add-Unique -Target $TechStack.backend -Items (Get-BulletsFromSection $SubContent)
                }
            }
        }

        # If we didn't find specific sub-sections but found bullets in the main section, add to backend
        if ($TechStack.frontend.Count -eq 0 -and $TechStack.backend.Count -eq 0) {
            $Bullets = Get-BulletsFromSection $TechSection
            if ($Bullets.Count -gt 0) {
                $TechStack.backend = Add-Unique -Target $TechStack.backend -Items $Bullets
            }
        }
    }

    # Extract from Markdown tables (Technical Context from plan.md)
    if ($ProjectContent -match '(?s)\| Aspect \| Value \|.*?[\r\n]+(?<table>.+?)(?=\r?\n#|\z)') {
        $TableContent = $Matches['table']
        $Rows = [regex]::Matches($TableContent, '(?m)^\s*\|\s*\*\*([^*]+)\*\*\s*\|\s*([^|]+)\s*\|')
        foreach ($Row in $Rows) {
            $Label = $Row.Groups[1].Value.Trim()
            $Value = $Row.Groups[2].Value.Trim()
            if ($Value -and $Value -ne '{e.g., ...}' -and $Value -notlike '*NEEDS RESEARCH*') {
                $Item = "${label}: $Value"
                $TechStack.backend = Add-Unique -Target $TechStack.backend -Items @($Item)
            }
        }
    }

    return $TechStack
}

function Test-ChecklistSequence {
    <#
    .SYNOPSIS
        Validates that CHK IDs in a checklist file are sequential without gaps.
    .PARAMETER Path
        Path to the checklist file.
    .OUTPUTS
        PSCustomObject with IsValid, Gaps, and FoundCount
    #>
    param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return [PSCustomObject]@{ IsValid = $True; Gaps = @(); FoundCount = 0 }
    }

    $Content = Get-Content $Path
    $Ids = @()
    foreach ($Line in $Content) {
        if ($Line -match 'CHK(\d{3})') {
            $Ids += [int]$Matches[1]
        }
    }

    if ($Ids.Count -le 1) {
        return [PSCustomObject]@{ IsValid = $True; Gaps = @(); FoundCount = $Ids.Count }
    }

    $Ids = $Ids | Sort-Object
    $Gaps = @()
    for ($Index = 0; $Index -lt ($Ids.Count - 1); $Index++) {
        if ($Ids[$Index + 1] -ne ($Ids[$Index] + 1)) {
            $Gaps += "Between CHK{0:D3} and CHK{1:D3}" -f $Ids[$Index], $Ids[$Index + 1]
        }
    }

    return [PSCustomObject]@{
        IsValid = ($Gaps.Count -eq 0)
        Gaps = $Gaps
        FoundCount = $Ids.Count
    }
}

function Get-CodeConventions {
    <#
    .SYNOPSIS
        Extracts code conventions from project.md
    .PARAMETER ProjectContent
        Raw content of project.md file
    .OUTPUTS
        Array of convention names
    #>
    param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectContent
    )

    $Conventions = @()

    $CodeStyleMatch = $Script:RegexCodeStyleSection.Match($ProjectContent)
    if ($CodeStyleMatch.Success) {
        $CodeStyleSection = $CodeStyleMatch.Groups[1].Value
        $Conventions = [regex]::Matches($CodeStyleSection, '#### ([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value.Trim() }
    }

    return $Conventions
}

function Get-ArchitecturePatterns {
    <#
    .SYNOPSIS
        Extracts architecture patterns from project.md
    .PARAMETER ProjectContent
        Raw content of project.md file
    .OUTPUTS
        Array of pattern names
    #>
    param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectContent
    )

    $Patterns = @()

    $ArchMatch = $Script:RegexArchitecturePatternsSection.Match($ProjectContent)
    if ($ArchMatch.Success) {
        $ArchSection = $ArchMatch.Groups[1].Value
        $Patterns = [regex]::Matches($ArchSection, '#### ([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value.Trim() }
    }

    return $Patterns
}

function Resolve-ConstitutionPath {
    <#
    .SYNOPSIS
        Resolves constitution.md path and returns candidate diagnostics.
    .PARAMETER RepoRoot
        Repository root for candidate resolution.
    .PARAMETER ScriptDir
        Script directory for candidate resolution.
    .OUTPUTS
        PSCustomObject with Path and Candidates.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptDir
    )

    $CandidateSpecs = @(
        @{ Label = 'Script-relative'; Path = (Join-Path $ScriptDir ".." "memory" "constitution.md") },
        @{ Label = 'Repo-relative'; Path = (Join-Path $RepoRoot "specs" "memory" "constitution.md") },
        @{ Label = 'Hybrid-relative'; Path = (Join-Path $RepoRoot "shes" "hybrid" "specs" "memory" "constitution.md") }
    )

    $Candidates = @()
    $ResolvedPath = $Null

    foreach ($Candidate in $CandidateSpecs) {
        $Resolved = Resolve-AbsolutePath $Candidate.Path
        $Exists = $False
        if ($Resolved) {
            $Exists = Test-Path $Resolved -ErrorAction SilentlyContinue
        }

        $Candidates += [PSCustomObject]@{
            Label = $Candidate.Label
            Path = $Resolved
            Exists = $Exists
        }

        if (-not $ResolvedPath -and $Exists) {
            $ResolvedPath = $Resolved
        }
    }

    return [PSCustomObject]@{
        Path = $ResolvedPath
        Candidates = $Candidates
    }
}

function Get-AllowedExtensionsFromContent {
    <#
    .SYNOPSIS
        Extracts allowed file extensions from governance content.
    .PARAMETER Content
        Raw Markdown content.
    .OUTPUTS
        String array of extensions (e.g., ".md").
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Content
    )

    $SectionMatch = [regex]::Match($Content, '(?s)##+\s+Allowed File Extensions\s*\r?\n(?<section>.+?)(?=\r?\n## |\z)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $SectionMatch.Success) {
        return @()
    }

    $Section = $SectionMatch.Groups['section'].Value
    $Matches = [regex]::Matches($Section, '(?m)^\s*[-*]\s+`?(?<ext>\.[A-Za-z0-9.]+)`?')
    $Extensions = @()
    foreach ($Match in $Matches) {
        $ExtValue = $Match.Groups['ext'].Value.Trim()
        if ($ExtValue -and $Extensions -notcontains $ExtValue) {
            $Extensions += $ExtValue
        }
    }

    return $Extensions
}

function Get-GovernanceData {
    <#
    .SYNOPSIS
        Extracts all governance data from constitution.md and project.md
    .DESCRIPTION
        Combines extraction from constitution.md (principles, quality standards, decision framework)
        and project.md (tech stack, code conventions, architecture patterns) into a single object.

        This function replaces duplicated extraction logic in setup-document.ps1 and
        update-agent-context.ps1 (Issue #9 fix).
    .PARAMETER ConstitutionPath
        Optional. Path to constitution.md. If not provided, uses default from Get-FeaturePathsEnv.
    .PARAMETER ProjectPath
        Optional. Path to project.md. If not provided, uses default from Get-FeaturePathsEnv.
    .PARAMETER NoCache
        Optional. Force fresh read, bypass cache.
    .OUTPUTS
        PSCustomObject with: Principles, TechStack, CodeConventions, ArchitecturePatterns,
        QualityStandards, DecisionFramework, HasConstitution, HasProject
    .EXAMPLE
        $Governance = Get-GovernanceData
        $Governance.Principles | ForEach-Object { Write-Host $_.title }
    #>
    param(
        [string]$ConstitutionPath,
        [string]$ProjectPath,
        [switch]$NoCache
    )

    # Get default paths if not provided
    $EnvData = Get-FeaturePathsEnv
    if (-not $ProjectPath) {
        $ProjectPath = Resolve-AbsolutePath $EnvData.PROJECT
    }

    if (-not $ConstitutionPath) {
        $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        $Resolution = Resolve-ConstitutionPath -RepoRoot $EnvData.REPO_ROOT -ScriptDir $ScriptDir
        $ConstitutionPath = $Resolution.Path

        if (-not $ConstitutionPath) {
            $CandidateReport = $Resolution.Candidates | ForEach-Object {
                "$($_.Label): $($_.Path) (exists=$($_.Exists))"
            }
            Write-Warning "[speckit] Constitution not found. Candidates:`n$($CandidateReport -join "`n")"
        }
    }

    # File-based caching with 1-hour expiration
    $CacheExpiryHours = $Script:CacheExpiryHours
    $TempDir = [System.IO.Path]::GetTempPath()
    $CacheKey = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$ConstitutionPath|$ProjectPath"))).Replace("-", "").ToLower()
    $CacheFile = Join-Path $TempDir "speckit-governance-cache-$CacheKey.json"

    $ConstitutionHash = if ($ConstitutionPath -and (Test-Path $ConstitutionPath)) { (Get-FileHash -LiteralPath $ConstitutionPath -Algorithm SHA256).Hash } else { "" }
    $ProjectHash = if ($ProjectPath -and (Test-Path $ProjectPath)) { (Get-FileHash -LiteralPath $ProjectPath -Algorithm SHA256).Hash } else { "" }

    # Check if cache is valid (exists, not expired, and files haven't changed)
    $UseCache = $False
    if (-not $NoCache -and (Test-Path $CacheFile)) {
        try {
            $CacheData = Get-Content $CacheFile -Raw | ConvertFrom-Json
            $CacheTime = [DateTime]::Parse($CacheData.Timestamp)

            # Cache is valid if:
            # 1. Less than 1 hour old
            # 2. File hashes match cached hashes
            if (([DateTime]::Now - $CacheTime).TotalHours -lt $CacheExpiryHours -and
                $CacheData.ConstitutionHash -eq $ConstitutionHash -and
                $CacheData.ProjectHash -eq $ProjectHash) {
                $UseCache = $True
            }
        } catch {
            # Invalid cache file, ignore and regenerate
        }
    }

    # Return cached data if valid
    if ($UseCache) {
        return $CacheData.Data
    }

    # Generate fresh data
    $Result = [PSCustomObject]@{
        Principles = @()
        TechStack = @{ frontend = @(); backend = @(); devtools = @() }
        CodeConventions = @()
        ArchitecturePatterns = @()
        QualityStandards = @()
        DecisionFramework = @()
        HasConstitution = $False
        HasProject = $False
        ConstitutionPath = $ConstitutionPath
        ProjectPath = $ProjectPath
        AllowedExtensions = @($Script:DefaultAllowedExtensions)
    }

    # Extract from constitution.md
    if ($ConstitutionPath -and (Test-Path $ConstitutionPath)) {
        $Result.HasConstitution = $True
        $ConstitutionContent = Get-FileContentCached -Path $ConstitutionPath -Raw

        $Result.Principles = Get-Principles -ConstitutionContent $ConstitutionContent

        # Extract Quality Standards
        $QualityMatch = $Script:RegexQualityStandardsSection.Match($ConstitutionContent)
        if ($QualityMatch.Success) {
            $QualitySection = $QualityMatch.Groups[1].Value
            $Result.QualityStandards = [regex]::Matches($QualitySection, '### ([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value.Trim() }
        }

        # Extract Decision Framework
        $DecisionMatch = $Script:RegexDecisionFrameworkSection.Match($ConstitutionContent)
        if ($DecisionMatch.Success) {
            $DecisionSection = $DecisionMatch.Groups[1].Value
            $Result.DecisionFramework = [regex]::Matches($DecisionSection, '### ([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value.Trim() }
        }

        # Extract Allowed Extensions (constitution overrides project if present)
        $ConstitutionExtensions = Get-AllowedExtensionsFromContent -Content $ConstitutionContent
        if ($ConstitutionExtensions.Count -gt 0) {
            $Result.AllowedExtensions = $ConstitutionExtensions
        }
    }

    # Extract from project.md
    if ($ProjectPath -and (Test-Path $ProjectPath)) {
        $Result.HasProject = $True
        $ProjectContent = Get-FileContentCached -Path $ProjectPath -Raw

        $Result.TechStack = Get-TechStack -ProjectContent $ProjectContent
        $Result.CodeConventions = Get-CodeConventions -ProjectContent $ProjectContent
        $Result.ArchitecturePatterns = Get-ArchitecturePatterns -ProjectContent $ProjectContent

        if (-not $Result.AllowedExtensions -or $Result.AllowedExtensions.Count -eq 0) {
            $ProjectExtensions = Get-AllowedExtensionsFromContent -Content $ProjectContent
            if ($ProjectExtensions.Count -gt 0) {
                $Result.AllowedExtensions = $ProjectExtensions
            }
        }
    }

    # Provide lower-case aliases for script consumers requiring stable keys.
    # These do not replace existing properties; they enable flexible consumption.
    try {
        $Result | Add-Member -NotePropertyName 'principles' -NotePropertyValue $Result.Principles -Force
        $Result | Add-Member -NotePropertyName 'tech_stack' -NotePropertyValue @{ frontend = @($Result.TechStack.frontend); backend = @($Result.TechStack.backend) } -Force
    } catch {
        # Non-fatal: continue without aliases
    }

    # Save to cache file
    $CacheObject = @{
        Timestamp = [DateTime]::Now.ToString("O")
        ConstitutionHash = $ConstitutionHash
        ProjectHash = $ProjectHash
        Data = $Result
    }

    try {
        $CachePayload = $CacheObject | ConvertTo-Json -Depth 10
        Write-CacheFileAtomic -Path $CacheFile -Content $CachePayload
    } catch {
        # Non-fatal: continue without caching
    }

    return $Result
}

function Get-AllowedExtensions {
    <#
    .SYNOPSIS
        Returns allowed extensions from governance data with defaults.
    #>
    param(
        [switch]$NoCache
    )

    $Governance = Get-GovernanceData -NoCache:$NoCache
    if ($Governance -and $Governance.AllowedExtensions -and $Governance.AllowedExtensions.Count -gt 0) {
        return $Governance.AllowedExtensions
    }

    return $Script:DefaultAllowedExtensions
}

# =============================================================================
# DELTA OPERATIONS (T023-T027 - 001-openspec-integration)
# =============================================================================
# Functions for detecting file changes (deltas) including renamed files
# =============================================================================

function Get-RenamedFiles {
    <#
    .SYNOPSIS
        Detects renamed files using Git rename detection (T023)
    .DESCRIPTION
        Uses `git diff -M --name-status --diff-filter=R` to detect files that were renamed.
        Returns array of objects with old and new paths, plus similarity percentage.
    .PARAMETER BaseRef
        Git ref to compare against (branch, tag, or commit). Default: "main"
    .PARAMETER FeatureDir
        Optional. Limit detection to files in this directory.
    .OUTPUTS
        PSCustomObject with Success, Renames (array), Error
    .EXAMPLE
        Get-RenamedFiles -BaseRef "main"
        Returns all renamed files compared to main branch.
    #>
    param(
        [Parameter(Position=0)]
        [string]$BaseRef,

        [string]$FeatureDir
    )

    if (-not $BaseRef) {
        $BaseRef = Get-DefaultGitBaseRef
    }

    if (-not (Test-GitRef -BaseRef $BaseRef)) {
        return [PSCustomObject]@{
            Success = $False
            Renames = @()
            Error = "Invalid git ref: $BaseRef"
        }
    }

    # Check Git availability
    if (-not (Test-HasGit)) {
        Write-Warning "[speckit] Git not available - RENAMED detection disabled"
        return [PSCustomObject]@{
            Success = $False
            Renames = @()
            Error = "Git not available"
        }
    }

    try {
        # Build git command
        $GitArgs = @("diff", "-M", "--name-status", "--diff-filter=R", $BaseRef)
        if ($FeatureDir) {
            $GitArgs += "--"
            $GitArgs += $FeatureDir
        }

        $Result = Invoke-GitCommand -GitArgs $GitArgs
        if (-not $Result.Success) {
            Write-Warning "[speckit] Git diff command failed - skipping rename detection"
            return [PSCustomObject]@{
                Success = $False
                Renames = @()
                Error = $Result.Error
            }
        }

        $Renames = @()
        foreach ($Line in $Result.Output) {
            # Parse format: R<similarity>	old/path	new/path
            if ($Line -match '^R(\d+)\s+(.+?)\s+(.+)$') {
                $Similarity = [int]$Matches[1]
                $Renames += [PSCustomObject]@{
                    OldPath = $Matches[2].Trim()
                    NewPath = $Matches[3].Trim()
                    Similarity = $Similarity
                    WasModified = ($Similarity -lt 100)
                }
            }
        }

        return [PSCustomObject]@{
            Success = $True
            Renames = $Renames
            Error = $Null
        }
    }
    catch {
        Write-Warning "[speckit] Error detecting renames: $_"
        return [PSCustomObject]@{
            Success = $False
            Renames = @()
            Error = $_.ToString()
        }
    }
}

function Get-FileSystemDeltas {
    <#
    .SYNOPSIS
        Computes file deltas using filesystem snapshots when Git is unavailable.
    .PARAMETER FeatureDir
        Directory to scan for deltas.
    .OUTPUTS
        Array of PSCustomObjects representing deltas.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$FeatureDir
    )

    $SnapshotKey = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($FeatureDir))).Replace('-', '').ToLower()
    $SnapshotPath = Join-Path ([System.IO.Path]::GetTempPath()) "speckit-filesystem-snapshot-$SnapshotKey.json"

    $CurrentFiles = @{}
    Get-ChildItem -Path $FeatureDir -Recurse -File | ForEach-Object {
        $Relative = $_.FullName.Substring($FeatureDir.Length).TrimStart('\', '/')
        $CurrentFiles[$Relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }

    $PreviousFiles = @{}
    if (Test-Path $SnapshotPath) {
        try {
            $SnapshotContent = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
            $PreviousFiles = @{}
            foreach ($Entry in $SnapshotContent.files.psobject.Properties) {
                $PreviousFiles[$Entry.Name] = $Entry.Value
            }
        } catch {
            $PreviousFiles = @{}
        }
    }

    $Deltas = @()

    foreach ($Entry in $CurrentFiles.GetEnumerator()) {
        if (-not $PreviousFiles.ContainsKey($Entry.Key)) {
            $Deltas += [PSCustomObject]@{
                Operation = 'ADDED'
                Path = (Join-Path $FeatureDir $Entry.Key)
                TargetPath = $Null
                DiffSummary = $Null
                DiffContent = $Null
                IsTrivial = $False
            }
        } elseif ($PreviousFiles[$Entry.Key] -ne $Entry.Value) {
            $Deltas += [PSCustomObject]@{
                Operation = 'MODIFIED'
                Path = (Join-Path $FeatureDir $Entry.Key)
                TargetPath = $Null
                DiffSummary = $Null
                DiffContent = $Null
                IsTrivial = $False
            }
        }
    }

    foreach ($Entry in $PreviousFiles.GetEnumerator()) {
        if (-not $CurrentFiles.ContainsKey($Entry.Key)) {
            $Deltas += [PSCustomObject]@{
                Operation = 'REMOVED'
                Path = (Join-Path $FeatureDir $Entry.Key)
                TargetPath = $Null
                DiffSummary = $Null
                DiffContent = $Null
                IsTrivial = $False
            }
        }
    }

    $SnapshotObject = @{
        timestamp = Get-IsoTimestamp
        files = $CurrentFiles
    }

    try {
        Write-CacheFileAtomic -Path $SnapshotPath -Content ($SnapshotObject | ConvertTo-Json -Depth 6)
    } catch {
        Write-Verbose "[speckit] Failed to update filesystem snapshot: $_"
    }

    return $Deltas
}

function Get-FileDeltas {
    <#
    .SYNOPSIS
        Gets all file deltas (ADDED, MODIFIED, REMOVED, RENAMED) for a feature
    .DESCRIPTION
        Comprehensive delta detection using Git. Handles all operation types
        including the combined RENAMED+MODIFIED case.
    .PARAMETER BaseRef
        Git ref to compare against. Default: "main"
    .PARAMETER FeatureDir
        Optional. Limit detection to files in this directory.
    .PARAMETER IncludeDiffContent
        Include diff content for MODIFIED files.
    .OUTPUTS
        Array of PSCustomObjects representing deltas (IsTrivial flag included)
    #>
    param(
        [Parameter(Position=0)]
        [string]$BaseRef,

        [string]$FeatureDir,

        [switch]$IncludeDiffContent
    )

    if (-not $BaseRef) {
        $BaseRef = Get-DefaultGitBaseRef
    }

    if (-not (Test-GitRef -BaseRef $BaseRef)) {
        Write-Warning "[speckit] Invalid git ref '$BaseRef' - skipping delta detection"
        return @()
    }

    if (-not (Test-HasGit)) {
        Write-Warning "[speckit] Git not available - using filesystem delta detection"
        if ($FeatureDir) {
            return Get-FileSystemDeltas -FeatureDir $FeatureDir
        }
        return @()
    }

    $Deltas = @()
    $PathFilter = if ($FeatureDir) { @("--", $FeatureDir) } else { @() }

    try {
        # Get ADDED files
        $AddedResult = Invoke-GitCommand -GitArgs (@("diff", "--name-status", "--diff-filter=A", $BaseRef) + $PathFilter)
        if (-not $AddedResult.Success) {
            Write-Warning "[speckit] Git diff failed for ADDED files"
        }

        foreach ($Line in ($AddedResult.Output | Where-Object { $_ })) {
            if ($Line -match '^A\s+(.+)$') {
                $Deltas += [PSCustomObject]@{
                    Operation = "ADDED"
                    Path = $Matches[1].Trim()
                    TargetPath = $Null
                    DiffSummary = $Null
                    DiffContent = $Null
                    IsTrivial = $False
                }
            }
        }

        # Get MODIFIED files
        $ModifiedResult = Invoke-GitCommand -GitArgs (@("diff", "--name-status", "--diff-filter=M", $BaseRef) + $PathFilter)
        if (-not $ModifiedResult.Success) {
            Write-Warning "[speckit] Git diff failed for MODIFIED files"
        }

        foreach ($Line in ($ModifiedResult.Output | Where-Object { $_ })) {
            if ($Line -match '^M\s+(.+)$') {
                $Path = $Matches[1].Trim()
                $DiffSummary = $Null
                $DiffContent = $Null
                $IsTrivial = Test-WhitespaceOnlyChange -Path $Path -BaseRef $BaseRef

                if ($IncludeDiffContent) {
                    # Get diff stats
                    $StatResult = Invoke-GitCommand -GitArgs @('diff', '--stat', $BaseRef, '--', $Path) -IgnoreErrors
                    $StatLine = $StatResult.Output | Select-Object -Last 1
                    if ($StatLine -match '(\d+)\s+insertion.*?(\d+)\s+deletion') {
                        $DiffSummary = "$($Matches[1]) insertions, $($Matches[2]) deletions"
                    } elseif ($StatLine -match '(\d+)\s+insertion') {
                        $DiffSummary = "$($Matches[1]) insertions, 0 deletions"
                    } elseif ($StatLine -match '(\d+)\s+deletion') {
                        $DiffSummary = "0 insertions, $($Matches[1]) deletions"
                    }

                    if ($IsTrivial) {
                        $DiffSummary = "$DiffSummary [TRIVIAL: whitespace-only]"
                    }

                    # Get diff content (first 10 lines)
                    $DiffResult = Invoke-GitCommand -GitArgs @('diff', '-U3', $BaseRef, '--', $Path) -IgnoreErrors
                    $Diff = $DiffResult.Output | Select-Object -First 15
                    $DiffContent = $Diff -join "`n"
                }

                $Deltas += [PSCustomObject]@{
                    Operation = "MODIFIED"
                    Path = $Path
                    TargetPath = $Null
                    DiffSummary = $DiffSummary
                    DiffContent = $DiffContent
                    IsTrivial = $IsTrivial
                }
            }
        }

        # Get REMOVED files
        $RemovedResult = Invoke-GitCommand -GitArgs (@("diff", "--name-status", "--diff-filter=D", $BaseRef) + $PathFilter)
        if (-not $RemovedResult.Success) {
            Write-Warning "[speckit] Git diff failed for REMOVED files"
        }

        foreach ($Line in ($RemovedResult.Output | Where-Object { $_ })) {
            if ($Line -match '^D\s+(.+)$') {
                $Deltas += [PSCustomObject]@{
                    Operation = "REMOVED"
                    Path = $Matches[1].Trim()
                    TargetPath = $Null
                    DiffSummary = $Null
                    DiffContent = $Null
                    IsTrivial = $False
                }
            }
        }

        # Get RENAMED files (includes RENAMED+MODIFIED handling)
        $RenamesResult = Get-RenamedFiles -BaseRef $BaseRef -FeatureDir $FeatureDir
        if (-not $RenamesResult.Success -and $RenamesResult.Error) {
            Write-Warning "[speckit] Rename detection failed: $($RenamesResult.Error)"
        }

        foreach ($Rename in $RenamesResult.Renames) {
            # Add RENAMED entry
            $Deltas += [PSCustomObject]@{
                Operation = "RENAMED"
                Path = $Rename.OldPath
                TargetPath = $Rename.NewPath
                DiffSummary = $Null
                DiffContent = $Null
                IsTrivial = $False
            }

            # If file was also modified (similarity < 100), add MODIFIED entry
            if ($Rename.WasModified -and $IncludeDiffContent) {
                $StatResult = Invoke-GitCommand -GitArgs @('diff', '--stat', $BaseRef, '--', $Rename.NewPath) -IgnoreErrors
                $Stat = $StatResult.Output | Select-Object -Last 1
                $DiffSummary = $Null
                if ($Stat -match '(\d+)\s+insertion.*?(\d+)\s+deletion') {
                    $DiffSummary = "$($Matches[1]) insertions, $($Matches[2]) deletions"
                }

                $IsTrivial = Test-WhitespaceOnlyChange -Path $Rename.NewPath -BaseRef $BaseRef
                if ($IsTrivial) {
                    $DiffSummary = "$DiffSummary [TRIVIAL: whitespace-only]"
                }

                $Deltas += [PSCustomObject]@{
                    Operation = "MODIFIED"
                    Path = $Rename.NewPath
                    TargetPath = $Null
                    DiffSummary = $DiffSummary
                    DiffContent = $Null
                    IsTrivial = $IsTrivial
                }
            }
        }

    }
    catch {
        Write-Warning "[speckit] Error detecting deltas: $_"
    }

    return $Deltas
}

function Format-DeltaMarkdown {
    <#
    .SYNOPSIS
        Formats delta entries as Markdown list items
    .PARAMETER Deltas
        Array of delta objects from Get-FileDeltas
    .OUTPUTS
        String array of formatted Markdown lines
    #>
    param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [ValidateNotNullOrEmpty()]
        [array]$Deltas
    )

    $Lines = @()
    foreach ($Delta in $Deltas) {
        switch ($Delta.Operation) {
            "ADDED" {
                $Lines += "- **ADDED**: $($Delta.Path)"
            }
            "MODIFIED" {
                $TrivialTag = if ($Delta.IsTrivial) { " [TRIVIAL: whitespace-only]" } else { "" }
                if ($Delta.DiffSummary) {
                    $Lines += "- **MODIFIED**: $($Delta.Path) ($($Delta.DiffSummary))$TrivialTag"
                } else {
                    $Lines += "- **MODIFIED**: $($Delta.Path)$TrivialTag"
                }
            }
            "REMOVED" {
                $Lines += "- **REMOVED**: $($Delta.Path)"
            }
            "RENAMED" {
                # Use Unicode right arrow (→)
                $Lines += "- **RENAMED**: $($Delta.Path) → $($Delta.TargetPath)"
            }
        }
    }

    return $Lines
}
function Test-WhitespaceOnlyChange {
    <#
    .SYNOPSIS
        Detects if a file change is whitespace-only (trivial change)
    .DESCRIPTION
        Uses git diff with ignore whitespace options to detect trivial changes.
        A change is trivial if:
        - Only whitespace (spaces, tabs, newlines) was modified
        - No actual content was changed
    .PARAMETER Path
        File path to check
    .PARAMETER BaseRef
        Git ref to compare against. Default: "main"
    .OUTPUTS
        Boolean - $True if change is whitespace-only (trivial)
    #>
    param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [string]$BaseRef
    )

    if (-not $BaseRef) {
        $BaseRef = Get-DefaultGitBaseRef
    }

    if (-not (Test-GitRef -BaseRef $BaseRef)) {
        return $False
    }

    if (-not (Test-HasGit)) {
        return $False
    }

    try {
        # Compare with and without ignore-space option
        # If -w produces no diff but regular diff does, it's whitespace-only
        $NormalResult = Invoke-GitCommand -GitArgs @('diff', $BaseRef, '--', $Path) -IgnoreErrors
        $WhitespaceResult = Invoke-GitCommand -GitArgs @('diff', '-w', $BaseRef, '--', $Path) -IgnoreErrors

        if (-not $NormalResult.Success -or -not $WhitespaceResult.Success) {
            return $False
        }

        $NormalDiff = $NormalResult.Output
        $NoWhitespaceDiff = $WhitespaceResult.Output

        # Has changes AND they disappear when ignoring whitespace = whitespace-only
        $HasChanges = $NormalDiff -and $NormalDiff.Length -gt 0
        $ChangesAreWhitespaceOnly = (-not $NoWhitespaceDiff) -or ($NoWhitespaceDiff.Length -eq 0)

        return ($HasChanges -and $ChangesAreWhitespaceOnly)
    }
    catch {
        Write-Verbose "[speckit] Error checking whitespace changes: $_"
        return $False
    }
}

