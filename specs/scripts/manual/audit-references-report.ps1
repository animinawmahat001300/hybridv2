#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Preview what audit-references.ps1 would scan: scope, file list, and reference counts.

.DESCRIPTION
    Companion script to audit-references.ps1. Reports scanning scope without
    performing full validation:
    - Repository root
    - Roots to be scanned
    - Excluded directories
    - Allowed file extensions
    - Tree view of candidate files with reference counts
    - Per-file reference details (normalized path, resolved path, exists status)

    Use this script to:
    1. Verify scan scope before running full audit
    2. Preview reference counts per file
    3. Identify high-reference files for focused review
    4. Debug path resolution behavior

    This script shares the same file enumeration and reference extraction logic
    as audit-references.ps1 but stops short of full validation. Useful for
    understanding what will be audited.

.PARAMETER Roots
    One or more directories to scan. Defaults to current directory (".").
    Paths are resolved relative to repository root if not absolute.
    Example: -Roots "specs", "docs", ".github"

.PARAMETER RepoRootOverride
    Override the detected repository root. Mainly for tooling.
    Must be a valid directory path.

.PARAMETER MaxFiles
    Maximum number of files to display in tree view. Defaults to 200.
    Increase to see more files; decrease for faster output with large workspaces.

.PARAMETER MaxRefsPerFile
    Maximum number of references to display per file. Defaults to 50.
    Increase for more detail; decrease for overview only.

.PARAMETER Help
    Display this help message and exit.

.EXAMPLE
    .\audit-references-report.ps1
    Preview scan scope for current directory.

.EXAMPLE
    .\audit-references-report.ps1 -Roots "specs", "docs"
    Preview what would be scanned for specific directories.

.EXAMPLE
    .\audit-references-report.ps1 -MaxFiles 500 -MaxRefsPerFile 100
    Increase limits for detailed preview of large workspace.

.EXAMPLE
    .\audit-references-report.ps1 -Roots "specs/scripts" | Out-File report.txt
    Save preview to file for review.

.NOTES
    Exit Codes:
      0 - Success
      1 - Error (invalid roots, no roots resolved, etc.)

    Output Format:
      1. Summary: Repo root, scan roots, exclusions, extensions, file count
      2. Tree: Hierarchical view of files with reference counts
      3. References: Per-file list of references with [OK]/[X] status
      4. Command: Suggested audit-references.ps1 invocation

    Excluded Directories:
      .git, node_modules, dist, build, out, target, .cache, .next, .turbo,
      .vite, .agent_work, coverage, bin, obj, .idea, .vscode

    Allowed Extensions:
      .md, .ps1, .psm1, .json, .jsonc, .yml, .yaml, .txt, .js, .jsx, .ts,
      .tsx, .cs, .py, .java, .go, .rb, .php, .sh

    Reference Patterns:
      - Markdown links: [text](path)
      - Markdown reference-style: [id]: path
      - filepath: markers
      - Quoted/backticked paths
      - Common path tokens (.github/, specs/, src/, tests/, docs/)

    Issue #10 (Code Duplication):
      This script shares pattern matching, normalization, and resolution logic
      with audit-references.ps1. Refactoring to shared module is deferred.
      Track progress in Issue #10.

    Relationship to audit-references.ps1:
      - This script: Preview scope, reference counts, path resolution
      - audit-references.ps1: Full validation, strict mode, JSON output
      Use this script first to verify scope, then run audit-references.ps1.

    Related Scripts:
      - audit-references.ps1: Full reference audit with validation
    - common.ps1: Shared utility functions (Get-RepositoryRoot, etc.)

.LINK
    docs/speckit/ARCHITECTURE_OVERVIEW.md

.LINK
    docs/speckit/architecture/ADR-0002-file-based-state.md
