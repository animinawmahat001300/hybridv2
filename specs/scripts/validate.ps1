#!/usr/bin/env pwsh

<#
.SYNOPSIS
Validates SpecKit specifications against formatting and quality rules.

.DESCRIPTION
The validate.ps1 script checks specification files for compliance with SpecKit
standards. It validates requirements, scenarios, naming conventions, and when
-Strict is used, enforces full constitution compliance.

.PARAMETER Target
Optional. Specifies the target to validate:
- A specific file path (e.g., "specs/changes/001-feature/spec.md")
- A change ID (e.g., "001-feature")
- If omitted, validates the current feature context

.PARAMETER Strict
Enables strict validation mode. When set, validates against ALL constitution
requirements including:
- Core Principles (Spec-First Development, File-Based Truth, etc.)
- Quality Standards (required sections, scenarios, formatting)
- Documentation Quality (heading levels, link styles)
Violations result in ERRORS (not warnings) and fail the validation.

.PARAMETER Json
Outputs validation results in JSON format for CI/CD integration.

.PARAMETER Help
Displays this help message.

.EXAMPLE
.\validate.ps1
Validates the current feature context using standard rules.

.EXAMPLE
.\validate.ps1 -Target "001-new-feature"
Validates the specified change by ID.

.EXAMPLE
.\validate.ps1 -Target "specs/changes/001-feature/spec.md"
Validates a specific spec file.

.EXAMPLE
.\validate.ps1 -Strict
Validates with full constitution compliance checking.

.EXAMPLE
.\validate.ps1 -Strict -Json
Validates in strict mode and outputs JSON for automation.

.NOTES
File: validate.ps1
Author: SpecKit Consolidated
Requires: PowerShell 7+
See: specs/memory/constitution.md for validation rules
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Target,

    [switch]$Strict,

    [switch]$IncludeGates,

    [switch]$Json,

    [switch]$Help
)

# Show help if requested
if ($Help) {
    @"

SYNOPSIS
    Validates SpecKit specifications against formatting and quality rules.

DESCRIPTION
    The validate.ps1 script checks specification files for compliance with SpecKit
    standards. It validates requirements, scenarios, naming conventions, and when
    -Strict is used, enforces full constitution compliance.

PARAMETERS
    -Target <string>
        Optional. Specifies the target to validate:
        - A specific file path (e.g., "specs/changes/001-feature/spec.md")
        - A change ID (e.g., "001-feature")
        - If omitted, validates the current feature context

    -Strict
        Enables strict validation mode. When set, validates against ALL constitution
        requirements including:
        - Core Principles (Spec-First Development, File-Based Truth, etc.)
        - Quality Standards (required sections, scenarios, formatting)
        - Documentation Quality (heading levels, link styles)
        Violations result in ERRORS (not warnings) and fail the validation.

    -IncludeGates
        Includes gate validation checks as part of validation:
        - Gate 1 (Clarify): No [NEEDS CLARIFICATION] markers in spec.md
        - Gate 2 (Implement): All checklist items completed
        - Gate 3 (Archive): No uncommitted changes in feature directory

    -Json
        Outputs validation results in JSON format for CI/CD integration.

    -Help
        Displays this help message.

EXAMPLES
    .\validate.ps1
        Validates the current feature context using standard rules.

    .\validate.ps1 -Target "001-new-feature"
        Validates the specified change by ID.

    .\validate.ps1 -Target "specs/changes/001-feature/spec.md"
        Validates a specific spec file.

    .\validate.ps1 -Strict
        Validates with full constitution compliance checking.

    .\validate.ps1 -Strict -Json
        Validates in strict mode and outputs JSON for automation.

    .\validate.ps1 -IncludeGates
        Validates and runs gate checks (Clarify, Implement, Archive).

    .\validate.ps1 -Strict -IncludeGates -Json
        Full validation with gates in JSON format for CI/CD.

NOTES
    File: validate.ps1
    Author: SpecKit Consolidated
    Requires: PowerShell 7+
    See: specs/memory/constitution.md for validation rules

"@
    exit $ExitCodes.Success
}

$ErrorActionPreference = 'Stop'
$ExitCodes = @{ Success = 0; Validation = 1; Operation = 2 }

$Script:DeltaReqIdLookaheadLines = 5
$Script:DeltaRemovedReasonLookaheadLines = 10
$Script:RequirementNormativeLookaheadLines = 10

# Source common functions
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { $ScriptDir = Get-Location }

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

$EnvData = Get-FeaturePathsEnv

# Use detected REPO_ROOT from common.ps1, with fallback to current directory only if needed
$RepoRoot = $EnvData.REPO_ROOT
if (-not $RepoRoot -or -not (Test-Path $RepoRoot)) {
    if (Test-Path (Join-Path (Get-Location).Path "specs")) {
        $RepoRoot = (Get-Location).Path
    }
}

if (-not $RepoRoot) {
    Write-Error "Could not detect SpecKit workspace root."
    exit $ExitCodes.Operation
}

# Standardize REPO_ROOT as an absolute path
$RepoRoot = (Resolve-Path $RepoRoot).Path

$AuditChangeId = $Null
if ($Target) {
    if ($Target -match 'specs[\\/]+changes[\\/]+([^\\/]+)') {
        $AuditChangeId = $Matches[1]
    } elseif ($Target -match '^\d{3}-.+') {
        $AuditChangeId = $Target
    }
}

if (-not $AuditChangeId) {
    $AuditChangeId = Get-CurrentChangeId
}

$Script:AuditRun = New-WorkflowScriptRunMetadata -ScriptName 'validate.ps1'
$Script:AuditContext = @{
    script_name = 'validate.ps1'
    action = 'validate'
    change_id = $AuditChangeId
    run_id = $Script:AuditRun.run_id
}
$Script:AuditStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Write-ValidationAuditEntry {
    <#
    .SYNOPSIS
        Writes a workflow audit entry and warns on append-only failures.
    .PARAMETER Outcome
        Outcome for the audit entry (success/failure).
    .PARAMETER ErrorRecord
        Optional error record or message to sanitize for failure entries.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateSet('success', 'failure')]
        [string]$Outcome,

        $ErrorRecord
    )

    $result = Write-WorkflowAuditEntry -Context $Script:AuditContext -Outcome $Outcome -ErrorRecord $ErrorRecord `
        -DurationMs ([int]$Script:AuditStopwatch.ElapsedMilliseconds)

    if (-not $result.Success) {
        Write-Warning "[speckit] Audit log append failed: $($result.Error)"
    }
}

# Constitution rules (loaded in -Strict mode)
$ConstitutionRules = $Null

function Import-ConstitutionRules {
    <#
    .SYNOPSIS
        Parses constitution.md and extracts validation rules.
    #>
    $Resolution = Resolve-ConstitutionPath -RepoRoot $RepoRoot -ScriptDir $ScriptDir
    $ConstitutionPath = $Resolution.Path

    if (-not $ConstitutionPath) {
        $CandidateReport = $Resolution.Candidates | ForEach-Object {
            "$($_.Label): $($_.Path) (exists=$($_.Exists))"
        }
        Write-Warning "Constitution not found. Candidates:`n$($CandidateReport -join "`n")"
        return @{}
    }

    Write-Verbose "Loading constitution from: $ConstitutionPath"
    $Content = Get-FileContentCached -Path $ConstitutionPath -Raw
    $Lines = Get-FileContentCached -Path $ConstitutionPath
    $Rules = @{
        CorePrinciples = @()
        QualityStandards = @()
        RequiredSections = @()
    }

    # Extract Core Principles by parsing lines
    $InCoreSection = $False
    foreach ($Line in $Lines) {
        if ($Line -match '^## Core Principles\s*$') {
            $InCoreSection = $True
            continue
        }
        if ($Line -match '^##\s' -and $InCoreSection) {
            $InCoreSection = $False
            break
        }
        if ($InCoreSection -and $Line -match '^###\s+([IVX]+)\.\s+(.+)$') {
            $Rules.CorePrinciples += @{
                Title = $Matches[2].Trim()
                Number = $Matches[1]
            }
        }
    }

    # Extract Quality Standards - Specification Quality
    if ($Content -match '(?s)### Specification Quality(.+?)(?=###|\z)') {
        $SpecQuality = $Matches[1]

        # Parse MUST requirements
        $MustMatches = [regex]::Matches($SpecQuality, '(?m)^- .+?MUST (.+?)$')
        foreach ($Match in $MustMatches) {
            $Rules.QualityStandards += @{
                Type = "Specification Quality"
                Rule = $Match.Groups[0].Value.Trim()
                Description = $Match.Groups[1].Value.Trim()
            }
        }

        # Parse Maximum requirements
        $MaxMatches = [regex]::Matches($SpecQuality, '(?m)^- Maximum (\d+) (.+?)$')
        foreach ($Match in $MaxMatches) {
            $Rules.QualityStandards += @{
                Type = "Specification Quality"
                Rule = $Match.Groups[0].Value.Trim()
                MaxCount = [int]$Match.Groups[1].Value
                Item = $Match.Groups[2].Value.Trim()
            }
        }
    }

    # Extract Documentation Quality standards
    if ($Content -match '(?s)### Documentation Quality(.+?)(?=##|\z)') {
        $DocQuality = $Matches[1]

        $MustMatches = [regex]::Matches($DocQuality, '(?m)^- .+?MUST (.+?)$')
        foreach ($Match in $MustMatches) {
            $Rules.QualityStandards += @{
                Type = "Documentation Quality"
                Rule = $Match.Groups[0].Value.Trim()
                Description = $Match.Groups[1].Value.Trim()
            }
        }
    }

    return $Rules
}

