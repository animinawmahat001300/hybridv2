#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Audits file references across the workspace to detect broken or missing paths.

.DESCRIPTION
    Scans text files (Markdown, PowerShell, JSON, code, etc.) for file references,
    including:
    - Markdown links: [text](path)
    - Markdown reference-style: [id]: path
    - filepath: markers
    - Quoted/backticked paths
    - Common path tokens (.github/, specs/, src/, tests/, docs/)
    - Bare filenames with recognized extensions

    For each reference, the script:
    1. Normalizes the path (removes anchors, query strings, wrapping quotes)
    2. Resolves it (relative to source file or workspace root)
    3. Tests if the resolved path exists on disk

    Missing references are reported by default. Use -Json for structured output or
    -OutFile to generate a detailed audit report.

    This script is part of the SpecKit reference integrity system. See related script:
    audit-references-report.ps1 for scanning scope preview.

.PARAMETER Json
    Output results as JSON (summary, missing, evaluated).
    Useful for tooling integration and automated checks.

.PARAMETER Strict
    Exit with code 1 if any missing references are found.
    Enables CI/CD integration (fail builds on broken references).

.PARAMETER Roots
    One or more directories to scan. Defaults to workspace root.
    Paths are resolved relative to workspace root if not absolute.
    Example: -Roots "specs", "docs", ".github"

.PARAMETER RepoRootOverride
    Override the detected repository root. Mainly for tooling.
    Must be a valid directory path.

.PARAMETER OutFile
    Path to write detailed audit report (text format).
    Defaults to specs/changes/audit-report.txt if not specified.
    Report includes missing paths grouped by occurrence count and
    references per file (up to MaxRefsPerFile each).

.PARAMETER MaxRefsPerFile
    Maximum number of references to include per file in reports.
    Defaults to 50. Increase for more detail; decrease for faster output.

.PARAMETER Help
    Display this help message and exit.

.EXAMPLE
    .\audit-references.ps1
    Basic audit of workspace root. Reports missing references to console.

.EXAMPLE
    .\audit-references.ps1 -Strict
    Audit with strict mode. Exit code 1 if any references are missing.
    Ideal for CI/CD pipelines.

.EXAMPLE
    .\audit-references.ps1 -Roots "specs", "docs", ".github/agents"
    Audit specific directories only.

.EXAMPLE
    .\audit-references.ps1 -Json | ConvertFrom-Json | Select-Object -ExpandProperty missing
    Output missing references as JSON and parse with PowerShell.

.EXAMPLE
    .\audit-references.ps1 -OutFile "reports/audit-$(Get-Date -Format 'yyyyMMdd').txt"
    Generate timestamped audit report file.

