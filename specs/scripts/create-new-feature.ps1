#!/usr/bin/env pwsh
# Create a new feature for SpecKit Consolidated
# Updated paths for consolidated folder structure (specs/changes/)
#
# CORRECTED VERSION - Fixes from 2ndanalysis.md Issue #3
# Added error handling, rollback logic, and eliminated code duplication
#
# Changes made:
# - Added try-catch blocks around all critical operations
# - Added rollback logic for failed spec creation
# - Removed duplicate root detection logic (now sources from common.ps1 via Get-RepositoryRoot)
# - Added -ErrorAction Stop to all New-Item and Copy-Item calls
# - Added cleanup of branch if directory creation fails
# - Added validation before setting environment variables
# - Added better error messages for debugging
#
# EXIT CODES:
#   0 - Success (feature created)
#   1 - Error (validation failed, directory creation failed, or rollback occurred)

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $True, Position = 0)]
    [string[]]$FeatureDescription,

    [switch]$Json,
    [string]$ShortName,
    [int]$Number = 0,
    [switch]$Help
)
$ErrorActionPreference = 'Stop'
$ExitCodes = @{ Success = 0; Validation = 1; Operation = 2 }

function Write-JsonFallback {
    <#
    .SYNOPSIS
        Writes a minimal JSON payload when common.ps1 is unavailable.
    .PARAMETER Status
        Result status string.
    .PARAMETER Message
        Error message to include.
    .PARAMETER Data
        Structured data payload.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Status,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$Data
    )

    $Payload = @{
        status = $Status
        timestamp = (Get-Date -Format 'o')
        script = 'create-new-feature.ps1'
        data = $Data
        errors = @($Message)
        warnings = @()
    }

    $JsonPayload = $Payload | ConvertTo-Json -Depth 6 -Compress
    $Schema = @'
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

    $SchemaValid = $True
    try {
        $SchemaValid = Test-Json -Json $JsonPayload -Schema $Schema
    } catch {
        $SchemaValid = $False
    }
    if (-not $SchemaValid) {
        Write-Warning "[speckit] JSON output failed schema validation"
    }

    Write-Output $JsonPayload
}

# Show help if requested
if ($Help) {
    Write-Host "Usage: ./create-new-feature.ps1 [-Json] [-ShortName <name>] [-Number N] <feature description>"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Json               Output in JSON format"
    Write-Host "  -ShortName <name>   Provide a custom short name (2-4 words) for the branch"
    Write-Host "  -Number N           Specify branch number manually (overrides auto-detection)"
    Write-Host "  -Help               Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ./create-new-feature.ps1 'Add user authentication system' -ShortName 'user-auth'"
    Write-Host "  ./create-new-feature.ps1 'Implement OAuth2 integration for API'"
    exit 0
}

# Feature description validation is performed after common.ps1 is loaded.

# NEW: Source common.ps1 for shared functions
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CommonScript = Join-Path $ScriptDir "common.ps1"

if (-not (Test-Path $CommonScript)) {
    if ($Json) {
        Write-JsonFallback -Status "operation_error" -Message "Required file not found: $CommonScript" -Data @{ common_path = $CommonScript }
    } else {
        Write-Error "Required file not found: $CommonScript"
    }
    exit $ExitCodes.Operation
}

try {
    . $CommonScript
} catch {
    $LoadError = $_.Exception
    if ($Json) {
        Write-JsonFallback -Status "operation_error" -Message "Failed to source common.ps1 from '$CommonScript': $($LoadError.Message)" -Data @{ common_path = $CommonScript }
    } else {
        Write-Error "Failed to source common.ps1 from '$CommonScript'. Ensure the SpecKit scripts directory is intact. Error: $($LoadError.Message)"
    }
    exit $ExitCodes.Operation
}

$ExitCodes = Get-ExitCodes
Set-StrictErrorActionPreference | Out-Null
$Constants = Get-SpeckitConstants