function Test-ConstitutionCompliance {
    <#
    .SYNOPSIS
        Tests artifacts against the five constitution principles.
    .DESCRIPTION
        Validates feature artifacts against each constitution principle:
        - Principle I: Spec-First Development (spec.md exists)
        - Principle II: File-Based Truth (all artifacts are files)
        - Principle III: Validation Gates (validation is running)
        - Principle IV: Dual-State Model (feature in specs/changes/)
        - Principle V: AI-Ready Instructions (WHEN/THEN + MUST/SHALL/NEVER)
        Plus additional checks:
        - Clarification Limit: Max 3 [NEEDS CLARIFICATION] markers
        - Task Format: T### format in tasks.md
    .OUTPUTS
        Hashtable with 'compliant' boolean and 'principles' array
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FeatureDir
    )

    $Principles = @()
    $HasFailure = $False

    # --- Principle I: Spec-First Development ---
    $SpecPath = Join-Path $FeatureDir "spec.md"
    if (Test-Path $SpecPath) {
        $Principles += @{
            name    = "I. Spec-First Development"
            status  = "PASS"
            details = "Specification exists at spec.md"
        }
    }
    else {
        $Principles += @{
            name    = "I. Spec-First Development"
            status  = "FAIL"
            details = "Missing spec.md - specification required before implementation"
        }
        $HasFailure = $True
    }

    # --- Principle II: File-Based Truth ---
    # SpecKit uses file-based artifacts by design
    $Principles += @{
        name    = "II. File-Based Truth"
        status  = "PASS"
        details = "All artifacts are Markdown files (file-based approach)"
    }

    # --- Principle III: Validation Gates ---
    # This check passes because we're running validation
    $Principles += @{
        name    = "III. Validation Gates"
        status  = "PASS"
        details = "Validation gate is active (this script is running)"
    }

    # --- Principle IV: Dual-State Model ---
    # Check if feature is in specs/changes/ (proposal state)
    $NormalizedPath = $FeatureDir -replace '\\', '/'
    if ($NormalizedPath -match 'specs/changes/') {
        $Principles += @{
            name    = "IV. Dual-State Model"
            status  = "PASS"
            details = "Feature is in proposal state (specs/changes/)"
        }
    }
    else {
        $Principles += @{
            name    = "IV. Dual-State Model"
            status  = "WARN"
            details = "Feature not in specs/changes/ - verify state is intentional"
        }
    }

    # --- Principle V: AI-Ready Instructions ---
    $AiReadyStatus = "PASS"
    $AiReadyDetails = @()

    if (Test-Path $SpecPath) {
        $SpecContent = Get-Content -LiteralPath $SpecPath -Raw -Encoding UTF8

        # Check for WHEN/THEN scenarios
        $HasWhenThen = $SpecContent -match '\bWHEN\b.*\bTHEN\b' -or
                       ($SpecContent -match '\bWHEN\b' -and $SpecContent -match '\bTHEN\b')
        if ($HasWhenThen) {
            $AiReadyDetails += "WHEN/THEN scenarios present"
        }
        else {
            $AiReadyStatus = "WARN"
            $AiReadyDetails += "Missing WHEN/THEN scenario language"
        }

        # Check for MUST/SHALL/NEVER language
        $HasNormative = $SpecContent -match '\b(MUST|SHALL|NEVER)\b'
        if ($HasNormative) {
            $AiReadyDetails += "Normative language (MUST/SHALL/NEVER) present"
        }
        else {
            $AiReadyStatus = "WARN"
            $AiReadyDetails += "Missing normative language (MUST/SHALL/NEVER)"
        }
    }
    else {
        $AiReadyStatus = "WARN"
        $AiReadyDetails += "Cannot check - spec.md not found"
    }

    $Principles += @{
        name    = "V. AI-Ready Instructions"
        status  = $AiReadyStatus
        details = ($AiReadyDetails -join "; ")
    }

    # --- Additional Check: Clarification Limit ---
    if (Test-Path $SpecPath) {
        $SpecContent = Get-Content -LiteralPath $SpecPath -Raw -Encoding UTF8
        $ClarificationCount = ([regex]::Matches($SpecContent, '\[NEEDS CLARIFICATION\]')).Count

        if ($ClarificationCount -eq 0) {
            $Principles += @{
                name    = "Clarification Limit"
                status  = "PASS"
                details = "No [NEEDS CLARIFICATION] markers"
            }
        }
        elseif ($ClarificationCount -le 3) {
            $Principles += @{
                name    = "Clarification Limit"
                status  = "WARN"
                details = "$ClarificationCount [NEEDS CLARIFICATION] marker(s) found (max 3 allowed)"
            }
        }
        else {
            $Principles += @{
                name    = "Clarification Limit"
                status  = "FAIL"
                details = "$ClarificationCount [NEEDS CLARIFICATION] markers exceed limit of 3"
            }
            $HasFailure = $True
        }
    }
    else {
        $Principles += @{
            name    = "Clarification Limit"
            status  = "PASS"
            details = "No spec.md to check"
        }
    }

    # --- Additional Check: Task Format ---
    $TasksPath = Join-Path $FeatureDir "tasks.md"
    if (Test-Path $TasksPath) {
        $TasksContent = Get-Content -LiteralPath $TasksPath -Raw -Encoding UTF8

        # Look for task headers or task references
        $TaskMatches = [regex]::Matches($TasksContent, '\bT\d{3}\b')
        $AllTaskRefs = [regex]::Matches($TasksContent, '(?m)^#+\s*(?:Task|T)\s*[\d:]+|^\s*-\s*\[.\]\s*(?:Task|T)\s*\d+')

        if ($TaskMatches.Count -gt 0) {
            $Principles += @{
                name    = "Task Format"
                status  = "PASS"
                details = "Found $($TaskMatches.Count) task(s) using T### format"
            }
        }
        elseif ($AllTaskRefs.Count -gt 0) {
            $Principles += @{
                name    = "Task Format"
                status  = "WARN"
                details = "Tasks found but not using T### format (e.g., T001, T002)"
            }
        }
        else {
            $Principles += @{
                name    = "Task Format"
                status  = "WARN"
                details = "No tasks detected in tasks.md"
            }
        }
    }
    else {
        $Principles += @{
            name    = "Task Format"
            status  = "WARN"
            details = "No tasks.md found"
        }
    }

    return @{
        compliant  = -not $HasFailure
        principles = $Principles
    }
}

function Test-SpecFileConstitutionCompliance {
    <#
    .SYNOPSIS
        Validates a spec file against constitution rules.
    .DESCRIPTION
        Performs deep validation including:
        - Required sections present
        - Heading level hierarchy
        - Quality standards (max clarifications, scenarios per requirement)
        - AI-Ready language (MUST/SHALL usage)
    #>
    param(
        [string]$FilePath,
        [hashtable]$Rules
    )

    $Errors = @()
    if (-not (Test-Path $FilePath)) { return $Errors }

    $Content = Get-FileContentCached -Path $FilePath -Raw
    $Lines = Get-FileContentCached -Path $FilePath

    # Rule: Every requirement MUST have at least one testable scenario
    # (Already validated in Test-SpecFile, but enhance error message)

    # Rule: Maximum 3 [NEEDS CLARIFICATION] markers per spec (0 in Strict mode)
    $ClarificationMarkers = ([regex]::Matches($Content, '\[NEEDS CLARIFICATION\]')).Count
    $MaxAllowed = if ($Strict) { 0 } else { $Script:ClarificationLimitDefault }
    if ($ClarificationMarkers -gt $MaxAllowed) {
        $ModeNote = if ($Strict) { " (Strict mode: zero tolerance)" } else { "" }
        $Errors += Write-ValidationError -Message "Constitution Violation: Specification Quality - Maximum $MaxAllowed [NEEDS CLARIFICATION] markers allowed$ModeNote, found $ClarificationMarkers" -File $FilePath -Line 0
    }

    # Rule: Heading levels MUST NOT skip
    $HeadingPattern = '^(#+)\s+(.+)$'
    $PreviousLevel = 0
    for ($LineIndex = 0; $LineIndex -lt $Lines.Count; $LineIndex++) {
        if ($Lines[$LineIndex] -match $HeadingPattern) {
            $CurrentLevel = $Matches[1].Length
            $HeadingText = $Matches[2]

            if ($PreviousLevel -gt 0 -and $CurrentLevel -gt ($PreviousLevel + 1)) {
                $Errors += Write-ValidationError -Message "Constitution Violation: Documentation Quality - Heading levels MUST NOT skip (h$PreviousLevel to h$CurrentLevel at line $($LineIndex + 1))" -File $FilePath -Line ($LineIndex + 1)
            }
            $PreviousLevel = $CurrentLevel
        }
    }

    # Rule: External links MUST use reference-style
    # Detect inline links: [text](http://...)
    $InlineLinkMatches = [regex]::Matches($Content, '\[([^\]]+)\]\((https?://[^\)]+)\)')
    if ($InlineLinkMatches.Count -gt 0) {
        foreach ($Match in $InlineLinkMatches) {
            $LineNum = ($Content.Substring(0, $Match.Index) -split $Script:RegexNewLine).Count
            $Errors += Write-ValidationError -Message "Constitution Violation: Documentation Quality - External links MUST use reference-style, found inline link: $($Match.Value)" -File $FilePath -Line $LineNum
        }
    }

    # Rule: Success criteria MUST be measurable (check for vague language)
    $VagueTerms = @('try to', 'could', 'please', 'might', 'should probably', 'maybe')
    foreach ($Term in $VagueTerms) {
        if ($Content -match [regex]::Escape($Term)) {
            $Matches = [regex]::Matches($Content, [regex]::Escape($Term))
            foreach ($Match in $Matches) {
                $LineNum = ($Content.Substring(0, $Match.Index) -split "`n").Count
                $Errors += Write-ValidationError -Message "Constitution Violation: AI-Ready Instructions - Avoid ambiguous language ('$Term'), use MUST/SHALL/NEVER instead" -File $FilePath -Line $LineNum
            }
        }
    }

    # Rule: Requirements should use SHALL/MUST (enhanced check)
    # This is checked in Test-SpecFile but we can add more context

    # Strict Mode Only: Check for unchecked checklist items in same feature directory
    if ($Strict) {
        # Try to locate checklists directory relative to the file being validated
        $FileDir = Split-Path -Parent $FilePath
        $ChecklistDir = Join-Path $FileDir "checklists"

        if (Test-Path $ChecklistDir) {
            $ChecklistFiles = Get-ChildItem -Path $ChecklistDir -Filter "*.md" -ErrorAction SilentlyContinue
            $UncheckedPattern = '- \[ \]'

            foreach ($ChecklistFile in $ChecklistFiles) {
                $Matches = Select-String -Path $ChecklistFile.FullName -Pattern $UncheckedPattern -AllMatches
                if ($Matches.Count -gt 0) {
                    $Errors += Write-ValidationError -Message "Strict Mode Violation: Found $($Matches.Count) unchecked checklist item(s) in checklists/$($ChecklistFile.Name)" -File $ChecklistFile.FullName -Line 0
                }
            }
        }
    }

    return $Errors
}

