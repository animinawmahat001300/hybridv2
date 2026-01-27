#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Analyzes markdown link format patterns across the codebase
.DESCRIPTION
    Detects and reports on markdown link format inconsistencies:
    - Plain inline links vs backticked labels
    - Backticks in paths (invalid)
    - Reference-style links
.EXAMPLE
    .\analyze-markdown-links.ps1
#>

$ErrorActionPreference = 'Stop'

Write-Host "=== MARKDOWN LINK PATTERN ANALYSIS ===" -ForegroundColor Cyan
Write-Host ""

$Files = Get-ChildItem -Path $PSScriptRoot\..\..\.. -Recurse -Filter "*.md" | Where-Object {
    $_.FullName -notmatch '[\\/](node_modules|\.git|\.agent_work)[\\/]'
}

Write-Host "Analyzing $($Files.Count) markdown files..." -ForegroundColor Gray
Write-Host ""

$Counts = @{
    'inline_plain' = 0
    'inline_backtick_label' = 0
    'inline_backtick_path' = 0
    'reference_style' = 0
}

$FileExamples = @{
    'inline_backtick_label' = @()
    'inline_backtick_path' = @()
    'plain_examples' = @()
}

$RepoRoot = (Get-Item $PSScriptRoot\..\..\.. -Force).FullName

foreach ($File in $Files) {
    $Content = Get-Content $File.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $Content) { continue }

    $RelPath = $File.FullName.Replace($RepoRoot, '.').Replace('\', '/')

    # Count plain inline links [text](url) - excluding backticked ones
    $PlainMatches = [regex]::Matches($Content, '\[([^\]`\r\n]+)\]\(([^\)`\r\n]+)\)')
    if ($PlainMatches.Count -gt 0) {
        $Counts.inline_plain += $PlainMatches.Count
        if ($FileExamples.plain_examples.Count -lt 3) {
            $Example = $PlainMatches[0].Value
            $FileExamples.plain_examples += "$RelPath : $Example"
        }
    }

    # Count backticked labels [`text`](url)
    $BacktickLabelMatches = [regex]::Matches($Content, '\[`([^`\r\n]+)`\]\(([^\)\r\n]+)\)')
    if ($BacktickLabelMatches.Count -gt 0) {
        $Counts.inline_backtick_label += $BacktickLabelMatches.Count
        $Example = $BacktickLabelMatches[0].Value
        $FileExamples.inline_backtick_label += "$RelPath : $($BacktickLabelMatches.Count) occurrences, e.g. $Example"
    }

    # Count backticked paths [text](`url`) - INVALID
    $BacktickPathMatches = [regex]::Matches($Content, '\]\(`([^`\r\n]+)`\)')
    if ($BacktickPathMatches.Count -gt 0) {
        $Counts.inline_backtick_path += $BacktickPathMatches.Count
        $Example = $BacktickPathMatches[0].Value
        $FileExamples.inline_backtick_path += "$RelPath : $($BacktickPathMatches.Count) occurrences, e.g. $Example"
    }

    # Count reference style [text][ref]
    $RefStyleMatches = [regex]::Matches($Content, '\[([^\]\r\n]+)\]\[([^\]\r\n]*)\]')
    $Counts.reference_style += $RefStyleMatches.Count
}

Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "PATTERN COUNTS" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Plain inline links [text](url):" -NoNewline
Write-Host "     $($Counts.inline_plain)" -ForegroundColor Green
Write-Host "  Backticked labels [``text``](url):" -NoNewline
Write-Host "   $($Counts.inline_backtick_label)" -ForegroundColor $(if ($Counts.inline_backtick_label -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  Backticked paths [text](``url``):" -NoNewline
Write-Host "    $($Counts.inline_backtick_path) " -NoNewline -ForegroundColor $(if ($Counts.inline_backtick_path -gt 0) { 'Red' } else { 'Green' })
if ($Counts.inline_backtick_path -gt 0) {
    Write-Host "⚠️ INVALID" -ForegroundColor Red
} else {
    Write-Host "✓" -ForegroundColor Green
}
Write-Host "  Reference style [text][ref]:" -NoNewline
Write-Host "       $($Counts.reference_style)" -ForegroundColor $(if ($Counts.reference_style -gt 0) { 'Cyan' } else { 'Green' })
Write-Host ""

$TotalInline = $Counts.inline_plain + $Counts.inline_backtick_label
if ($TotalInline -gt 0) {
    $PercentPlain = [math]::Round(($Counts.inline_plain / $TotalInline) * 100, 1)
    $PercentBacktick = [math]::Round(($Counts.inline_backtick_label / $TotalInline) * 100, 1)

    Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "DOMINANT PATTERN" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Plain labels:      $PercentPlain%" -ForegroundColor Green
    Write-Host "  Backticked labels: $PercentBacktick%" -ForegroundColor Yellow
    Write-Host ""
    if ($PercentPlain -gt 75) {
        Write-Host "✓ STANDARD: Use plain labels [text](url)" -ForegroundColor Green
    } else {
        Write-Host "⚠️ NO CLEAR DOMINANT PATTERN" -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($FileExamples.plain_examples.Count -gt 0) {
    Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "PLAIN LINK EXAMPLES (STANDARD)" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    $FileExamples.plain_examples | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Gray
    }
    Write-Host ""
}

if ($FileExamples.inline_backtick_label.Count -gt 0) {
    Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "FILES WITH BACKTICKED LABELS" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    $FileExamples.inline_backtick_label | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "NOTE: These should be normalized to plain labels unless they're" -ForegroundColor Gray
    Write-Host "      showing pattern examples in meta-documentation." -ForegroundColor Gray
    Write-Host ""
}

if ($FileExamples.inline_backtick_path.Count -gt 0) {
    Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "⚠️ CRITICAL: INVALID BACKTICKED PATHS" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    $FileExamples.inline_backtick_path | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "ACTION REQUIRED: Remove backticks from URL paths!" -ForegroundColor Red
    Write-Host "Correct format: [text](url)" -ForegroundColor Green
    Write-Host ""
}

Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "ANALYSIS COMPLETE" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""

if ($Counts.inline_backtick_path -gt 0) {
    exit 1
} else {
    exit 0
}