$Script:AuditRun = New-WorkflowScriptRunMetadata -ScriptName 'create-new-feature.ps1'
$Script:AuditContext = @{
    script_name = 'create-new-feature.ps1'
    action = 'create'
    change_id = $Null
    run_id = $Script:AuditRun.run_id
}
$Script:AuditStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Check if feature description provided
if (-not $FeatureDescription -or $FeatureDescription.Count -eq 0) {
    $ErrorDetails = @{
        error = "Feature description required"
        context = "create-new-feature requires a feature description to build branch name"
        suggestion = "Provide a feature description: ./create-new-feature.ps1 'Add user auth'"
    }
    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'failure' -ErrorRecord 'Feature description required' `
        -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null
    if ($Json) {
        Write-JsonResult -Result (New-JsonResult -Status "validation_error" -ScriptName "create-new-feature.ps1" -Data $ErrorDetails -Errors @("Feature description required") )
    } else {
        Write-Error "Usage: ./create-new-feature.ps1 [-Json] [-ShortName <name>] <feature description>"
    }
    exit $ExitCodes.Validation
}

$FeatureDesc = ($FeatureDescription -join ' ').Trim()

function Exit-WithError {
    <#
    .SYNOPSIS
        Writes a standardized error payload and exits.
    .PARAMETER Status
        Status string for JSON output.
    .PARAMETER Message
        Error message.
    .PARAMETER Data
        Structured data payload.
    .PARAMETER ExitCode
        Exit code to return.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Status,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$Data,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [int]$ExitCode
    )

    if ($Json) {
        Write-JsonResult -Result (New-JsonResult -Status $Status -ScriptName "create-new-feature.ps1" -Data $Data -Errors @($Message))
    } else {
        Write-Error $Message
    }

    if ($BranchName) {
        $Script:AuditContext.change_id = $BranchName
    }
    Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'failure' -ErrorRecord $Message `
        -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null

    exit $ExitCode
}

# NEW: Use Get-RepositoryRoot from common.ps1 instead of duplicate logic
try {
    $RepoRoot = Get-RepositoryRoot
    if (-not $RepoRoot) {
        throw "Could not determine repository root"
    }
}
catch {
    Exit-WithError -Status "operation_error" -Message "Error: Could not determine repository root. Error: $_" -Data @{ context = "repository root detection" } -ExitCode $ExitCodes.Operation
}

# NEW: Use Test-HasGit from common.ps1
$HasGit = Test-HasGit

Set-Location $RepoRoot

$SpecsDir = Join-Path $RepoRoot 'specs'
$ChangesDir = Join-Path $SpecsDir 'changes'

try {
    New-Item -ItemType Directory -Path $ChangesDir -Force -ErrorAction Stop | Out-Null
}
catch {
    Exit-WithError -Status "operation_error" -Message "Failed to create changes directory: $ChangesDir. Error: $_" -Data @{ changes_dir = $ChangesDir } -ExitCode $ExitCodes.Operation
}

function Get-HighestNumberFromSpecs {
    <#
    .SYNOPSIS
        Determines the highest numeric prefix in specs directories.
    .PARAMETER SpecsDir
        Path to scan.
    .OUTPUTS
        Integer maximum value found.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$SpecsDir
    )

    $Highest = 0
    if (Test-Path $SpecsDir) {
        Get-ChildItem -Path $SpecsDir -Directory | ForEach-Object {
            if ($_.Name -match '^(\d+)') {
                $Num = [int]$Matches[1]
                if ($Num -gt $Highest) { $Highest = $Num }
            }
        }
    }
    return $Highest
}

function Get-HighestNumberFromBranches {
    <#
    .SYNOPSIS
        Determines the highest numeric prefix across git branches.
    .OUTPUTS
        Integer maximum value found.
    #>
    param()

    $Highest = 0
    try {
        $BranchesResult = Invoke-GitCommand -GitArgs @('branch', '-a') -IgnoreErrors
        if ($BranchesResult.Success) {
            foreach ($Branch in $BranchesResult.Output) {
                $CleanBranch = $Branch.Trim() -replace '^\*?\s+', '' -replace '^remotes/[^/]+/', ''
                # Updated regex to match numbers anywhere in branch name (Issue #29)
                # Matches digit sequences separated by delimiters or at string boundaries
                if ($CleanBranch -match '(?:^|[/-])(\d+)(?:[/-]|$)') {
                    $Num = [int]$Matches[1]
                    if ($Num -gt $Highest) { $Highest = $Num }
                }
            }
        }
    }
    catch {
        Write-Verbose "Could not check Git branches: $_"
    }
    return $Highest
}