function Test-DeltaSpec {
    <#
    .SYNOPSIS
        Validates delta specification files for proper structure and content.
    .DESCRIPTION
        A delta file is identified by:
        - Located in specs/changes/{change-id}/specs/{capability}/spec.md
        - OR contains sections: ## ADDED Requirements, ## MODIFIED Requirements, ## REMOVED Requirements

        Validations performed:
        - At least one of ADDED, MODIFIED, or REMOVED sections must exist
        - Each ADDED requirement must have format: - **REQ-XXX**: description
        - Each MODIFIED requirement must reference an existing REQ-ID from the base spec
        - Each REMOVED requirement must have a reason
        - If delta references a capability, that capability's spec.md must exist
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SpecPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot
    )

    $Result = @{
        isDelta = $False
        valid = $True
        errors = @()
        warnings = @()
        sections = @{
            added = $False
            modified = $False
            removed = $False
        }
    }

    if (-not (Test-Path $SpecPath)) {
        return $Result
    }

    $Content = Get-FileContentCached -Path $SpecPath -Raw
    $Lines = Get-FileContentCached -Path $SpecPath
    $NormalizedPath = $SpecPath -replace '\\', '/'

    # Detection: Check if file is a delta spec
    # Pattern 1: Located in specs/changes/{change-id}/specs/{capability}/spec.md
    $IsLocationDelta = $NormalizedPath -match 'specs/changes/[^/]+/specs/[^/]+/spec\.md$'

    # Pattern 2: Contains delta section headers
    $HasAddedSection = $Content -match '(?m)^## ADDED Requirements'
    $HasModifiedSection = $Content -match '(?m)^## MODIFIED Requirements'
    $HasRemovedSection = $Content -match '(?m)^## REMOVED Requirements'
    $HasAnySectionHeader = $HasAddedSection -or $HasModifiedSection -or $HasRemovedSection

    if (-not $IsLocationDelta -and -not $HasAnySectionHeader) {
        # Not a delta file
        return $Result
    }

    $Result.isDelta = $True
    $Result.sections.added = $HasAddedSection
    $Result.sections.modified = $HasModifiedSection
    $Result.sections.removed = $HasRemovedSection

    # Validation 1: At least one section must exist
    if (-not $HasAnySectionHeader) {
        $Result.valid = $False
        $Result.errors += @{
            error = "Delta spec must have at least one of: ## ADDED Requirements, ## MODIFIED Requirements, or ## REMOVED Requirements"
            file = $SpecPath
            line = 1
        }
        return $Result
    }

    # Validation 2: If location-based delta, check that base capability spec exists
    if ($IsLocationDelta) {
        if ($NormalizedPath -match 'specs/changes/[^/]+/specs/([^/]+)/spec\.md$') {
            $CapabilityName = $Matches[1]
            $BaseSpecPath = Join-Path $RepoRoot "specs" $CapabilityName "spec.md"

            if (-not (Test-Path $BaseSpecPath)) {
                $Result.warnings += @{
                    warning = "Base capability spec not found: specs/$CapabilityName/spec.md - delta may be for a new capability"
                    file = $SpecPath
                    line = 1
                }
            }
        }
    }

    # Parse sections and validate content
    $CurrentSection = $Null
    $CurrentSectionStart = 0
    $RequirementPattern = '^###\s+Requirement:\s*(.+)$'
    $ReqIdPattern = '\bREQ-[A-Z0-9]{3,}\b'
    $ReasonPattern = '\*\*Reason\*\*:|Reason:'

    for ($LineIndex = 0; $LineIndex -lt $Lines.Count; $LineIndex++) {
        $Line = $Lines[$LineIndex]
        $LineNum = $LineIndex + 1

        # Detect section transitions
        if ($Line -match '^## ADDED Requirements') {
            $CurrentSection = 'ADDED'
            $CurrentSectionStart = $LineNum
            continue
        }
        elseif ($Line -match '^## MODIFIED Requirements') {
            $CurrentSection = 'MODIFIED'
            $CurrentSectionStart = $LineNum
            continue
        }
        elseif ($Line -match '^## REMOVED Requirements') {
            $CurrentSection = 'REMOVED'
            $CurrentSectionStart = $LineNum
            continue
        }
        elseif ($Line -match '^## ') {
            # Exit delta section on any other h2 header
            $CurrentSection = $Null
            continue
        }

        # Skip empty lines and non-requirement lines
        if (-not $CurrentSection -or [string]::IsNullOrWhiteSpace($Line)) {
            continue
        }

        # Validation 3: ADDED requirements should have proper format
        if ($CurrentSection -eq 'ADDED' -and $Line -match $RequirementPattern) {
            $ReqTitle = $Matches[1]
            # Check for REQ-ID in the requirement or following lines (look ahead up to 5 lines)
            $ContextLines = ($Lines | Select-Object -Skip $LineIndex -First ($Script:DeltaReqIdLookaheadLines + 1)) -join "`n"

            # ADDED requirements should ideally have a REQ-ID, but warn if missing
            if ($ContextLines -notmatch $ReqIdPattern) {
                $Result.warnings += @{
                    warning = "ADDED requirement '$ReqTitle' should include a REQ-ID (e.g., **REQ-XXX**)"
                    file = $SpecPath
                    line = $LineNum
                }
            }
        }

        # Validation 4: MODIFIED requirements should reference existing REQ-ID
        if ($CurrentSection -eq 'MODIFIED' -and $Line -match $RequirementPattern) {
            $ReqTitle = $Matches[1]
            # Check for REQ-ID reference
            $ContextLines = ($Lines | Select-Object -Skip $LineIndex -First ($Script:DeltaReqIdLookaheadLines + 1)) -join "`n"

            if ($ContextLines -notmatch $ReqIdPattern) {
                $Result.errors += @{
                    error = "MODIFIED requirement '$ReqTitle' must reference an existing REQ-ID from the base spec"
                    file = $SpecPath
                    line = $LineNum
                }
                $Result.valid = $False
            }
        }

        # Validation 5: REMOVED requirements must have a reason
        if ($CurrentSection -eq 'REMOVED' -and $Line -match $RequirementPattern) {
            $ReqTitle = $Matches[1]
            # Look ahead for a reason (up to 10 lines or until next requirement/section)
            $FoundReason = $False
            for ($LookaheadIndex = $LineIndex + 1; $LookaheadIndex -lt [Math]::Min($LineIndex + $Script:DeltaRemovedReasonLookaheadLines, $Lines.Count); $LookaheadIndex++) {
                $CheckLine = $Lines[$LookaheadIndex]
                if ($CheckLine -match '^###?\s' -or $CheckLine -match '^## ') {
                    # Hit next requirement or section, stop looking
                    break
                }
                if ($CheckLine -match $ReasonPattern) {
                    $FoundReason = $True
                    break
                }
            }

            if (-not $FoundReason) {
                $Result.errors += @{
                    error = "REMOVED requirement '$ReqTitle' must include a reason (use **Reason**: or Reason:)"
                    file = $SpecPath
                    line = $LineNum
                }
                $Result.valid = $False
            }
        }
    }

    function Get-DeltaSectionContent {
        param(
            [Parameter(Mandatory = $True)]
            [ValidateNotNullOrEmpty()]
            [string]$SectionName
        )

        $Pattern = "(?ms)^## $SectionName Requirements\s*\r?\n(?<section>.+?)(?=^##\s|\z)"
        $Match = [regex]::Match($Content, $Pattern)
        if ($Match.Success) {
            return $Match.Groups['section'].Value
        }

        return ""
    }

    function Get-RequirementBlock {
        param(
            [Parameter(Mandatory = $True)]
            [ValidateNotNullOrEmpty()]
            [string]$BlockContent,
            [Parameter(Mandatory = $True)]
            [ValidateNotNullOrEmpty()]
            [string]$ReqId
        )

        $Pattern = "(?ms)^###\s+Requirement:.*?$([regex]::Escape($ReqId)).*?(?=^###\s+Requirement:|^##\s|\z)"
        $Match = [regex]::Match($BlockContent, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($Match.Success) {
            return $Match.Value.Trim()
        }

        return ""
    }

    function Normalize-RequirementBlock {
        param(
            [Parameter(Mandatory = $True)]
            [ValidateNotNullOrEmpty()]
            [string]$Block
        )

        $Normalized = $Block -replace '\s+', ' '
        return $Normalized.Trim()
    }

    $SectionContents = @{
        ADDED = (Get-DeltaSectionContent -SectionName 'ADDED')
        MODIFIED = (Get-DeltaSectionContent -SectionName 'MODIFIED')
        REMOVED = (Get-DeltaSectionContent -SectionName 'REMOVED')
    }

    $SeenReqIds = @{}
    $BaseSpecContent = $Null
    if ($BaseSpecPath -and (Test-Path $BaseSpecPath)) {
        $BaseSpecContent = Get-FileContentCached -Path $BaseSpecPath -Raw
    }

    foreach ($SectionName in $SectionContents.Keys) {
        $SectionContent = $SectionContents[$SectionName]
        if ([string]::IsNullOrWhiteSpace($SectionContent)) {
            continue
        }

        $ReqMatches = [regex]::Matches($SectionContent, $ReqIdPattern)
        if ($ReqMatches.Count -eq 0) {
            $Result.valid = $False
            $Result.errors += @{
                error = "$SectionName section must include REQ-ID references"
                file = $SpecPath
                line = 1
            }
            continue
        }

        foreach ($ReqMatch in $ReqMatches) {
            $ReqId = $ReqMatch.Value.ToUpper()

            if (-not $Script:RegexRequirementId.IsMatch($ReqId)) {
                $Result.valid = $False
                $Result.errors += @{
                    error = "Invalid REQ-ID format: $ReqId"
                    file = $SpecPath
                    line = 1
                }
                continue
            }

            if ($SeenReqIds.ContainsKey($ReqId)) {
                $Result.valid = $False
                $Result.errors += @{
                    error = "Duplicate REQ-ID '$ReqId' referenced in $SectionName and $($SeenReqIds[$ReqId]) sections"
                    file = $SpecPath
                    line = 1
                }
            } else {
                $SeenReqIds[$ReqId] = $SectionName
            }

            if ($SectionName -eq 'MODIFIED' -and $BaseSpecContent) {
                if ($BaseSpecContent -notmatch [regex]::Escape($ReqId)) {
                    $Result.valid = $False
                    $Result.errors += @{
                        error = "MODIFIED requirement '$ReqId' does not exist in base spec"
                        file = $SpecPath
                        line = 1
                    }
                }
            }

            if ($SectionName -eq 'REMOVED') {
                $RemovedBlock = Get-RequirementBlock -BlockContent $SectionContent -ReqId $ReqId
                if ($RemovedBlock -and ($RemovedBlock -notmatch $ReasonPattern)) {
                    $Result.valid = $False
                    $Result.errors += @{
                        error = "REMOVED requirement '$ReqId' must include a reason"
                        file = $SpecPath
                        line = 1
                    }
                }
            }
        }
    }

    if ($BaseSpecContent -and $SectionContents['MODIFIED']) {
        foreach ($ReqId in $SeenReqIds.Keys | Where-Object { $SeenReqIds[$_] -eq 'MODIFIED' }) {
            $DeltaBlock = Get-RequirementBlock -BlockContent $SectionContents['MODIFIED'] -ReqId $ReqId
            $BaseBlock = Get-RequirementBlock -BlockContent $BaseSpecContent -ReqId $ReqId

            if ($DeltaBlock -and $BaseBlock) {
                if ((Normalize-RequirementBlock -Block $DeltaBlock) -eq (Normalize-RequirementBlock -Block $BaseBlock)) {
                    $Result.valid = $False
                    $Result.errors += @{
                        error = "MODIFIED requirement '$ReqId' has no detectable changes compared to base spec"
                        file = $SpecPath
                        line = 1
                    }
                }
            }
        }
    }

    return $Result
}