#>
[CmdletBinding()]
param(
    [string[]]$Roots = @("."),
    [string]$RepoRootOverride,
    [int]$MaxFiles = 200,
    [int]$MaxRefsPerFile = 50,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Display help if requested
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

. (Join-Path $PSScriptRoot ".." "common.ps1")

# Resolve repo root with optional override
if ($RepoRootOverride) {
    try {
        $RepoRoot = (Resolve-Path $RepoRootOverride).Path
    }
    catch {
        Write-Error "RepoRootOverride '$RepoRootOverride' is invalid."
        exit 1
    }
} else {
    $RepoRoot = Get-RepositoryRoot
}

$ExcludeDirs = @(
    ".git", "node_modules", "dist", "build", "out", "target",
    ".cache", ".next", ".turbo", ".vite", ".agent_work", "coverage",
    "bin", "obj", ".idea", ".vscode"
)

$ExtAllow = @(
    ".md", ".ps1", ".psm1", ".json", ".jsonc", ".yml", ".yaml", ".txt",
    ".js", ".jsx", ".ts", ".tsx", ".cs", ".py", ".java", ".go", ".rb", ".php", ".sh"
)

# Resolve roots
$RootsAbs = @()
foreach ($R in $Roots) {
    $P = if ([IO.Path]::IsPathRooted($R)) { $R } else { Join-Path $RepoRoot $R }
    $RootsAbs += $P
}

# Always include .github/agents if present (agents trigger audits and should be covered)
$AgentsDir = Join-Path $RepoRoot '.github/agents'
if (Test-Path -LiteralPath $AgentsDir) {
    $RootsAbs += $AgentsDir
}

# Deduplicate roots
$RootsAbs = $RootsAbs | Sort-Object -Unique

if ($RootsAbs.Count -eq 0) {
    Write-Error "No roots provided or resolved."
    exit 1
}

function Get-TextFiles {
    param([string]$Base)

    Get-ChildItem -LiteralPath $Base -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $Full = $_.FullName

            foreach ($D in $ExcludeDirs) {
                if ($Full -match ([regex]::Escape("\\$D\\"))) { return $False }
                if ($Full -match ([regex]::Escape("/$D/"))) { return $False }
            }

            return $ExtAllow -contains $_.Extension.ToLowerInvariant()
        }
}

$Files = @()
foreach ($R in $RootsAbs) {
    if (Test-Path -LiteralPath $R -PathType Container) {
        $Files += Get-TextFiles -Base $R
    }
}

Write-Host "[speckit] Audit Reference Scope Report" -ForegroundColor Cyan
Write-Host "====================================="
Write-Host "Repo Root: $RepoRoot"
Write-Host "Roots: $($RootsAbs -join ', ')"
Write-Host "Excluded Dirs: $($ExcludeDirs -join ', ')"
Write-Host "Allowed Extensions: $($ExtAllow -join ', ')"
Write-Host "Candidate Files: $($Files.Count)" -ForegroundColor Yellow