function Get-NextBranchNumber {
    <#
    .SYNOPSIS
        Determines the next available numeric branch prefix.
    .PARAMETER RepoRoot
        Repository root path.
    .OUTPUTS
        Integer next branch number.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot
    )

    try {
        Invoke-GitCommand -GitArgs @('fetch', '--all', '--prune') -IgnoreErrors | Out-Null
    }
    catch { }

    $HighestBranch = Get-HighestNumberFromBranches
    $HighestSpec = [Math]::Max(
        (Get-HighestNumberFromSpecs -SpecsDir (Join-Path $RepoRoot "specs")),
        (Get-HighestNumberFromSpecs -SpecsDir (Join-Path $RepoRoot "specs" "changes"))
    )

    $MaxNum = [Math]::Max($HighestBranch, $HighestSpec)
    return $MaxNum + 1
}

function ConvertTo-CleanBranchName {
    <#
    .SYNOPSIS
        Normalizes a branch name to kebab-case.
    .PARAMETER Name
        Input name to normalize.
    .OUTPUTS
        Normalized branch name string.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    return $Name.ToLower() -replace '[^a-z0-9]', '-' -replace '-{2,}', '-' -replace '^-', '' -replace '-$', ''
}

function Get-BranchName {
    <#
    .SYNOPSIS
        Builds a branch name from a feature description.
    .PARAMETER Description
        Feature description text.
    .OUTPUTS
        Generated branch name string.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Description
    )

    $StopWords = @(
        'i', 'a', 'an', 'the', 'to', 'for', 'of', 'in', 'on', 'at', 'by', 'with', 'from',
        'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
        'do', 'does', 'did', 'will', 'would', 'should', 'could', 'can', 'may', 'might', 'must', 'shall',
        'this', 'that', 'these', 'those', 'my', 'your', 'our', 'their',
        'want', 'need', 'add', 'get', 'set'
    )

    $CleanName = $Description.ToLower() -replace '[^a-z0-9\s]', ' '
    $Words = $CleanName -split '\s+' | Where-Object { $_ }

    $MeaningfulWords = @()
    foreach ($Word in $Words) {
        if ($StopWords -contains $Word) { continue }
        if ($Word.Length -ge 3) {
            $MeaningfulWords += $Word
        }
        elseif ($Description -match "\b$($Word.ToUpper())\b") {
            $MeaningfulWords += $Word
        }
    }

    if ($MeaningfulWords.Count -gt 0) {
        $MaxWords = if ($MeaningfulWords.Count -eq 4) { 4 } else { 3 }
        $Result = ($MeaningfulWords | Select-Object -First $MaxWords) -join '-'
        return $Result
    }
    else {
        $Result = ConvertTo-CleanBranchName -Name $Description
        $FallbackWords = ($Result -split '-') | Where-Object { $_ } | Select-Object -First 3
        return [string]::Join('-', $FallbackWords)
    }
}

# Generate branch name
if ($ShortName) {
    $BranchSuffix = ConvertTo-CleanBranchName -Name $ShortName
}
else {
    $BranchSuffix = Get-BranchName -Description $FeatureDesc
}

# Determine branch number
if ($Number -eq 0) {
    if ($HasGit) {
        $Number = Get-NextBranchNumber -RepoRoot $RepoRoot
    }
    else {
        $Number = (Get-HighestNumberFromSpecs -SpecsDir $ChangesDir) + 1
    }
}

$FeatureNum = ('{0:000}' -f $Number)
$BranchName = "$FeatureNum-$BranchSuffix"

if (-not (Test-SafePathSegment -Segment $BranchName)) {
    Exit-WithError -Status "validation_error" -Message "Generated branch name is invalid for paths: $BranchName" -Data @{ branch_name = $BranchName } -ExitCode $ExitCodes.Validation
}

# Validate branch name length
$MaxBranchLength = $Constants.MaxBranchNameLength
if ($BranchName.Length -gt $MaxBranchLength) {
    $MaxSuffixLength = $MaxBranchLength - 4
    $TruncatedSuffix = $BranchSuffix.Substring(0, [Math]::Min($BranchSuffix.Length, $MaxSuffixLength))
    $TruncatedSuffix = $TruncatedSuffix -replace '-$', ''
    $OriginalBranchName = $BranchName
    $BranchName = "$FeatureNum-$TruncatedSuffix"
    Write-Warning "[speckit] Branch name exceeded 244-byte limit, truncated to: $BranchName"
}