function Write-ValidationError {
    <#
    .SYNOPSIS
        Formats and outputs validation errors.
    .PARAMETER Message
        Error message text.
    .PARAMETER File
        File name or path associated with the error.
    .PARAMETER Line
        Line number associated with the error.
    .OUTPUTS
        Hashtable describing the error.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$File,
        [int]$Line
    )

    # Always return an error object for counting
    $ErrorObj = @{ error = $Message; file = $File; line = $Line }

    # Display immediately in non-JSON mode
    if (-not $Json) {
        Write-LogInfo "ERROR: $Message" -ForegroundColor Red
        Write-LogInfo "  File: $File" -ForegroundColor Gray
        if ($Line -gt 0) { Write-LogInfo "  Line: $Line" -ForegroundColor Gray }
    }

    return $ErrorObj
}

function Test-SpecFile {
    <#
    .SYNOPSIS
        Validates a spec.md file for formatting and scenario coverage.
    .PARAMETER FilePath
        Path to the spec file.
    .OUTPUTS
        Hashtable with errors and requirement validation results.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )
    $Errors = @()
    if (-not (Test-Path $FilePath)) { return $Errors }

    $Content = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    $Lines = Get-Content -LiteralPath $FilePath -Encoding UTF8
    $CurrentRequirement = ""
    $HasScenario = $False

    # Validate REQ-IDs for uniqueness and sequence
    $ReqIdResult = Test-RequirementIds -SpecContent $Content -FilePath $FilePath

    # Add REQ-ID errors to the error list
    foreach ($Err in $ReqIdResult.errors) {
        $Errors += Write-ValidationError -Message $Err.error -File $Err.file -Line $Err.line
    }

    # Display REQ-ID warnings in non-JSON mode
    foreach ($Warn in $ReqIdResult.warnings) {
        if (-not $Json) {
            Write-LogInfo "WARNING: $($Warn.warning)" -ForegroundColor Yellow
            Write-LogInfo "  File: $($Warn.file)" -ForegroundColor Gray
        }
    }

    for ($I = 0; $I -lt $Lines.Count; $I++) {
        $Line = $Lines[$I].Trim()
        $LineNum = $I + 1

        # Check for Requirement header
        if ($Line -match '^### Requirement:\s*(.+)$') {
            if ($CurrentRequirement -and -not $HasScenario) {
                $ErrorMsg = "Requirement '$CurrentRequirement' must have at least one scenario"
                if ($Strict) {
                    $ErrorMsg = "Constitution Violation: Specification Quality - $ErrorMsg (Core Principle V: Testable scenarios required)"
                }
                $Errors += Write-ValidationError -Message $ErrorMsg -File $FilePath -Line ($I)
            }

            $CurrentRequirement = $Matches[1]
            $HasScenario = $False

            # Check for SHALL/MUST
            $NextLines = $Lines | Select-Object -Skip ($I + 1) -First $Script:RequirementNormativeLookaheadLines
            $FullReq = ($Line + " " + ($NextLines -join " "))
            if ($FullReq -notmatch '\b(SHALL|MUST)\b') {
                $ErrorMsg = "Requirement '$CurrentRequirement' should use SHALL or MUST for normative clarity"
                if ($Strict) {
                    $ErrorMsg = "Constitution Violation: AI-Ready Instructions - $ErrorMsg (Core Principle V)"
                }
                $Errors += Write-ValidationError -Message $ErrorMsg -File $FilePath -Line $LineNum
            }
        }

        # Check for Scenario header
        if ($Line -match '^#### Scenario:') {
            $HasScenario = $True
        }
        elseif ($Line -match '^#+\s*Scenario:' -and $Line -notmatch '^####\s') {
            $ErrorMsg = "Scenario must use exactly four hashtags (#### Scenario:)"
            if ($Strict) {
                $ErrorMsg = "Constitution Violation: Documentation Quality - $ErrorMsg"
            }
            $Errors += Write-ValidationError -Message $ErrorMsg -File $FilePath -Line $LineNum
        }
        elseif ($Line -match '^- \*\*Scenario:') {
            $ErrorMsg = "Scenario header must not be a bullet point. Use #### Scenario:"
            if ($Strict) {
                $ErrorMsg = "Constitution Violation: Documentation Quality - $ErrorMsg"
            }
            $Errors += Write-ValidationError -Message $ErrorMsg -File $FilePath -Line $LineNum
        }
    }

    if ($CurrentRequirement -and -not $HasScenario) {
        $ErrorMsg = "Requirement '$CurrentRequirement' must have at least one scenario"
        if ($Strict) {
            $ErrorMsg = "Constitution Violation: Specification Quality - $ErrorMsg (Core Principle V: Testable scenarios required)"
        }
        $Errors += Write-ValidationError -Message $ErrorMsg -File $FilePath -Line $Lines.Count
    }

    # Return structured result with errors and REQ-ID validation
    return @{
        errors = $Errors
        reqIdValidation = $ReqIdResult
    }
}

function Test-ChangeId {
    <#
    .SYNOPSIS
        Validates change ID format for naming convention compliance.
    .PARAMETER Id
        Change ID string to validate.
    .OUTPUTS
        Hashtable describing the error, or $Null when valid.
    #>
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Id
    )
    $ValidPrefixes = @('add-', 'update-', 'remove-', 'refactor-', 'fix-', 'feat-')
    $IsValid = $Id -match '^(\d{3}-|add-|update-|remove-|refactor-|fix-|feat-)[a-z0-9-]+$'

    if (-not $IsValid) {
        $ErrorMsg = "Change ID '$Id' must be kebab-case and start with a verb (add-, update-, etc.) or number (001-)"
        if ($Strict) {
            $ErrorMsg = "Constitution Violation: Naming Convention - $ErrorMsg"
        }
        return Write-ValidationError -Message $ErrorMsg -File "N/A" -Line 0
    }
    return $Null
}

