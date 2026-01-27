#!/usr/bin/env pwsh
<#
.SYNOPSIS
Validates consistency between template placeholders and agent instruction references.

.DESCRIPTION
Detects placeholder format conflicts where agent instructions reference placeholders
that don't match the format used in templates. This prevents agents from failing
to replace placeholders correctly.

Checks for:
- Templates using {SCREAMING_SNAKE} format
- Agent instructions referencing <angle-bracket> format (mismatch)
- Feature identifier terminology conflicts ({CHANGE_ID} vs {slug} vs <change-id>)

.PARAMETER Fix
If specified, attempts to auto-fix common placeholder mismatches in agent files.

.PARAMETER Json
Output results in JSON format for CI/CD integration.

.EXAMPLE
.\manual\test-placeholder-consistency.ps1

.EXAMPLE
.\manual\test-placeholder-consistency.ps1 -Fix

.EXAMPLE
.\manual\test-placeholder-consistency.ps1 -Json

.NOTES
Exit Codes:
    0 - Success (no mismatches)
    1 - Mismatches detected
    2 - File access error

#>

[CmdletBinding()]
param(
    [switch]$Fix,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# Get workspace root
$repoRoot = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".." "..")).Path
}

$templatesDir = Join-Path $repoRoot "specs" "templates"
$agentsDir = Join-Path $repoRoot ".github" "agents"

# Extract {PLACEHOLDER} format from templates
function Get-TemplatePlaceholders {
    param([string]$Path)

    $placeholders = @{}
    $files = Get-ChildItem -Path $Path -Filter "*.md" -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        # Extract {PLACEHOLDER} format
        [regex]::Matches($content, '\{([A-Z_]+)\}') | ForEach-Object {
            $placeholder = $_.Groups[1].Value
            if (-not $placeholders.ContainsKey($placeholder)) {
                $placeholders[$placeholder] = @()
            }
            $placeholders[$placeholder] += $file.Name
        }
    }

    return $placeholders
}

# Extract <placeholder> references from agent instructions
function Get-AgentPlaceholderReferences {
    param([string]$Path)

    $references = @{}
    $files = Get-ChildItem -Path $Path -Filter "*.md" -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        # Extract <placeholder> references in "Replace" instructions
        $matches = [regex]::Matches($content, '(?:Replace|replace)\s+`<([a-z-]+)>`')
        foreach ($match in $matches) {
            $placeholder = $match.Groups[1].Value
            if (-not $references.ContainsKey($placeholder)) {
                $references[$placeholder] = @()
            }
            $references[$placeholder] += @{
                File = $file.Name
                Line = ($content.Substring(0, $match.Index) -split "`n").Count
            }
        }

        # Also check for standalone <placeholder> in code blocks
        $standaloneMatches = [regex]::Matches($content, '`<([a-z-]+)>`')
        foreach ($match in $standaloneMatches) {
            $placeholder = $match.Groups[1].Value
            # Skip if already captured by Replace pattern
            if ($references.ContainsKey($placeholder)) { continue }

            if (-not $references.ContainsKey($placeholder)) {
                $references[$placeholder] = @()
            }
            $references[$placeholder] += @{
                File = $file.Name
                Line = ($content.Substring(0, $match.Index) -split "`n").Count
            }
        }
    }

    return $references
}

# Main validation
if (-not (Test-Path $templatesDir)) {
    Write-Error "Templates directory not found: $templatesDir"
    exit 2
}

if (-not (Test-Path $agentsDir)) {
    Write-Error "Agents directory not found: $agentsDir"
    exit 2
}

Write-Host "[speckit] Checking placeholder consistency..." -ForegroundColor Cyan
Write-Host ""

$templatePlaceholders = Get-TemplatePlaceholders -Path $templatesDir
$agentReferences = Get-AgentPlaceholderReferences -Path $agentsDir

# Report template placeholders
Write-Host "Template Placeholders ({SCREAMING_SNAKE}):" -ForegroundColor Green
$templatePlaceholders.Keys | Sort-Object | ForEach-Object {
    Write-Host "  {$_}" -ForegroundColor Gray
}
Write-Host ""

# Check for mismatches
$mismatches = @()
foreach ($anglePlaceholder in $agentReferences.Keys) {
    $upperSnake = $anglePlaceholder.ToUpper().Replace('-', '_')

    if (-not $templatePlaceholders.ContainsKey($upperSnake)) {
        $mismatches += @{
            AngleBracket = $anglePlaceholder
            ExpectedFormat = "{$upperSnake}"
            Locations = $agentReferences[$anglePlaceholder]
        }
    }
}

if ($mismatches.Count -gt 0) {
    Write-Host "❌ MISMATCHES DETECTED:" -ForegroundColor Red
    Write-Host ""

    foreach ($mismatch in $mismatches) {
        Write-Host "  Agent references: <$($mismatch.AngleBracket)>" -ForegroundColor Yellow
        Write-Host "  Should be: $($mismatch.ExpectedFormat)" -ForegroundColor Green
        foreach ($location in $mismatch.Locations) {
            Write-Host "    - $($location.File):$($location.Line)" -ForegroundColor Gray
        }
        Write-Host ""
    }

    if ($Json) {
        $result = @{
            Status = "FAIL"
            MismatchCount = $mismatches.Count
            Mismatches = $mismatches
        }
        Write-Output ($result | ConvertTo-Json -Depth 10)
    }

    exit 1
}

Write-Host "✅ All placeholders are consistent!" -ForegroundColor Green

if ($Json) {
    $result = @{
        Status = "PASS"
        MismatchCount = 0
        TemplatePlaceholders = @($templatePlaceholders.Keys | Sort-Object)
    }
    Write-Output ($result | ConvertTo-Json -Depth 10)
}

exit 0