# NEW: Track if branch was created for rollback purposes
$BranchCreated = $False
$FeatureDir = Join-Path $ChangesDir $BranchName
$Tracker = New-OperationTracker

# NEW: Create branch with proper error handling
if ($HasGit) {
    try {
        # Check if branch already exists
        $ExistingBranch = Invoke-GitCommand -GitArgs @('rev-parse', '--verify', $BranchName) -IgnoreErrors
        if ($ExistingBranch.Success) {
            Exit-WithError -Status "validation_error" -Message "Branch '$BranchName' already exists. Please choose a different name or number." -Data @{ branch_name = $BranchName } -ExitCode $ExitCodes.Validation
        }

        $CheckoutResult = Invoke-GitCommand -GitArgs @('checkout', '-b', $BranchName)
        if (-not $CheckoutResult.Success) {
            throw "Git checkout failed: $($CheckoutResult.Error)"
        }
        $BranchCreated = $True
        Write-Verbose "Created git branch: $BranchName"
    }
    catch {
        Exit-WithError -Status "operation_error" -Message "Failed to create git branch '$BranchName': $_" -Data @{ branch_name = $BranchName } -ExitCode $ExitCodes.Operation
    }
}
else {
    Write-Warning "[speckit] Warning: Git repository not detected; skipped branch creation for $BranchName"
}

# NEW: Create feature directory with rollback on failure
try {
    if (Test-Path $FeatureDir) {
        throw "Feature directory already exists: $FeatureDir"
    }

    New-Item -ItemType Directory -Path $FeatureDir -Force -ErrorAction Stop | Out-Null
    Add-TrackedDirectory -Tracker $Tracker -Path $FeatureDir
    Write-Verbose "Created feature directory: $FeatureDir"
}
catch {
    Invoke-TrackedRollback -Tracker $Tracker

    # NEW: Rollback - delete branch if it was created
    if ($BranchCreated -and $HasGit) {
        Write-Warning "Rolling back: deleting branch '$BranchName'..."
        try {
            $BaseBranch = Get-DefaultGitBaseRef
            Invoke-GitCommand -GitArgs @('checkout', $BaseBranch) -IgnoreErrors | Out-Null
            Invoke-GitCommand -GitArgs @('branch', '-D', $BranchName) -IgnoreErrors | Out-Null
            Write-Host "Branch '$BranchName' deleted." -ForegroundColor Yellow
        }
        catch {
            Write-Warning "Could not delete branch '$BranchName'. Manual cleanup may be required."
        }
    }

    Exit-WithError -Status "operation_error" -Message "Failed to create feature directory: $FeatureDir. Error: $_" -Data @{ feature_dir = $FeatureDir; branch_name = $BranchName } -ExitCode $ExitCodes.Operation
}

# NEW: Copy template with error handling and rollback
$Template = Join-Path $SpecsDir 'templates' 'spec-template.md'
$SpecFile = Join-Path $FeatureDir 'spec.md'