function Test-PlaceholderSweep {
    <#
    .SYNOPSIS
        Detects placeholder markers in generated artifacts to prevent incomplete work.
    .DESCRIPTION
        Searches for common placeholder patterns (TBD, TODO, FIXME, [insert], etc.)
        in generated files. Excludes build artifacts, version control, and archives.
    .PARAMETER TargetPath
        Path to search for placeholders (file or directory).
    .OUTPUTS
        Hashtable with 'valid' boolean, 'placeholders' array, and 'errors' array.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetPath
    )

    $Result = @{
        valid = $True
        placeholders = @()
        errors = @()
    }

    if (-not (Test-Path $TargetPath)) {
        $Result.valid = $False
        $Result.errors += @{
            error = "Target path not found: $TargetPath"
            file = $TargetPath
            line = 0
        }
        return $Result
    }

    # Placeholder patterns to detect
    $PlaceholderPattern = 'TBD|TODO|FIXME|\[insert\]|\[placeholder\]|<placeholder>'

    # Excluded paths (relative patterns)
    $ExcludePaths = @(
        '*/node_modules/*',
        '*/.git/*',
        '*/dist/*',
        '*/build/*',
        '*/archive/*',
        '*.log'
    )

    try {
        # Search for placeholder patterns
        $SearchParams = @{
            Path = $TargetPath
            Pattern = $PlaceholderPattern
            Recurse = $True
            ErrorAction = 'SilentlyContinue'
        }

        $Matches = Select-String @searchParams | Where-Object {
            $FilePath = $_.Path
            $ShouldExclude = $False

            foreach ($ExcludePattern in $ExcludePaths) {
                if ($FilePath -like $ExcludePattern) {
                    $ShouldExclude = $True
                    break
                }
            }

            -not $ShouldExclude
        }

        if ($Matches) {
            $Result.valid = $False

            foreach ($Match in $Matches) {
                $Placeholder = @{
                    file = $Match.Path
                    line = $Match.LineNumber
                    pattern = $Match.Line.Trim()
                    matchedText = $Match.Matches[0].Value
                }

                $Result.placeholders += $Placeholder

                $ErrorMsg = "Placeholder marker '$($Placeholder.matchedText)' found - must be resolved before completion"
                $Result.errors += @{
                    error = $ErrorMsg
                    file = $Match.Path
                    line = $Match.LineNumber
                }
            }
        }
    }
    catch {
        $Result.valid = $False
        $Result.errors += @{
            error = "Placeholder sweep failed: $_"
            file = $TargetPath
            line = 0
        }
    }

    return $Result
}

function Test-PlaceholderConsistency {
    <#
    .SYNOPSIS
        Detects placeholder format conflicts between templates and agent instructions.
    .DESCRIPTION
        Validates that agent instructions reference the same placeholder formats used in templates.
        Prevents agents from failing to replace placeholders due to format mismatches.
    #>
    param()

    $Result = @{
        valid = $True
        errors = @()
    }

    try {
        # Get template files
        $TemplateFiles = Get-ChildItem "specs/templates/*.md" -ErrorAction SilentlyContinue
        $AgentFiles = Get-ChildItem ".github/agents/*.md" -ErrorAction SilentlyContinue

        $TemplatePlaceholders = @{}
        $AgentInstructions = @{}

        # Extract {PLACEHOLDER} format from templates
        foreach ($File in $TemplateFiles) {
            $Content = Get-Content $File.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $Content) { continue }

            [regex]::Matches($Content, '\{([A-Z_]+)\}') | ForEach-Object {
                $TemplatePlaceholders[$_.Groups[1].Value] = $True
            }
        }

        # Extract <placeholder> references in agent instructions (exclude code blocks and examples)
        foreach ($File in $AgentFiles) {
            $Content = Get-Content $File.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $Content) { continue }

            # Find <placeholder> patterns but exclude those in code blocks or clear examples
            $Lines = $Content -split "`n"
            for ($I = 0; $I -lt $Lines.Count; $I++) {
                $Line = $Lines[$I]

                # Skip if we're in a code block
                $InCodeBlock = $False
                for ($J = 0; $J -le $I; $J++) {
                    if ($Lines[$J] -match '^```') { $InCodeBlock = -not $InCodeBlock }
                }

                if (-not $InCodeBlock) {
                    # Look for <placeholder> patterns in instructional text
                    $Matches = [regex]::Matches($Line, '<([a-z-]+)>')
                    foreach ($Match in $Matches) {
                        # Skip if it looks like an example (contains words like "e.g.", "example", "format", or is in a command)
                        $Context = $Line.ToLower()
                        if ($Context -notmatch 'e\.g\.|example|format|description|table|option|specs/scripts|\.ps1|→') {
                            $AgentInstructions[$Match.Groups[1].Value] = $File.Name
                        }
                    }
                }
            }
        }

        # Report mismatches
        $AgentInstructions.Keys | ForEach-Object {
            $Upper = $_.ToUpper().Replace('-', '_')
            if (-not $TemplatePlaceholders[$Upper]) {
                $Result.valid = $False
                $Result.errors += @{
                    error = "Agent references <$($_)> but template uses {$Upper}"
                    file = $AgentInstructions[$_]
                    line = 0
                }
            }
        }
    }
    catch {
        $Result.valid = $False
        $Result.errors += @{
            error = "Placeholder consistency check failed: $_"
            file = ""
            line = 0
        }
    }

    return $Result
}

function Test-RequirementIds {
    <#
    .SYNOPSIS
        Validates REQ-IDs in specification files for uniqueness and sequence.
    .DESCRIPTION
        Scans spec content for requirement ID patterns and validates:
        - All REQ-IDs are unique (no duplicates within the same file)
        - REQ-IDs are sequential (warns if gaps exist in numbering)

        Recognized REQ-ID formats:
        - **REQ-001**: (bold with number)
        - REQ-001: (plain with number)
        - **REQ-FR-001**: (with prefix like FR, NFR, UI, etc.)
        - [REQ-001] (bracketed)
    .PARAMETER SpecContent
        The raw content of the spec file to validate.
    .PARAMETER FilePath
        The path to the spec file (for error reporting).
    .OUTPUTS
        Hashtable with validation results including reqIds, duplicates, sequenceGaps, and validity status.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SpecContent,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    $Result = @{
        reqIds = @()           # List of all found REQ-IDs
        duplicates = @()       # Any duplicate IDs found
        sequenceGaps = @()     # Missing IDs in sequence
        valid = $True
        errors = @()
        warnings = @()
    }

    # Pattern to match all REQ-ID formats:
    # - **REQ-001**: (bold with colon)
    # - REQ-001: (plain with colon)
    # - REQ-001 (plain, followed by space or end)
    # - **REQ-FR-001**: (with optional prefix like FR, NFR, UI, etc.)
    # - [REQ-001] (bracketed)
    # Captures: optional prefix (like FR-), and the numeric portion
    $ReqIdPattern = '(?:\*\*)?(?:\[)?REQ-(?:([A-Z]+-)?(\d{3,}))(?:\]|\*\*)?(?::|(?=\s|$|\*|\]))'

    $ReqMatches = [regex]::Matches($SpecContent, $ReqIdPattern)

    if ($ReqMatches.Count -eq 0) {
        # No REQ-IDs found - this is not an error, just no requirements to validate
        return $Result
    }

    # Extract all REQ-IDs and track their positions for duplicate detection
    $FoundIds = @{}  # Hash to track ID -> list of line numbers
    $NumericIds = @()  # Track numeric portions for sequence checking

    foreach ($Match in $ReqMatches) {
        # Reconstruct the full REQ-ID
        $Prefix = $Match.Groups[1].Value  # e.g., "FR-" or empty
        $Number = $Match.Groups[2].Value  # e.g., "001"
        $FullId = "REQ-$Prefix$Number"

        # Calculate line number for this match
            $LineNum = ($SpecContent.Substring(0, $Match.Index) -split $Script:RegexNewLine).Count

        # Track for duplicate detection
        if (-not $FoundIds.ContainsKey($FullId)) {
            $FoundIds[$FullId] = @()
        }
        $FoundIds[$FullId] += $LineNum

        # Track numeric portion for sequence checking (only for IDs without prefix or with same prefix)
        $NumericIds += @{
            prefix = $Prefix
            number = [int]$Number
            fullId = $FullId
            line = $LineNum
        }
    }

    # Populate reqIds list
    $Result.reqIds = $FoundIds.Keys | Sort-Object

    # Check for duplicates (same REQ-ID appearing more than once)
    foreach ($Id in $FoundIds.Keys) {
        if ($FoundIds[$Id].Count -gt 1) {
            $Result.duplicates += @{
                id = $Id
                lines = $FoundIds[$Id]
                count = $FoundIds[$Id].Count
            }
            $Result.valid = $False
            $Result.errors += @{
                error = "Duplicate REQ-ID '$Id' found $($FoundIds[$Id].Count) times at lines: $($FoundIds[$Id] -join ', ')"
                file = $FilePath
                line = $FoundIds[$Id][0]
            }
        }
    }

    # Check for sequence gaps (group by prefix and check each group)
    $GroupedByPrefix = $NumericIds | Group-Object -Property prefix

    foreach ($Group in $GroupedByPrefix) {
        $Prefix = $Group.Name
        $Numbers = $Group.Group | ForEach-Object { $_.number } | Sort-Object -Unique

        if ($Numbers.Count -gt 1) {
            $MinNum = $Numbers | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
            $MaxNum = $Numbers | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

            # Find gaps in the sequence
            $ExpectedNumbers = $MinNum..$MaxNum
            $MissingNumbers = $ExpectedNumbers | Where-Object { $_ -notin $Numbers }

            if ($MissingNumbers.Count -gt 0) {
                $PrefixDisplay = if ($Prefix) { "REQ-$Prefix" } else { "REQ-" }
                $MissingIds = $MissingNumbers | ForEach-Object {
                    "$PrefixDisplay$($_.ToString('D3'))"
                }

                $Result.sequenceGaps += @{
                    prefix = $Prefix
                    missingNumbers = $MissingNumbers
                    missingIds = $MissingIds
                }

                $Result.warnings += @{
                    warning = "REQ-ID sequence gap detected. Missing: $($MissingIds -join ', ')"
                    file = $FilePath
                    line = 1
                }
            }
        }
    }

    return $Result
}

# =============================================================================
# Gate Validation Functions (from run-gates.ps1)
# =============================================================================

$GateNames = @{
    1 = "Clarify"
    2 = "Implement"
    3 = "Archive"
}

