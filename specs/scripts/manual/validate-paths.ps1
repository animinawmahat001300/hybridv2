#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates that all SpecKit agent files use workspace-relative paths.

.DESCRIPTION
    Scans all 11 SpecKit agent files for invalid path patterns.
    In the hybrid workspace, agents should use `specs/scripts/`, `specs/templates/`, etc.
    NOT `hybrid/specs/` (absolute from root) or `.specify/` (wrong workspace).

.PARAMETER AgentDir
    Directory containing agent files. Default: ".github/agents"

.PARAMETER Json
    Output results in JSON format.

.PARAMETER Strict
    Fail if ANY non-workspace-relative paths are found (even warnings).

.OUTPUTS
    Summary of path validation results. Exit code 0 = PASS, 1 = FAIL.

.EXAMPLE
    ./validate-paths.ps1
    Validates all agent files and outputs results.

.EXAMPLE
    ./validate-paths.ps1 -Json
    Outputs results in JSON format.

.EXAMPLE
    ./validate-paths.ps1 -Strict
    Fails on any non-standard path patterns.
#>

param(
    [string]$AgentDir = ".github/agents",
    [switch]$Json,
    [switch]$Strict
)

# Determine workspace root
$scriptDir = $PSScriptRoot
$workspaceRoot = (Resolve-Path (Join-Path $scriptDir ".." ".." "..")).Path

# Define invalid patterns for hybrid workspace
$invalidPatterns = @(
    @{ Pattern = 'hybrid/specs/'; Reason = "Absolute path from root - should be workspace-relative 'specs/'" }
    @{ Pattern = '\.specify/scripts/'; Reason = "Wrong workspace - .specify/ is in root, not hybrid" }
    @{ Pattern = '\.specify/templates/'; Reason = "Wrong workspace - .specify/ is in root, not hybrid" }
    @{ Pattern = '\.specify/memory/'; Reason = "Wrong workspace - use 'specs/memory/' instead" }
)

# Warning patterns (not blocking by default)
$warningPatterns = @(
    @{ Pattern = 'c:\\'; Reason = "Hardcoded Windows path" }
    @{ Pattern = '/Users/'; Reason = "Hardcoded macOS path" }
    @{ Pattern = '/home/'; Reason = "Hardcoded Linux path" }
)

# Expected agent files
$expectedAgents = @(
    'speckit.specify.agent.md',
    'speckit.clarify.agent.md',
    'speckit.plan.agent.md',
    'speckit.tasks.agent.md',
    'speckit.checklist.agent.md',
    'speckit.taskstoissues.agent.md',
    'speckit.analyze.agent.md',
    'speckit.implement.agent.md',
    'speckit.archive.agent.md',
    'speckit.document.agent.md',
    'speckit.constitution.agent.md'
)

# Results tracking
$results = @{
    status = "PASS"
    agents_checked = 0
    agents_passed = 0
    agents_failed = 0
    failures = @()
    warnings = @()
    timestamp = (Get-Date -Format "o")
}

# Resolve agent directory
$agentPath = Join-Path $workspaceRoot $AgentDir
if (-not (Test-Path $agentPath)) {
    $results.status = "ERROR"
    $results.failures += "Agent directory not found: $agentPath"

    if ($Json) {
        $results | ConvertTo-Json -Depth 10
    } else {
        Write-Host "ERROR: Agent directory not found: $agentPath" -ForegroundColor Red
    }
    exit 2
}

# Validate each expected agent file
foreach ($agentFile in $expectedAgents) {
    $filePath = Join-Path $agentPath $agentFile
    $results.agents_checked++

    if (-not (Test-Path $filePath)) {
        $results.agents_failed++
        $results.failures += @{
            agent = $agentFile
            type = "MISSING"
            message = "Agent file not found"
        }
        continue
    }

    $content = Get-Content $filePath -Raw
    $agentFailed = $false

    # Check invalid patterns
    foreach ($check in $invalidPatterns) {
        if ($content -match [regex]::Escape($check.Pattern)) {
            $agentFailed = $true
            $matches = Select-String -Path $filePath -Pattern ([regex]::Escape($check.Pattern)) -AllMatches
            foreach ($match in $matches) {
                $results.failures += @{
                    agent = $agentFile
                    type = "INVALID_PATH"
                    pattern = $check.Pattern
                    reason = $check.Reason
                    line = $match.LineNumber
                    content = $match.Line.Trim()
                }
            }
        }
    }

    # Check warning patterns
    foreach ($check in $warningPatterns) {
        if ($content -match $check.Pattern) {
            $matches = Select-String -Path $filePath -Pattern $check.Pattern -AllMatches
            foreach ($match in $matches) {
                $results.warnings += @{
                    agent = $agentFile
                    type = "WARNING"
                    pattern = $check.Pattern
                    reason = $check.Reason
                    line = $match.LineNumber
                }
            }
            if ($Strict) {
                $agentFailed = $true
            }
        }
    }

    if ($agentFailed) {
        $results.agents_failed++
    } else {
        $results.agents_passed++
    }
}

# Determine overall status
if ($results.agents_failed -gt 0 -or $results.failures.Count -gt 0) {
    $results.status = "FAIL"
}

# Output results
if ($Json) {
    $results | ConvertTo-Json -Depth 10
} else {
    Write-Host ""
    Write-Host "=== Path Validation Results ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Agents checked: $($results.agents_checked)"
    Write-Host "Agents passed:  $($results.agents_passed)" -ForegroundColor $(if ($results.agents_passed -eq $results.agents_checked) { "Green" } else { "Yellow" })
    Write-Host "Agents failed:  $($results.agents_failed)" -ForegroundColor $(if ($results.agents_failed -eq 0) { "Green" } else { "Red" })
    Write-Host ""

    if ($results.failures.Count -gt 0) {
        Write-Host "FAILURES:" -ForegroundColor Red
        foreach ($failure in $results.failures) {
            if ($failure -is [string]) {
                Write-Host "  - $failure" -ForegroundColor Red
            } else {
                Write-Host "  - $($failure.agent):$($failure.line) - $($failure.type): $($failure.reason)" -ForegroundColor Red
                if ($failure.content) {
                    Write-Host "      $($failure.content)" -ForegroundColor DarkGray
                }
            }
        }
        Write-Host ""
    }

    if ($results.warnings.Count -gt 0) {
        Write-Host "WARNINGS:" -ForegroundColor Yellow
        foreach ($warning in $results.warnings) {
            Write-Host "  - $($warning.agent):$($warning.line) - $($warning.reason)" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    Write-Host "Status: $($results.status)" -ForegroundColor $(if ($results.status -eq "PASS") { "Green" } else { "Red" })
}

# Exit with appropriate code
if ($results.status -eq "PASS") {
    exit 0
} elseif ($results.status -eq "ERROR") {
    exit 2
} else {
    exit 1
}