try {
    if (Test-Path $Template) {
        Copy-ItemAtomic -Source $Template -Destination $SpecFile
        Add-TrackedFile -Tracker $Tracker -Path $SpecFile
        Write-Verbose "Copied template to: $SpecFile"

        # Replace header metadata placeholders only; content placeholders filled by AI agents
        if (Test-Path $SpecFile) {
            $SpecContent = Get-Content $SpecFile -Raw -Encoding UTF8

            # Derive values for placeholder replacement
            $CreatedDate = Get-StandardDate
            $IssueNumber = $FeatureNum  # Already formatted as "001", "002", etc.
            $FeatureName = $BranchSuffix
            $FeatureDescription = if ($ShortName) { $ShortName } else { $FeatureDesc }

            # Replace only valid header placeholders (escape special regex chars in replacement)
            $EscapedFeatureDesc = $FeatureDescription -replace '\$', '$$'
            $EscapedFeatureName = $FeatureName -replace '\$', '$$'
            $EscapedOriginalRequest = $FeatureDesc -replace '\$', '$$'

            # Header metadata replacements (5 valid placeholders)
            $SpecContent = $SpecContent -replace '\{FEATURE_NAME\}', $EscapedFeatureDesc
            $SpecContent = $SpecContent -replace '\{FEATURE-NAME\}', $EscapedFeatureName
            $SpecContent = $SpecContent -replace '\{ISSUE_NUMBER\}', $IssueNumber
            $SpecContent = $SpecContent -replace '\{ISSUE-NUMBER\}', $IssueNumber
            $SpecContent = $SpecContent -replace '\{YYYY_MM_DD\}', $CreatedDate
            $SpecContent = $SpecContent -replace '\{YYYY-MM-DD\}', $CreatedDate
            $SpecContent = $SpecContent -replace '\{ORIGINAL_USER_REQUEST\}', $EscapedOriginalRequest

            # Optional: Replace STORY_TITLE with feature description for convenience
            $SpecContent = $SpecContent -replace '\{STORY_TITLE\}', $EscapedFeatureDesc

            Set-Content -Path $SpecFile -Value $SpecContent -Encoding UTF8 -NoNewline
            Write-Verbose "Replaced header metadata placeholders in spec file"
        }
    }
    else {
        Write-Warning "Template not found: $Template. Creating empty spec file."
        New-Item -ItemType File -Path $SpecFile -ErrorAction Stop | Out-Null
        Add-TrackedFile -Tracker $Tracker -Path $SpecFile
    }
}
catch {
    # NEW: Rollback - delete directory and branch
    Write-Warning "Rolling back: cleaning up feature directory and branch..."

    Invoke-TrackedRollback -Tracker $Tracker

    if ($BranchCreated -and $HasGit) {
        try {
            $BaseBranch = Get-DefaultGitBaseRef
            Invoke-GitCommand -GitArgs @('checkout', $BaseBranch) -IgnoreErrors | Out-Null
            Invoke-GitCommand -GitArgs @('branch', '-D', $BranchName) -IgnoreErrors | Out-Null
            Write-Host "Branch '$BranchName' deleted." -ForegroundColor Yellow
        }
        catch {
            Write-Warning "Could not delete branch '$BranchName'. Manual cleanup may be required."
        }
    }

    Exit-WithError -Status "operation_error" -Message "Failed to create spec file: $SpecFile. Error: $_" -Data @{ spec_file = $SpecFile; branch_name = $BranchName } -ExitCode $ExitCodes.Operation
}

# NEW: Validate before setting environment variables
if (-not (Test-Path $SpecFile)) {
    Exit-WithError -Status "operation_error" -Message "Spec file was not created successfully: $SpecFile" -Data @{ spec_file = $SpecFile } -ExitCode $ExitCodes.Operation
}

# NEW (T060): Update project.md with new feature entry
$PopulateScript = Join-Path $ScriptDir "populate-project.ps1"
if (Test-Path $PopulateScript) {
    try {
        & $PopulateScript -Action add -FeatureBranch $BranchName -ErrorAction SilentlyContinue
        Write-Verbose "Updated project.md with new feature entry"
    } catch {
        Write-Verbose "Could not update project.md: $_"
        # Non-fatal - continue with feature creation
    }
} else {
    Write-Verbose "populate-project.ps1 not found - skipping project.md update"
}

# Set environment variable for the current session
$Env:SPECIFY_CHANGE_ID = $BranchName

if ($Json) {
    $Obj = @{
        branch_name = $BranchName
        spec_file   = $SpecFile
        feature_num = $FeatureNum
        feature_dir = $FeatureDir
        has_git     = $HasGit
    }
    Write-JsonResult -Result (New-JsonResult -Status "success" -ScriptName "create-new-feature.ps1" -Data $Obj)
}
else {
    Write-Output "BRANCH_NAME: $BranchName"
    Write-Output "SPEC_FILE: $SpecFile"
    Write-Output "FEATURE_DIR: $FeatureDir"
    Write-Output "FEATURE_NUM: $FeatureNum"
    Write-Output "HAS_GIT: $HasGit"
    Write-Output "SPECIFY_CHANGE_ID environment variable set to: $BranchName"
}

$Script:AuditContext.change_id = $BranchName
Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome 'success' `
    -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds) | Out-Null

exit $ExitCodes.Success