function Invoke-GateValidation {
    <#
    .SYNOPSIS
        Runs all three gate validations for a feature directory.
    .DESCRIPTION
        Executes Gate 1 (Clarify), Gate 2 (Implement), and Gate 3 (Archive)
        and returns combined results.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FeatureDir
    )

    $GateResults = @{
        gates = @()
        overallStatus = "PASS"
        totalFailures = 0
        timestamp = (Get-Date -Format "o")
    }

    # Run Gate 1: Spec Clarity
    $Gate1 = Invoke-Gate1 -FeatureDir $FeatureDir
    $GateResults.gates += $Gate1
    if ($Gate1.status -eq "FAIL") {
        $GateResults.overallStatus = "FAIL"
        $GateResults.totalFailures += $Gate1.failures.Count
    }
    elseif ($Gate1.status -eq "ERROR" -and $GateResults.overallStatus -ne "FAIL") {
        $GateResults.overallStatus = "ERROR"
    }

    # Run Gate 2: Checklist Completion
    $Gate2 = Invoke-Gate2 -FeatureDir $FeatureDir
    $GateResults.gates += $Gate2
    if ($Gate2.status -eq "FAIL") {
        $GateResults.overallStatus = "FAIL"
        $GateResults.totalFailures += $Gate2.failures.Count
    }
    elseif ($Gate2.status -eq "ERROR" -and $GateResults.overallStatus -ne "FAIL") {
        $GateResults.overallStatus = "ERROR"
    }

    # Run Gate 3: Archive Readiness
    $Gate3 = Invoke-Gate3 -FeatureDir $FeatureDir
    $GateResults.gates += $Gate3
    if ($Gate3.status -eq "FAIL") {
        $GateResults.overallStatus = "FAIL"
        $GateResults.totalFailures += $Gate3.failures.Count
    }
    elseif ($Gate3.status -eq "ERROR" -and $GateResults.overallStatus -ne "FAIL") {
        $GateResults.overallStatus = "ERROR"
    }

    return $GateResults
}

function Invoke-Gate1 {
    <#
    .SYNOPSIS
        Gate 1: Spec Clarity - No [NEEDS CLARIFICATION] markers in spec.md
    #>
    param([string]$FeatureDir)

    $Result = @{
        gate = 1
        name = $GateNames[1]
        status = "PASS"
        message = ""
        checked_files = @()
        failures = @()
    }

    $SpecFile = Join-Path $FeatureDir "spec.md"

    if (-not (Test-Path $SpecFile)) {
        $Result.status = "ERROR"
        $Result.message = "spec.md not found in feature directory"
        return $Result
    }

    $Result.checked_files = @($SpecFile)

    # Search for [NEEDS CLARIFICATION patterns
    $Pattern = '\[NEEDS CLARIFICATION'
    $Matches = Select-String -Path $SpecFile -Pattern $Pattern -AllMatches

    if ($Matches.Count -gt 0) {
        $Result.status = "FAIL"
        $Result.message = "Found $($Matches.Count) unresolved clarification marker(s)"

        foreach ($Match in $Matches) {
            $Result.failures += @{
                file = "spec.md"
                line = $Match.LineNumber
                pattern = $Match.Line.Trim()
                message = "Unresolved clarification marker"
            }
        }
    } else {
        $Result.message = "No clarification markers found - spec is ready"
    }

    return $Result
}

function Invoke-Gate2 {
    <#
    .SYNOPSIS
        Gate 2: Checklist Completion - All checklist items must be checked
    #>
    param([string]$FeatureDir)

    $Result = @{
        gate = 2
        name = $GateNames[2]
        status = "PASS"
        message = ""
        checked_files = @()
        failures = @()
    }

    $ChecklistDir = Join-Path $FeatureDir "checklists"

    if (-not (Test-Path $ChecklistDir)) {
        $Result.message = "No checklists directory found - gate passes by default"
        return $Result
    }

    $ChecklistFiles = Get-ChildItem -Path $ChecklistDir -Filter "*.md" -ErrorAction SilentlyContinue

    if ($ChecklistFiles.Count -eq 0) {
        $Result.message = "No checklist files found - gate passes by default"
        return $Result
    }

    $Result.checked_files = $ChecklistFiles.FullName

    # Search for unchecked items: - [ ]
    $Pattern = '- \[ \]'
    $AllFailures = @()

    foreach ($File in $ChecklistFiles) {
        $Matches = Select-String -Path $File.FullName -Pattern $Pattern -AllMatches

        foreach ($Match in $Matches) {
            $AllFailures += @{
                file = "checklists/$($File.Name)"
                line = $Match.LineNumber
                pattern = $Match.Line.Trim()
                message = "Unchecked checklist item"
            }
        }

        # Check for sequence gaps if Test-ChecklistSequence exists
        if (Get-Command Test-ChecklistSequence -ErrorAction SilentlyContinue) {
            $SeqCheck = Test-ChecklistSequence -Path $File.FullName
            if (-not $SeqCheck.IsValid) {
                $AllFailures += @{
                    file = "checklists/$($File.Name)"
                    line = 1
                    pattern = "CHK sequence"
                    message = "Gap detected in CHK IDs: $($SeqCheck.Gaps -join ', ')"
                }
            }
        }
    }

    if ($AllFailures.Count -gt 0) {
        $Result.status = "FAIL"
        $Result.message = "Found $($AllFailures.Count) unchecked checklist item(s)"
        $Result.failures = $AllFailures
    } else {
        $Result.message = "All checklist items are checked - ready for archive"
    }

    return $Result
}