if ($Files.Count -gt 0) {
    Write-Host "" -NoNewline
    Write-Host "Tree of scanned files (relative to repo root) with reference counts:" -ForegroundColor Yellow

    $RelFiles = $Files | ForEach-Object { $_.FullName.Substring($RepoRoot.Length).TrimStart([char]92,[char]47) }
    $RelFilesSorted = $RelFiles | Sort-Object

    # Build reference counts per file by reusing the same patterns/logic as the main audit
    $RxMdLink = [regex]'\]\((?<p>[^)]+)\)'
    $RxMdRef  = [regex]'^\[(?<id>[^\]]+)\]:\s*(?<p>\S+)\s*$'
    $RxFilepathMarker = [regex]'filepath:\s*(?<p>.+)$'
    $RxPathToken = [regex]'(?<p>(?:\.github|specs|src|tests|docs)[\\/][A-Za-z0-9._\-\\/]+(?:\.[A-Za-z0-9]+)?)'
    $RxQuotedOrTicked = [regex]'(?<q>["''`])(?<p>[^"''`\r\n]{2,}?[\\/][^"''`\r\n]{2,}?)\k<q>'

    function ConvertTo-NormalizedRefLocal {
        param([string]$Ref)
        if ([string]::IsNullOrWhiteSpace($Ref)) { return $Null }
        $R = $Ref.Trim().Trim([char[]]@([char]0x60, [char]0x27, [char]0x22))
        $R = $R.TrimEnd(")", "]", "}", ".", ",", ":", ";")
        $Hash = $R.IndexOf('#'); if ($Hash -ge 0) { $R = $R.Substring(0, $Hash) }
        $Q = $R.IndexOf('?');    if ($Q -ge 0) { $R = $R.Substring(0, $Q) }
        $R = $R.Trim()

        # If arguments follow a plausible path, keep only the first token
        if ($R -match '\s') {
            $First = ($R -split '\s+', 2)[0]
            if ($First -match '[\\/]' -and -not ($First -match '^(https?|mailto):')) {
                $R = $First
            }
        }

        if ([string]::IsNullOrWhiteSpace($R)) { return $Null }
        if ($R -match '^(https?|mailto):') { return $Null }
        return $R
    }

    function Resolve-RefPathLocal {
        param([string]$Ref, [string]$BaseDir)
        $R = ConvertTo-NormalizedRefLocal $Ref
        if (-not $R) { return $Null }

            # No skip patterns: treat all path-like tokens
        if ($R.IndexOfAny([char[]]@('<','>','[',']','{','}','*','?','$')) -ge 0) { return $Null }
        if ($R -match '^\^') { return $Null }
        if ($R -match '\s') {
            if ($R -notmatch '[\\/]') { return $Null }
            if ($R -match '\bnot found\b') { return $Null }
        }
        if ($R.Length -gt 512) { return $Null }
        if ($R -match ':' -and -not ($R -match '^[A-Za-z]:')) { return $Null }
        $Invalid = [IO.Path]::GetInvalidPathChars(); if ($R.IndexOfAny($Invalid) -ge 0) { return $Null }
        $LooksLikePath = ($R -match '^[A-Za-z]:[\\/]' -or $R -match '^\.{1,2}[\\/]' -or $R -match '[\\/]')
        if (-not $LooksLikePath) { return $Null }
        if ([IO.Path]::IsPathRooted($R)) { return $R }
        $Base = $RepoRoot
        if ($BaseDir -and $R -match '^\.{1,2}[\\/]') { $Base = $BaseDir }
        try { return (Join-Path $Base $R) } catch { return $Null }
    }

    function Test-RefExistsLocal {
        param([string]$Path)
        if (-not $Path) { return $False }
        if (Test-Path -LiteralPath $Path) { return $True }
        $Alt = $Path -replace '/', '\\'
        if (Test-Path -LiteralPath $Alt) { return $True }
        $Alt2 = $Path -replace '\\', '/'
        if (Test-Path -LiteralPath $Alt2) { return $True }
        return $False
    }

    $RefCounts = @{}
    $RefDetails = @{}
    foreach ($File in $Files) {
        $Count = 0
        $Details = New-Object System.Collections.Generic.List[object]
        $Lines = Get-Content -LiteralPath $File.FullName -ErrorAction SilentlyContinue
        for ($I = 0; $I -lt $Lines.Count; $I++) {
            $Line = $Lines[$I]
            $AddRef = {
                param($Candidate)
                $Norm = ConvertTo-NormalizedRefLocal $Candidate
                if (-not $Norm) { return }
                $Resolved = Resolve-RefPathLocal -Ref $Candidate -BaseDir $File.DirectoryName
                if (-not $Resolved) { return }
                $Exists = Test-RefExistsLocal $Resolved
                $Details.Add([PSCustomObject]@{ normalized = $Norm; resolved = $Resolved; exists = $Exists })
                $Count++
            }

            foreach ($M in $RxMdLink.Matches($Line)) { & $AddRef $M.Groups['p'].Value }
            $M2 = $RxMdRef.Match($Line); if ($M2.Success) { & $AddRef $M2.Groups['p'].Value }
            $M3 = $RxFilepathMarker.Match($Line); if ($M3.Success) { & $AddRef $M3.Groups['p'].Value }
            foreach ($M in $RxQuotedOrTicked.Matches($Line)) { & $AddRef $M.Groups['p'].Value }
            foreach ($M in $RxPathToken.Matches($Line)) { & $AddRef $M.Groups['p'].Value }
        }
        $Rel = $File.FullName.Substring($RepoRoot.Length).TrimStart([char]92,[char]47)
        $RefCounts[$Rel] = $Count
        $RefDetails[$Rel] = $Details
    }

    foreach ($F in $RelFilesSorted) {
        $Parts = $F -split '[\\/]'
        $Indent = ""
        for ($I = 0; $I -lt $Parts.Length; $I++) {
            if ($I -eq $Parts.Length - 1) {
                $Count = $RefCounts[$F]
                $Suffix = if ($Count -gt 0) { " (refs: $Count)" } else { "" }
                Write-Host "$Indent└─ $($Parts[$I])$Suffix"
            }
            else {
                Write-Host "$Indent├─ $($Parts[$I])"
                $Indent += "   "
            }
        }
    }

    if ($Files.Count -gt $MaxFiles) {
        Write-Host "" -NoNewline
        Write-Host "(Tree truncated to first $MaxFiles files; adjust -MaxFiles to see more)" -ForegroundColor Yellow
    }
}

if ($Files.Count -gt 0) {
    Write-Host "" -NoNewline
    Write-Host "References per file (up to $MaxRefsPerFile each):" -ForegroundColor Yellow

    foreach ($F in $RelFilesSorted) {
        $Refs = $RefDetails[$F]
        if (-not $Refs -or $Refs.Count -eq 0) {
            Write-Host "- $F : (no references)"
            continue
        }
        Write-Host "- $F : $($Refs.Count) reference(s)"
        $Refs | Select-Object -First $MaxRefsPerFile | ForEach-Object {
            $Status = if ($_.exists) { "[OK]" } else { "[X]" }
            Write-Host "    $Status $($_.normalized) -> $($_.resolved)"
        }
        if ($Refs.Count -gt $MaxRefsPerFile) {
            Write-Host "    ... (truncated; adjust -MaxRefsPerFile to see more)" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "Run the main audit with:" -ForegroundColor Gray
Write-Host "  pwsh specs/scripts/audit-references.ps1 -Roots $($Roots -join ' ') -RepoRootOverride $RepoRootOverride" -ForegroundColor Gray