.NOTES
    Exit Codes:
      0 - Success (no missing references, or non-strict mode)
      1 - Error (missing references in -Strict mode, or script failure)

    Output:
      Console: Human-readable summary with missing references grouped
      -Json:   Structured JSON (summary, missing, evaluated arrays)
      -OutFile: Detailed text report (missing + per-file reference list)

    Excluded Directories:
      .git, node_modules, dist, build, out, target, .cache, .next, .turbo,
      .vite, .agent_work, coverage, bin, obj, .idea, .vscode

    Allowed Extensions:
      .md, .ps1, .psm1, .json, .jsonc, .yml, .yaml, .txt, .js, .jsx, .ts,
      .tsx, .cs, .py, .java, .go, .rb, .php, .sh

    Skip Patterns:
      - URLs (http://, https://, mailto:)
      - Regex/glob patterns (*, ?, $, ^, [], {}, <>)
      - Common bare filenames (README.md, package.json, etc.)
      - Tool invocation markers (execute/, edit/, Run /speckit)

    Issue #10 (Code Duplication):
      This script shares pattern matching and normalization logic with
      audit-references-report.ps1. Refactoring to shared module is deferred.
      Track progress in Issue #10.

    Related Scripts:
      - audit-references-report.ps1: Preview scan scope and reference counts
    - common.ps1: Shared utility functions (Get-RepositoryRoot, etc.)

.LINK
    docs/speckit/ARCHITECTURE_OVERVIEW.md

.LINK
    docs/speckit/architecture/ADR-0002-file-based-state.md
#>
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Strict,
    [string[]]$Roots = @("."),
    [string]$RepoRootOverride,
    [string]$OutFile,
    [int]$MaxRefsPerFile = 50,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Display help if requested
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

# Top-level guard to surface any unexpected errors
try {

    . (Join-Path $PSScriptRoot ".." "common.ps1")

    $Sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "[speckit] Starting reference audit..." -ForegroundColor Cyan

    # Resolve repo root with optional override (mainly for tooling)
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

    # Workspace root: folder containing this specs directory (keeps scope local)
    $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path  # specs/
    $WorkspaceRoot = (Resolve-Path (Join-Path $WorkspaceRoot '..')).Path # repo workspace root (hybrid)
    # Force repo root to workspace root so only one root is used/shown
    $RepoRoot = $WorkspaceRoot

    # Constrain default scope to the current workspace root
    if (-not $PSBoundParameters.ContainsKey('Roots') -or ($Roots.Count -eq 1 -and $Roots[0] -eq '.')) {
        $Roots = @($WorkspaceRoot)
    }

    # Default output file to specs/changes/audit-report.txt (anchored to this script's specs folder) if not provided
    if (-not $OutFile) {
        $specsDir = Split-Path -Parent $PSScriptRoot
        $changesDir = Join-Path $specsDir 'changes'
        $OutFile = Join-Path $changesDir 'audit-report.txt'
    }

function Get-TextFiles {
    param([string]$Base)

    $excludeDirs = @(
        ".git", "node_modules", "dist", "build", "out", "target",
        ".cache", ".next", ".turbo", ".vite", ".agent_work", "coverage",
        "bin", "obj", ".idea", ".vscode"
    )

    $extAllow = @(
        ".md", ".ps1", ".psm1", ".json", ".jsonc", ".yml", ".yaml", ".txt",
        ".js", ".jsx", ".ts", ".tsx", ".cs", ".py", ".java", ".go", ".rb", ".php", ".sh"
    )

    Get-ChildItem -LiteralPath $Base -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $full = $_.FullName

            # Skip generated audit outputs to avoid recursive explosion (K.8)
            # - audit-report.txt is the default -OutFile
            # - _last_error.txt is written on failure
            # - audit-references-report.* can be generated by audit-references-report.ps1
            # - specs/changes is where these reports are typically written
            if ($_.Name -in @('audit-report.txt', '_last_error.txt')) { return $false }
            if ($_.Name -match '^audit-references-report\.(txt|md|json)$') { return $false }
            if ($full -match '([\\/])specs([\\/])changes\1') {
                if ($_.Name -match '^(audit-report|audit-references-report|_last_error)\.(txt|md|json)$') { return $false }
            }

            # Fast exclude for .vscode and other directories
            if ($full -like '*\.vscode\*' -or $full -like '*/.vscode/*') { return $false }

            foreach ($d in $excludeDirs) {
                if ($full -match ([regex]::Escape("\\$d\\"))) { return $false }
                if ($full -match ([regex]::Escape("/$d/"))) { return $false }
            }

            return $extAllow -contains $_.Extension.ToLowerInvariant()
        }
}

function ConvertTo-NormalizedRef {
    param([string]$Ref)

    if ([string]::IsNullOrWhiteSpace($Ref)) { return $null }

    $r = $Ref.Trim()

    # Strip surrounding wrappers
    # Use explicit char codes to avoid PowerShell backtick-escaping gotchas
    # 0x60 = `  (backtick), 0x27 = ' (single quote), 0x22 = " (double quote)
    $r = $r.Trim([char[]]@([char]0x60, [char]0x27, [char]0x22))

    # Remove trailing punctuation
    $r = $r.TrimEnd(")", "]", "}", ".", ",", ":", ";")

    # Drop anchors/query fragments for file checks
    $hash = $r.IndexOf('#')
    if ($hash -ge 0) { $r = $r.Substring(0, $hash) }
    $q = $r.IndexOf('?')
    if ($q -ge 0) { $r = $r.Substring(0, $q) }

    $r = $r.Trim()

    # If arguments follow a plausible path, keep only the first token (e.g., "specs/scripts/x.ps1 -Json" -> path only)
    if ($r -match '\s') {
        $first = ($r -split '\s+', 2)[0]
        if ($first -match '[\\/]' -and -not ($first -match '^(https?|mailto):')) {
            $r = $first
        }
    }

    if ([string]::IsNullOrWhiteSpace($r)) { return $null }

    # Ignore obvious URLs and mailto
    if ($r -match '^(https?|mailto):') { return $null }

    return $r
}

function Resolve-RefPath {
    param(
        [string]$Ref,
        [string]$BaseDir
    )

    $r = ConvertTo-NormalizedRef $Ref
    if (-not $r) { return $null }

    # Skip known non-path tokens and tool-call markers
    $skipPatterns = @(
        '^execute/', '^edit/', '^read/', '^search/',
        '^Run /speckit', '^Run \\speckit',
        '^No recovery flows detected',
        '^Are visual hierarchy requirements measurable/testable',
        '^Are security failure/breach response requirements defined',
        '^Are retry/timeout requirements defined',
        '^markers, quoted/backticked paths, and common$',
        '^C:\\Program$',
        '^FEATURE_DIR/',
        '^\*\.', # Skip wildcard patterns like *.md or speckit.*.agent.md fragments
        '^\.agent\.md$', # Skip bare .agent.md (fragment from wildcard patterns like speckit.*.agent.md)
        '^spec\.md$', '^plan\.md$', '^tasks\.md$', '^research\.md$', '^data-model\.md$', '^quickstart\.md$', '^checklist\.md$',
        '^package\.json$', '^package-lock\.json$', '^pnpm-lock\.yaml$', '^api\.md$', '^security\.md$', '^ux\.md$', '^test\.md$', '^constitution\.md$',
        '^project\.md$', '^spec-template\.md$', '^plan-template\.md$', '^_last_error\.txt$',
        '^\.eslintrc\.js$', '^\.eslintrc\.json$', '^eslint\.config\.js$', '^prettier\.config\.js$', '^jsconfig\.json$', '^tsconfig\.json$', '^workflow\.md$', '^composer\.json$',
        '^speckit\.plan\.agent\.md$', '^speckit\.plan\.prompt\.md$', '^speckit\.specify\.prompt\.md$', '^speckit\.constitution\.prompt\.md$', '^speckit\.clarify\.prompt\.md$', '^README\.md$', '^performance\.md$',
        '^\.secret\.yaml$', '^\.min\.js$', '^Node\.js$', '^Next\.js$',
        '^github/github-mcp-server/issue_write$',
        '^vendor/bundle/',
        '^Archive to specs/changes/archive/',
        '^\.github/agents/speckit$'
    )
    foreach ($pat in $skipPatterns) { if ($r -match $pat) { return $null } }

    # Skip obvious placeholders, wildcards, and regex snippets
    if ($r.IndexOfAny([char[]]@('<','>','[',']','{','}','*','?','$')) -ge 0) { return $null }
    if ($r -match '^\^') { return $null }

    # Allow whitespace only when it still looks like a path (contains a separator) AND is not an error message
    # (e.g., "tasks.md not found ...").
    if ($r -match '\s') {
        if ($r -notmatch '[\\/]') { return $null }
        if ($r -match '\bnot found\b') { return $null }
    }

    # Discard implausible tokens
    if ($r.Length -gt 512) { return $null }

    # Heuristics: only treat as a filesystem path if it looks like one.
    # In particular, skip strings that contain ':' but are not Windows drive paths.
    if ($r -match ':' -and -not ($r -match '^[A-Za-z]:')) { return $null }

    # Skip references containing invalid path characters (Windows: mainly control chars)
    $invalid = [IO.Path]::GetInvalidPathChars()
    if ($r.IndexOfAny($invalid) -ge 0) { return $null }

    # Require at least one path separator OR a drive path OR ./../ style.
    $looksLikePath = ($r -match '^[A-Za-z]:[\\/]' -or $r -match '^\.{1,2}[\\/]' -or $r -match '[\\/]')

    # If no obvious separators, allow bare filenames with common text/code extensions and resolve them relative to the source file directory (fallback to workspace root).
    if (-not $looksLikePath) {
        $bareFilePattern = '^[A-Za-z0-9._-]+\.(md|ps1|psm1|json|jsonc|yml|yaml|txt|js|jsx|ts|tsx|cs|py|java|go|rb|php|sh)$'
        if ($r -notmatch $bareFilePattern) { return $null }

        $rootCandidate = $null
        $baseCandidate = $null
        if ($BaseDir) {
            try { $baseCandidate = Join-Path $BaseDir $r } catch {}
        }
        try { $rootCandidate = Join-Path $WorkspaceRoot $r } catch {}

        # Prefer source directory (more precise), fall back to workspace root.
        $resolvedBare = $baseCandidate
        if (-not $resolvedBare) { $resolvedBare = $rootCandidate }
        if (-not $resolvedBare) { return $null }

        return [PSCustomObject]@{
            Ref      = $r
            Resolved = $resolvedBare
        }
    }

    # Absolute?
    if ([IO.Path]::IsPathRooted($r)) {
        return [PSCustomObject]@{
            Ref      = $r
            Resolved = $r
        }
    }

    # Resolve relative to the source file directory when the ref starts with ./ or ../; otherwise workspace root
    $base = $WorkspaceRoot
    if ($BaseDir -and $r -match '^\.{1,2}[\\/]') {
        $base = $BaseDir
    }

    try {
        $resolved = Join-Path $base $r
    }
    catch {
        return $null
    }
    return [PSCustomObject]@{
        Ref      = $r
        Resolved = $resolved
    }
}

function Test-RefExists {
    param([string]$Path)

    if (-not $Path) { return $false }

    # Try exact, then try normalized separators
    if (Test-Path -LiteralPath $Path) { return $true }

    $alt = $Path -replace '/', '\\'
    if (Test-Path -LiteralPath $alt) { return $true }

    $alt2 = $Path -replace '\\', '/'
    if (Test-Path -LiteralPath $alt2) { return $true }

    return $false
}

$rootsAbs = @()
$workspaceFull = (Resolve-Path -LiteralPath $WorkspaceRoot -ErrorAction SilentlyContinue)
if (-not $workspaceFull) {
    Write-Error "Workspace root '$WorkspaceRoot' could not be resolved."
    exit 1
}
$workspaceNorm = ($workspaceFull.Path -replace '/', '\').TrimEnd('\')
$workspacePrefix = "$workspaceNorm\"

foreach ($r in $Roots) {
    $p = if ([IO.Path]::IsPathRooted($r)) { $r } else { Join-Path $WorkspaceRoot $r }

    # Enforce scope: only scan paths within the current repo/workspace root
    $pFull = (Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue)
    if ($null -eq $pFull) {
        Write-Warning "Root '$r' could not be resolved and will be skipped."
        continue
    }
    $pNorm = ($pFull.Path -replace '/', '\')
    if ($pNorm -notlike "$workspacePrefix*" -and $pNorm -ne $workspaceNorm) {
        Write-Warning "Root '$pNorm' is outside the current workspace root '$workspaceNorm' and will be skipped."
        continue
    }

    $rootsAbs += $pFull.Path
}

# Always include .github/agents if present (agents invoke workflows and should be audited)
$agentsDir = Join-Path $WorkspaceRoot '.github/agents'
if (Test-Path -LiteralPath $agentsDir) {
    $rootsAbs += $agentsDir
}

# Deduplicate roots
$rootsAbs = $rootsAbs | Sort-Object -Unique

    Write-Host "[speckit] Roots to scan:" ($rootsAbs -join ', ')

if ($rootsAbs.Count -eq 0) {
    Write-Error "No roots provided or resolved."
    exit 1
}

$files = @()
Write-Host "[speckit] Enumerating files..." -ForegroundColor Cyan
foreach ($r in $rootsAbs) {
    if (Test-Path -LiteralPath $r -PathType Container) {
        $files += Get-TextFiles -Base $r
    }
}

Write-Host "[speckit] Found $($files.Count) candidate file(s)" -ForegroundColor Cyan

if ($files.Count -eq 0) {
    Write-Host "[speckit] Reference Audit" -ForegroundColor Cyan
    Write-Host "========================"
    Write-Host "No files scanned. Check roots: $($rootsAbs -join ', ')" -ForegroundColor Yellow
    exit 0
}

$occurrences = New-Object System.Collections.Generic.List[object]

# Regexes: markdown links, ref-style, filepath markers, and path-like tokens
$rxMdLink = [regex]'\]\((?<p>[^)]+)\)'
$rxMdRef  = [regex]'^\[(?<id>[^\]]+)\]:\s*(?<p>\S+)\s*$'
$rxFilepathMarker = [regex]'filepath:\s*(?<p>.+)$'
$rxPathToken = [regex]'(?<p>(?:\.github|specs|src|tests|docs)[\\/][A-Za-z0-9._\-\\/]+(?:\.[A-Za-z0-9]+)?)'
$rxQuotedOrTicked = [regex]'(?<q>["''`])(?<p>[^"''`\r\n]{2,}?[\\/][^"''`\r\n]{2,}?)\k<q>'
$rxBareFile = [regex]'(?<![A-Za-z0-9._/-])(?<p>[A-Za-z0-9._-]+\.(md|ps1|psm1|json|jsonc|yml|yaml|txt|js|jsx|ts|tsx|cs|py|java|go|rb|php|sh))(?![A-Za-z0-9._-])'

foreach ($f in $files) {
    $fileIdx = ++$fileIdx
    if ($fileIdx -eq 1 -or ($fileIdx % 20 -eq 0)) {
        Write-Host "[speckit] Scanning file $fileIdx of $($files.Count): $($f.FullName)" -ForegroundColor DarkCyan
    }
    # TrimStart expects chars; use explicit char codes: 92='\', 47='/'.
    $rel = $f.FullName.Substring($WorkspaceRoot.Length).TrimStart([char]92, [char]47)
    $lines = Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        foreach ($m in $rxMdLink.Matches($line)) {
            $refObj = Resolve-RefPath -Ref $m.Groups['p'].Value -BaseDir $f.DirectoryName
            if ($refObj) {
                $occurrences.Add([PSCustomObject]@{
                    source = $rel; line = $i + 1; raw = $m.Groups['p'].Value
                    normalized = $refObj.Ref; resolved = $refObj.Resolved
                })
            }
        }

        $m2 = $rxMdRef.Match($line)
        if ($m2.Success) {
            $refObj = Resolve-RefPath -Ref $m2.Groups['p'].Value -BaseDir $f.DirectoryName
            if ($refObj) {
                $occurrences.Add([PSCustomObject]@{
                    source = $rel; line = $i + 1; raw = $m2.Groups['p'].Value
                    normalized = $refObj.Ref; resolved = $refObj.Resolved
                })
            }
        }

        $m3 = $rxFilepathMarker.Match($line)
        if ($m3.Success) {
            $refObj = Resolve-RefPath -Ref $m3.Groups['p'].Value -BaseDir $f.DirectoryName
            if ($refObj) {
                $occurrences.Add([PSCustomObject]@{
                    source = $rel; line = $i + 1; raw = $m3.Groups['p'].Value
                    normalized = $refObj.Ref; resolved = $refObj.Resolved
                })
            }
        }

        foreach ($m in $rxQuotedOrTicked.Matches($line)) {
            $refObj = Resolve-RefPath -Ref $m.Groups['p'].Value -BaseDir $f.DirectoryName
            if ($refObj) {
                $occurrences.Add([PSCustomObject]@{
                    source = $rel; line = $i + 1; raw = $m.Groups['p'].Value
                    normalized = $refObj.Ref; resolved = $refObj.Resolved
                })
            }
        }

        foreach ($m in $rxPathToken.Matches($line)) {
            $refObj = Resolve-RefPath -Ref $m.Groups['p'].Value -BaseDir $f.DirectoryName
            if ($refObj) {
                $occurrences.Add([PSCustomObject]@{
                    source = $rel; line = $i + 1; raw = $m.Groups['p'].Value
                    normalized = $refObj.Ref; resolved = $refObj.Resolved
                })
            }
        }

        foreach ($m in $rxBareFile.Matches($line)) {
            $refObj = Resolve-RefPath -Ref $m.Groups['p'].Value -BaseDir $f.DirectoryName
            if ($refObj) {
                $occurrences.Add([PSCustomObject]@{
                    source = $rel; line = $i + 1; raw = $m.Groups['p'].Value
                    normalized = $refObj.Ref; resolved = $refObj.Resolved
                })
            }
        }
    }
}

# De-dup occurrences (same source+line+normalized)
$occurrences = $occurrences |
    Sort-Object source, line, normalized -Unique

# Exclude references that point to this script's own audit outputs (K.8)
# This prevents recursive growth when the report is generated under specs/changes.
try {
    $outFileFull = (Resolve-Path -LiteralPath $OutFile -ErrorAction SilentlyContinue)
    $outFileNorm = $null
    if ($outFileFull) { $outFileNorm = ($outFileFull.Path -replace '/', '\\').TrimEnd('\\') }

    $changesRoot = (Resolve-Path -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'changes') -ErrorAction SilentlyContinue)
    $changesNorm = $null
    if ($changesRoot) { $changesNorm = ($changesRoot.Path -replace '/', '\\').TrimEnd('\\') + '\\' }

    $occurrences = $occurrences | Where-Object {
        $resolvedNorm = ($_.resolved -replace '/', '\\')
        if ($outFileNorm -and $resolvedNorm -eq $outFileNorm) { return $false }
        if ($resolvedNorm -match '([\\/])audit-(report|references-report)\.(txt|md|json)$') { return $false }
        if ($changesNorm -and $resolvedNorm.StartsWith($changesNorm) -and ($resolvedNorm -match '([\\/])(_last_error|audit-report|audit-references-report)\.(txt|md|json)$')) { return $false }
        return $true
    }
}
catch {
    # Non-fatal; proceed without occurrence filtering.
}

# Evaluate existence
$evaluated = $occurrences | ForEach-Object {
    $exists = Test-RefExists -Path $_.resolved
    [PSCustomObject]@{
        source     = $_.source
        line       = $_.line
        raw        = $_.raw
        normalized = $_.normalized
        resolved   = $_.resolved
        exists     = $exists
    }
}

$missing = $evaluated | Where-Object { -not $_.exists }

$summary = [PSCustomObject]@{
    repo_root          = $RepoRoot
    scanned_files      = $files.Count
    reference_hits     = $evaluated.Count
    missing_hits       = $missing.Count
    missing_unique     = ($missing | Select-Object -ExpandProperty normalized | Sort-Object -Unique).Count
}

if ($Json) {
    @{
        summary   = $summary
        missing   = $missing
        evaluated = $evaluated
    } | ConvertTo-Json -Depth 6 -Compress

    if ($Strict -and $missing.Count -gt 0) { exit 1 }
    exit 0
}

# If OutFile is specified, write a detailed report (text) regardless of Json mode
if ($OutFile) {
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine("[speckit] Reference Audit Report")
    $null = $sb.AppendLine("Repo Root: $RepoRoot")
    $null = $sb.AppendLine("Scanned Files: $($summary.scanned_files)")
    $null = $sb.AppendLine("Reference Hits: $($summary.reference_hits)")
    $null = $sb.AppendLine("Missing Hits: $($summary.missing_hits)")
    $null = $sb.AppendLine("Missing Unique: $($summary.missing_unique)")
    $null = $sb.AppendLine("")

    if ($missing.Count -gt 0) {
        $null = $sb.AppendLine("Missing referenced paths (grouped):")
        $missing | Group-Object normalized | Sort-Object Count -Descending | ForEach-Object {
            $norm = $_.Name
            $count = $_.Count
            $sample = $_.Group | Select-Object -First 5
            $null = $sb.AppendLine("- $norm ($count occurrence(s))")
            foreach ($s in $sample) {
                $null = $sb.AppendLine("  - $($s.source):$($s.line) -> $($s.resolved)")
            }
        }
    }
    else {
        $null = $sb.AppendLine("No missing referenced paths detected.")
    }

    # References per file (both present and missing)
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("References per file (up to $MaxRefsPerFile each):")
    $evaluated | Group-Object source | Sort-Object Name | ForEach-Object {
        $grp = $_.Group
        $null = $sb.AppendLine("- $($_.Name) : $($grp.Count) reference(s)")
        $grp | Select-Object -First $MaxRefsPerFile | ForEach-Object {
            $status = if ($_.exists) { "[OK]" } else { "[X]" }
            $null = $sb.AppendLine("    $status $($_.normalized) -> $($_.resolved)")
        }
        if ($grp.Count -gt $MaxRefsPerFile) {
            $null = $sb.AppendLine("    ... (truncated; increase -MaxRefsPerFile to see more)")
        }
    }

    try {
        $dir = Split-Path -Parent $OutFile
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $sb.ToString() | Set-Content -LiteralPath $OutFile -Encoding UTF8
    }
    catch {
        Write-Warning "Failed to write report to $OutFile : $_"
    }
}

    Write-Host "[speckit] Reference Audit" -ForegroundColor Cyan
    Write-Host "========================"
    Write-Host "Workspace Root: $WorkspaceRoot"
    Write-Host "Scanned Files: $($summary.scanned_files)"
    Write-Host "Reference Hits: $($summary.reference_hits)"
    Write-Host "Missing Hits: $($summary.missing_hits)"
    Write-Host "Missing Unique: $($summary.missing_unique)"
Write-Host ""

if ($missing.Count -eq 0) {
    Write-Host "No missing referenced paths detected." -ForegroundColor Green
    exit 0
}

Write-Host "Missing referenced paths (grouped):" -ForegroundColor Yellow
$missing |
    Group-Object normalized |
    Sort-Object Count -Descending |
    ForEach-Object {
        $norm = $_.Name
        $count = $_.Count
        $sample = $_.Group | Select-Object -First 3
        Write-Host ""
        Write-Host "- $norm ($count occurrence(s))" -ForegroundColor Red
        foreach ($s in $sample) {
            Write-Host "  - $($s.source):$($s.line)  ->  $($s.resolved)"
        }
    }

if ($Strict) { exit 1 }

}
catch {
    $err = $_
    Write-Host "[speckit] ERROR: $($err.Exception.Message)" -ForegroundColor Red
    if ($err.InvocationInfo) {
        Write-Host $err.InvocationInfo.PositionMessage -ForegroundColor Yellow
    }
    if ($err.ScriptStackTrace) {
        Write-Host $err.ScriptStackTrace -ForegroundColor DarkYellow
    }

    try {
        $specsDir = Split-Path -Parent $PSScriptRoot
        $changesDir = Join-Path $specsDir 'changes'
        $logFile = Join-Path $changesDir '_last_error.txt'
        "Error: $($err.Exception.Message)`n$($err.InvocationInfo.PositionMessage)`n$($err.ScriptStackTrace)" | Set-Content -LiteralPath $logFile -Encoding UTF8
        Write-Host "[speckit] Error details written to $logFile" -ForegroundColor Yellow
    }
    catch {}

    exit 1
}