function Invoke-Gate3 {
    <#
    .SYNOPSIS
        Gate 3: Archive Readiness - No uncommitted changes in feature or governance files
    .DESCRIPTION
        Checks entire repo git status but filters to relevant paths:
        - Feature directory itself
        - specs/memory (constitution.md)
        - specs/project.md (project registry)
        - specs/templates (template files)
    #>
    param([string]$FeatureDir)

    $Result = @{
        gate = 3
        name = $GateNames[3]
        status = "PASS"
        message = ""
        checked_files = @()
        failures = @()
    }

    # Check entire repo, not just feature directory
    $RepoRoot = Get-WorkspaceRoot
    $Result.checked_files = @($FeatureDir, "$RepoRoot/specs/memory", "$RepoRoot/specs/project.md", "$RepoRoot/specs/templates")

    # Check if Git is available
    if (-not (Test-HasGit)) {
        $Result.status = "ERROR"
        $Result.message = "Git not available - cannot verify uncommitted changes"
        return $Result
    }

    # Get git status for entire repo, filter to relevant paths
    try {
        Push-Location $RepoRoot

        # Get git status for entire repo
        $StatusResult = Invoke-GitCommand -GitArgs @('status', '--porcelain') -IgnoreErrors
        if (-not $StatusResult.Success) {
            $Result.status = "ERROR"
            $Result.message = "Git status command failed: $($StatusResult.Error)"
            return $Result
        }
        $AllChanges = $StatusResult.Output

        if ($AllChanges) {
            # Get relative feature path for filtering
            $RelativeFeaturePath = $FeatureDir.Replace($RepoRoot, '').TrimStart('\', '/').Replace('\', '/')

            # Filter to relevant paths:
            # 1. Feature directory itself
            # 2. Governance files (constitution.md, project.md)
            # 3. Template files (if modified during feature work)
            $RelevantPaths = @(
                $RelativeFeaturePath,                    # Feature dir
                'specs/memory',                          # Constitution
                'specs/project.md',                      # Project registry
                'specs/templates'                        # Templates
            )

            $RelevantChanges = $AllChanges | Where-Object {
                $Line = $_.Trim()
                if ($Line.Length -lt 3) { return $False }
                $FilePath = $Line.Substring(3).Trim()

                foreach ($Path in $RelevantPaths) {
                    if ($FilePath -like "$Path*") { return $True }
                }
                return $False
            }

            if ($RelevantChanges) {
                $Result.status = "FAIL"
                $StatusLines = $RelevantChanges -split "`n" | Where-Object { $_ -match '\S' }
                $Result.message = "Uncommitted changes in feature or governance files ($($StatusLines.Count) file(s))"

                foreach ($Line in $StatusLines) {
                    if ($Line -match '^(.{2})\s+(.+)$') {
                        $StatusCode = $Matches[1].Trim()
                        $FilePath = $Matches[2].Trim()

                        $StatusMessage = switch ($StatusCode) {
                            "M"  { "Modified" }
                            "MM" { "Modified (staged and unstaged)" }
                            "A"  { "Added (staged)" }
                            "AM" { "Added and modified" }
                            "D"  { "Deleted" }
                            "R"  { "Renamed" }
                            "??" { "Untracked" }
                            default { "Changed ($StatusCode)" }
                        }

                        $Result.failures += @{
                            file = $FilePath
                            status = $StatusCode
                            message = $StatusMessage
                        }
                    }
                }
            } else {
                $Result.message = "No uncommitted changes in relevant paths - ready for archive"
            }
        } else {
            $Result.message = "Working tree clean - ready for archive"
        }
    }
    catch {
        $Result.status = "ERROR"
        $Result.message = "Git status command failed: $_"
    }
    finally {
        Pop-Location
    }

    return $Result
}

# Main Logic
Write-Verbose "Validation starting..."
Write-Verbose "Mode: $(if ($Strict) { 'STRICT (Constitution Compliance)' } else { 'Standard' })"

# Load constitution rules if in strict mode
if ($Strict) {
    Write-Verbose "Loading constitution rules..."
    $ConstitutionRules = Import-ConstitutionRules
    Write-Verbose "Loaded $($ConstitutionRules.CorePrinciples.Count) core principles and $($ConstitutionRules.QualityStandards.Count) quality standards"
}

$AllErrors = @()
$ConstitutionResult = $Null
$DeltaResults = @()
$ReqIdResults = @()

# Global validation checks (not target-specific)
$PlaceholderResult = Test-PlaceholderConsistency
if (-not $PlaceholderResult.valid) {
    foreach ($Err in $PlaceholderResult.errors) {
        $AllErrors += Write-ValidationError -Message $Err.error -File $Err.file -Line $Err.line
    }
}

if ($Target) {
    # Validate specific target
    if (Test-Path $Target -PathType Leaf) {
        Write-Verbose "Validating file: $Target"
        $SpecValidation = Test-SpecFile -FilePath $Target
        $AllErrors += $SpecValidation.errors
        if ($SpecValidation.reqIdValidation) {
            $ReqIdResults += $SpecValidation.reqIdValidation
        }

        # Delta spec validation
        Write-Verbose "Checking for delta spec..."
        $DeltaResult = Test-DeltaSpec -SpecPath $Target -RepoRoot $RepoRoot
        if ($DeltaResult.isDelta) {
            $DeltaResults += $DeltaResult
            if (-not $DeltaResult.valid) {
                foreach ($Err in $DeltaResult.errors) {
                    $AllErrors += Write-ValidationError -Message $Err.error -File $Err.file -Line $Err.line
                }
            }
            foreach ($Warn in $DeltaResult.warnings) {
                if (-not $Json) {
                    Write-Host "WARNING: $($Warn.warning)" -ForegroundColor Yellow
                    Write-Host "  File: $($Warn.file)" -ForegroundColor Gray
                }
            }
        }

        # Apply constitution checks in strict mode
        if ($Strict -and $ConstitutionRules) {
            Write-Verbose "Applying constitution compliance checks..."
            $AllErrors += Test-SpecFileConstitutionCompliance -FilePath $Target -Rules $ConstitutionRules

            # Run principle-level compliance check
            $FeatureDir = Split-Path -Parent $Target
            $ConstitutionResult = Test-ConstitutionCompliance -FeatureDir $FeatureDir
        }
    }
    elseif (Test-Path (Join-Path $RepoRoot "specs" "changes" $Target)) {
        $ChangeDir = Join-Path $RepoRoot "specs" "changes" $Target
        $SpecFile = Join-Path $ChangeDir "spec.md"

        Write-Verbose "Validating change: $Target"
        $IdError = Test-ChangeId -Id $Target
        if ($IdError) { $AllErrors += $IdError }

        if (Test-Path $SpecFile) {
            $SpecValidation = Test-SpecFile -FilePath $SpecFile
            $AllErrors += $SpecValidation.errors
            if ($SpecValidation.reqIdValidation) {
                $ReqIdResults += $SpecValidation.reqIdValidation
            }

            # Delta spec validation for main spec
            Write-Verbose "Checking for delta spec..."
            $DeltaResult = Test-DeltaSpec -SpecPath $SpecFile -RepoRoot $RepoRoot
            if ($DeltaResult.isDelta) {
                $DeltaResults += $DeltaResult
                if (-not $DeltaResult.valid) {
                    foreach ($Err in $DeltaResult.errors) {
                        $AllErrors += Write-ValidationError -Message $Err.error -File $Err.file -Line $Err.line
                    }
                }
                foreach ($Warn in $DeltaResult.warnings) {
                    if (-not $Json) {
                        Write-Host "WARNING: $($Warn.warning)" -ForegroundColor Yellow
                        Write-Host "  File: $($Warn.file)" -ForegroundColor Gray
                    }
                }
            }

            # Also check for delta specs in specs/ subdirectory
            $SpecsSubDir = Join-Path $ChangeDir "specs"
            if (Test-Path $SpecsSubDir) {
                $DeltaSpecFiles = Get-ChildItem -Path $SpecsSubDir -Filter "spec.md" -Recurse -ErrorAction SilentlyContinue
                foreach ($DeltaFile in $DeltaSpecFiles) {
                    Write-Verbose "Validating delta spec: $($DeltaFile.FullName)"
                    $DeltaResult = Test-DeltaSpec -SpecPath $DeltaFile.FullName -RepoRoot $RepoRoot
                    if ($DeltaResult.isDelta) {
                        $DeltaResults += $DeltaResult
                        if (-not $DeltaResult.valid) {
                            foreach ($Err in $DeltaResult.errors) {
                                $AllErrors += Write-ValidationError -Message $Err.error -File $Err.file -Line $Err.line
                            }
                        }
                        foreach ($Warn in $DeltaResult.warnings) {
                            if (-not $Json) {
                                Write-Host "WARNING: $($Warn.warning)" -ForegroundColor Yellow
                                Write-Host "  File: $($Warn.file)" -ForegroundColor Gray
                            }
                        }
                    }
                }
            }

            # Apply constitution checks in strict mode
            if ($Strict -and $ConstitutionRules) {
                Write-Verbose "Applying constitution compliance checks..."
                $AllErrors += Test-SpecFileConstitutionCompliance -FilePath $SpecFile -Rules $ConstitutionRules

                # Run principle-level compliance check
                $ConstitutionResult = Test-ConstitutionCompliance -FeatureDir $ChangeDir
            }
        }
    }
    else {
        $AllErrors += Write-ValidationError -Message "Target not found: $Target" -File $Target -Line 0
    }
}
else {
    # Validate current feature
    $FeatureDir = $EnvData.FEATURE_DIR
    $SpecFile = $EnvData.FEATURE_SPEC

    if (-not $FeatureDir -or -not $SpecFile) {
        if (-not $Json) {
            Write-Host "[speckit] No active change context found." -ForegroundColor Yellow
            Write-Host "  Tip: Set `$Env:SPECIFY_CHANGE_ID or run from a feature branch" -ForegroundColor Gray
            Write-Host "  Or specify a target: .\validate.ps1 -Target <change-id or file>" -ForegroundColor Gray
        }
        exit $ExitCodes.Success
    }

    Write-Verbose "Validating current feature: $FeatureDir"
    if (Test-Path $SpecFile) {
        $SpecValidation = Test-SpecFile -FilePath $SpecFile
        $AllErrors += $SpecValidation.errors
        if ($SpecValidation.reqIdValidation) {
            $ReqIdResults += $SpecValidation.reqIdValidation
        }

        # Delta spec validation for main spec
        Write-Verbose "Checking for delta spec..."
        $DeltaResult = Test-DeltaSpec -SpecPath $SpecFile -RepoRoot $RepoRoot
        if ($DeltaResult.isDelta) {
            $DeltaResults += $DeltaResult
            if (-not $DeltaResult.valid) {
                foreach ($Err in $DeltaResult.errors) {
                    $AllErrors += Write-ValidationError -Message $Err.error -File $Err.file -Line $Err.line
                }
            }
            foreach ($Warn in $DeltaResult.warnings) {
                if (-not $Json) {
                    Write-Host "WARNING: $($Warn.warning)" -ForegroundColor Yellow
                    Write-Host "  File: $($Warn.file)" -ForegroundColor Gray
                }
            }
        }

        # Also check for delta specs in specs/ subdirectory
        $SpecsSubDir = Join-Path $FeatureDir "specs"
        if (Test-Path $SpecsSubDir) {
            $DeltaSpecFiles = Get-ChildItem -Path $SpecsSubDir -Filter "spec.md" -Recurse -ErrorAction SilentlyContinue
            foreach ($DeltaFile in $DeltaSpecFiles) {
                Write-Verbose "Validating delta spec: $($DeltaFile.FullName)"
                $DeltaResult = Test-DeltaSpec -SpecPath $DeltaFile.FullName -RepoRoot $RepoRoot
                if ($DeltaResult.isDelta) {
                    $DeltaResults += $DeltaResult
                    if (-not $DeltaResult.valid) {
                        foreach ($Err in $DeltaResult.errors) {
                            $AllErrors += Write-ValidationError -Message $Err.error -File $Err.file -Line $Err.line
                        }
                    }
                    foreach ($Warn in $DeltaResult.warnings) {
                        if (-not $Json) {
                            Write-Host "WARNING: $($Warn.warning)" -ForegroundColor Yellow
                            Write-Host "  File: $($Warn.file)" -ForegroundColor Gray
                        }
                    }
                }
            }
        }

        # Apply constitution checks in strict mode
        if ($Strict -and $ConstitutionRules) {
            Write-Verbose "Applying constitution compliance checks..."
            $AllErrors += Test-SpecFileConstitutionCompliance -FilePath $SpecFile -Rules $ConstitutionRules

            # Run principle-level compliance check
            $ConstitutionResult = Test-ConstitutionCompliance -FeatureDir $FeatureDir
        }
    }
    else {
        Write-Verbose "No spec file found at: $SpecFile"
        if (-not $Json) {
            Write-Host "[speckit] Warning: No spec.md found in current feature" -ForegroundColor Yellow
        }
    }
}

# Filter out null errors
$AllErrors = $AllErrors | Where-Object { $_ }

# In strict mode, check if constitution compliance failed
$ConstitutionFailed = $False
if ($Strict -and $ConstitutionResult) {
    $ConstitutionFailed = -not $ConstitutionResult.compliant
}

# Run gate validations if -IncludeGates is specified
$GateResults = $Null
$GatesFailed = $False
if ($IncludeGates) {
    Write-Verbose "Running gate validations..."

    # Determine the feature directory for gate checks
    $GateFeatureDir = $Null
    if ($Target) {
        if (Test-Path $Target -PathType Leaf) {
            $GateFeatureDir = Split-Path -Parent $Target
        }
        elseif (Test-Path (Join-Path $RepoRoot "specs" "changes" $Target)) {
            $GateFeatureDir = Join-Path $RepoRoot "specs" "changes" $Target
        }
    }
    else {
        $GateFeatureDir = $EnvData.FEATURE_DIR
    }

    if ($GateFeatureDir -and (Test-Path $GateFeatureDir)) {
        $GateResults = Invoke-GateValidation -FeatureDir $GateFeatureDir
        $GatesFailed = $GateResults.overallStatus -ne "PASS"
    }
    else {
        Write-Verbose "Could not determine feature directory for gate validation"
    }
}

if ($Json) {
    $IsValid = ($AllErrors.Count -eq 0) -and (-not $ConstitutionFailed) -and (-not $GatesFailed)
    $Output = @{
        valid  = $IsValid
        strict = $Strict.IsPresent
        includeGates = $IncludeGates.IsPresent
        errors = $AllErrors
    }

    # Include REQ-ID validation results if any were found
    if ($ReqIdResults.Count -gt 0) {
        $AllReqIds = @()
        $AllDuplicates = @()
        $AllSequenceGaps = @()
        $ReqIdWarnings = @()

        foreach ($ReqResult in $ReqIdResults) {
            $AllReqIds += $ReqResult.reqIds
            $AllDuplicates += $ReqResult.duplicates
            $AllSequenceGaps += $ReqResult.sequenceGaps
            $ReqIdWarnings += $ReqResult.warnings
        }

        $Output.requirementIds = @{
            count = $AllReqIds.Count
            ids = ($AllReqIds | Sort-Object -Unique)
            duplicates = $AllDuplicates
            sequenceGaps = $AllSequenceGaps
            warnings = $ReqIdWarnings
            valid = ($AllDuplicates.Count -eq 0)
        }
    }

    # Include delta validation results if any delta specs were found
    if ($DeltaResults.Count -gt 0) {
        $Output.deltaSpecs = @{
            count = $DeltaResults.Count
            results = $DeltaResults
            allValid = ($DeltaResults | Where-Object { -not $_.valid }).Count -eq 0
        }
    }

    # Include constitution compliance in JSON output when in strict mode
    if ($Strict -and $ConstitutionResult) {
        $Output.constitution = $ConstitutionResult
    }

    # Include gate results in JSON output when -IncludeGates is specified
    if ($IncludeGates -and $GateResults) {
        $Output.gates = $GateResults
    }

    $ErrorMessages = $AllErrors | ForEach-Object { $_.error }
    $Status = if ($IsValid) { "success" } else { "validation_error" }
    if ($IsValid) {
        Write-ValidationAuditEntry -Outcome 'success'
    } else {
        Write-ValidationAuditEntry -Outcome 'failure' -ErrorRecord ($ErrorMessages -join '; ')
    }
    Write-JsonResult -Result (New-JsonResult -Status $Status -ScriptName "validate.ps1" -Data $Output -Errors $ErrorMessages)
}
else {
    # Display REQ-ID validation results if any requirements were found
    if ($ReqIdResults.Count -gt 0) {
        $TotalReqIds = 0
        $TotalDuplicates = 0
        $TotalGaps = 0

        foreach ($ReqResult in $ReqIdResults) {
            $TotalReqIds += $ReqResult.reqIds.Count
            $TotalDuplicates += $ReqResult.duplicates.Count
            $TotalGaps += $ReqResult.sequenceGaps.Count
        }

        if ($TotalReqIds -gt 0) {
            Write-Host "`n[speckit] REQ-ID Validation" -ForegroundColor Cyan
            Write-Host ("=" * 45) -ForegroundColor DarkGray

            $StatusColor = if ($TotalDuplicates -eq 0) { "Green" } else { "Red" }
            $StatusIcon = if ($TotalDuplicates -eq 0) { "[PASS]" } else { "[FAIL]" }

            Write-Host "$StatusIcon " -ForegroundColor $StatusColor -NoNewline
            Write-Host "Found $TotalReqIds requirement ID(s)" -ForegroundColor White

            if ($TotalDuplicates -gt 0) {
                Write-Host "       Duplicates: $TotalDuplicates (ERROR)" -ForegroundColor Red
            }

            if ($TotalGaps -gt 0) {
                Write-Host "       Sequence Gaps: $TotalGaps (WARNING)" -ForegroundColor Yellow
            }

            Write-Host ("=" * 45) -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    # Display delta spec validation results if any were found
    if ($DeltaResults.Count -gt 0) {
        Write-Host "`n[speckit] Delta Spec Validation" -ForegroundColor Cyan
        Write-Host ("=" * 45) -ForegroundColor DarkGray

        foreach ($Delta in $DeltaResults) {
            $StatusColor = if ($Delta.valid) { "Green" } else { "Red" }
            $StatusIcon = if ($Delta.valid) { "[PASS]" } else { "[FAIL]" }

            # Extract relative path for display
            $DisplayPath = $Delta.errors[0].file
            if (-not $DisplayPath -and $Delta.warnings.Count -gt 0) {
                $DisplayPath = $Delta.warnings[0].file
            }
            if (-not $DisplayPath) {
                $DisplayPath = "(delta spec)"
            }

            Write-Host "$StatusIcon " -ForegroundColor $StatusColor -NoNewline
            Write-Host "Delta Spec" -ForegroundColor White

            # Show which sections are present
            $Sections = @()
            if ($Delta.sections.added) { $Sections += "ADDED" }
            if ($Delta.sections.modified) { $Sections += "MODIFIED" }
            if ($Delta.sections.removed) { $Sections += "REMOVED" }
            Write-Host "       Sections: $($Sections -join ', ')" -ForegroundColor Gray

            # Show warnings count if any
            if ($Delta.warnings.Count -gt 0) {
                Write-Host "       Warnings: $($Delta.warnings.Count)" -ForegroundColor Yellow
            }
        }

        Write-Host ("=" * 45) -ForegroundColor DarkGray

        $AllDeltasValid = ($DeltaResults | Where-Object { -not $_.valid }).Count -eq 0
        if ($AllDeltasValid) {
            Write-Host "[speckit] Delta Specs: VALID ($($DeltaResults.Count) spec(s))" -ForegroundColor Green
        }
        else {
            $InvalidCount = ($DeltaResults | Where-Object { -not $_.valid }).Count
            Write-Host "[speckit] Delta Specs: INVALID ($InvalidCount of $($DeltaResults.Count) failed)" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Display constitution compliance results in strict mode
    if ($Strict -and $ConstitutionResult) {
        Write-Host "`n[speckit] Constitution Compliance Check" -ForegroundColor Cyan
        Write-Host ("=" * 45) -ForegroundColor DarkGray

        foreach ($Principle in $ConstitutionResult.principles) {
            $StatusColor = switch ($Principle.status) {
                "PASS" { "Green" }
                "WARN" { "Yellow" }
                "FAIL" { "Red" }
                default { "White" }
            }

            $StatusIcon = switch ($Principle.status) {
                "PASS" { "[PASS]" }
                "WARN" { "[WARN]" }
                "FAIL" { "[FAIL]" }
                default { "[????]" }
            }

            Write-Host "$StatusIcon " -ForegroundColor $StatusColor -NoNewline
            Write-Host "$($Principle.name)" -ForegroundColor White
            Write-Host "       $($Principle.details)" -ForegroundColor Gray
        }

        Write-Host ("=" * 45) -ForegroundColor DarkGray

        if ($ConstitutionResult.compliant) {
            Write-Host "[speckit] Constitution: COMPLIANT" -ForegroundColor Green
        }
        else {
            Write-Host "[speckit] Constitution: NON-COMPLIANT" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Display gate validation results when -IncludeGates is specified
    if ($IncludeGates -and $GateResults) {
        Write-Host "`n[speckit] Gate Validation Check" -ForegroundColor Cyan
        Write-Host ("=" * 50) -ForegroundColor DarkGray

        foreach ($Gate in $GateResults.gates) {
            $StatusColor = switch ($Gate.status) {
                "PASS" { "Green" }
                "FAIL" { "Red" }
                "ERROR" { "Yellow" }
                default { "White" }
            }

            $StatusIcon = switch ($Gate.status) {
                "PASS" { "[PASS]" }
                "FAIL" { "[FAIL]" }
                "ERROR" { "[ERR ]" }
                default { "[????]" }
            }

            Write-Host "$StatusIcon " -ForegroundColor $StatusColor -NoNewline
            Write-Host "Gate $($Gate.gate) ($($Gate.name))" -ForegroundColor White
            Write-Host "       $($Gate.message)" -ForegroundColor Gray

            # Show failures if any
            if ($Gate.failures.Count -gt 0) {
                foreach ($Failure in $Gate.failures) {
                    if ($Failure.line) {
                        Write-Host "         - $($Failure.file):$($Failure.line)" -ForegroundColor Yellow
                        Write-Host "           $($Failure.pattern)" -ForegroundColor DarkGray
                    } else {
                        Write-Host "         - $($Failure.file): $($Failure.message)" -ForegroundColor Yellow
                    }
                }
            }
        }

        Write-Host ("=" * 50) -ForegroundColor DarkGray

        if ($GateResults.overallStatus -eq "PASS") {
            Write-Host "[speckit] Gates: ALL PASSED" -ForegroundColor Green
        }
        elseif ($GateResults.overallStatus -eq "FAIL") {
            Write-Host "[speckit] Gates: FAILED ($($GateResults.totalFailures) failure(s))" -ForegroundColor Red
        }
        else {
            Write-Host "[speckit] Gates: ERROR" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    if ($AllErrors.Count -eq 0 -and -not $ConstitutionFailed -and -not $GatesFailed) {
        $ModeText = if ($Strict) { " (STRICT MODE)" } else { "" }
        $GateText = if ($IncludeGates) { " [+GATES]" } else { "" }
        Write-Host "[speckit] Validation PASSED$ModeText$GateText" -ForegroundColor Green
        Write-ValidationAuditEntry -Outcome 'success'
        exit $ExitCodes.Success
    }
    else {
        $ModeText = if ($Strict) { " (STRICT MODE)" } else { "" }
        $GateText = if ($IncludeGates) { " [+GATES]" } else { "" }
        $ErrorCount = $AllErrors.Count

        $FailureDetails = @()
        if ($ErrorCount -gt 0) {
            $FailureDetails += "$ErrorCount error(s)"
        }
        if ($ConstitutionFailed) {
            $FailedPrinciples = ($ConstitutionResult.principles | Where-Object { $_.status -eq "FAIL" }).Count
            $FailureDetails += "$FailedPrinciples constitution violation(s)"
        }
        if ($GatesFailed -and $GateResults) {
            $FailureDetails += "$($GateResults.totalFailures) gate failure(s)"
        }

        $FailureSummary = $FailureDetails -join " and "
        Write-Host "[speckit] Validation FAILED$ModeText$GateText with $FailureSummary" -ForegroundColor Red

        if ($Strict) {
            Write-Host "`nTo see constitution rules: Get-Content specs/memory/constitution.md" -ForegroundColor Yellow
        }

        Write-ValidationAuditEntry -Outcome 'failure' -ErrorRecord $FailureSummary
        exit $ExitCodes.Validation
    }
}

