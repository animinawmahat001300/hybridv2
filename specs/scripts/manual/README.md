# Manual Scripts

This directory contains scripts intended for **manual use** by developers and maintainers. These scripts are **not invoked by agents** and are designed for ad-hoc validation, debugging, and maintenance tasks.

# # Available Scripts

## # analyze-markdown-links.ps1

**Purpose**: Analyze and validate markdown link format consistency across the codebase.

**Description**: Scans all markdown files for link format patterns and reports inconsistencies. Detects:
- Plain inline links: `[text](url)` (STANDARD)
- Backticked labels: `` [`text`](url) `` (non-standard)
- Backticked paths: Links with backticks in URL (INVALID - causes parsing errors)
- Reference-style links: `[text][ref]` with `[ref]: url`

**Exit Codes**:
- `0` - All links are valid (no backticked paths found)
- `1` - Invalid backticked paths detected (requires fixing)

**Use Cases**:
- CI/CD integration to enforce link format standards
- Pre-commit validation of markdown files
- Identifying files that deviate from markdown conventions
- Preventing invalid markdown link syntax

**Output**:
- Pattern counts for each link type
- Percentage breakdown (dominant pattern determination)
- List of files with backticked labels
- **Critical errors**: Files with backticked paths (invalid syntax)

**Examples**:
```powershell
# Run full analysis
.\analyze-markdown-links.ps1

# In CI/CD pipeline
if (.\analyze-markdown-links.ps1; $LASTEXITCODE -ne 0) {
    Write-Error "Invalid markdown links detected"
    exit 1
}

# Check before commit
git add *.md
.\analyze-markdown-links.ps1 && git commit -m "docs: update markdown"
```

**Standard**: Plain labels `[text](url)` are the established convention (88.9% usage).  
**Rule**: NEVER use backticks in URL paths - this is invalid markdown.  
**Exception**: Backticks in labels acceptable when referencing code identifiers.

---

## # audit-references.ps1

**Purpose**: Full validation of file references across the workspace.

**Description**: Scans text files (Markdown, PowerShell, JSON, code, etc.) for file references and validates their existence on disk. Detects:
- Markdown links: `[text](path)`
- Markdown reference-style: `[id]: path`
- `filepath:` markers
- Quoted/backticked paths
- Common path tokens (`.github/`, `specs/`, `src/`, `tests/`, `docs/`)
- Bare filenames with recognized extensions

**Use Cases**:
- CI/CD integration with `-Strict` mode (fails build on broken references)
- Pre-commit validation of documentation
- Periodic workspace hygiene checks
- Debugging broken cross-references

**Parameters**:
- `-Json` - Output structured JSON for tooling integration
- `-Strict` - Exit code 1 if missing references found (CI mode)
- `-Roots` - Directories to scan (defaults to workspace root)
- `-OutFile` - Path to write detailed report (default: `specs/changes/audit-report.txt`)
- `-MaxRefsPerFile` - Max references per file in reports (default: 50)
- `-RepoRootOverride` - Override detected repository root

**Examples**:
```powershell
# Basic audit
.\audit-references.ps1

# Strict mode for CI/CD
.\audit-references.ps1 -Strict

# Specific directories
.\audit-references.ps1 -Roots "specs", "docs", ".github/agents"

# JSON output for automation
.\audit-references.ps1 -Json | ConvertFrom-Json

# Custom report file
.\audit-references.ps1 -OutFile "reports/audit-$(Get-Date -Format 'yyyyMMdd').txt"
```

**Exit Codes**:
- `0` - Success (no missing references, or non-strict mode)
- `1` - Error (missing references in `-Strict` mode, or script failure)

**Notes**:
- Shares pattern matching logic with `audit-references-report.ps1` (Issue #10: code duplication deferred)
- Excludes common build/cache directories (`.git`, `node_modules`, `dist`, etc.)
- Skips own audit outputs to prevent recursive growth

---

## # audit-references-report.ps1

**Purpose**: Preview scan scope before running full audit.

**Description**: Companion script to `audit-references.ps1` that reports scanning scope **without** performing full validation. Shows:
- Repository root
- Roots to be scanned
- Excluded directories
- Allowed file extensions
- Tree view of candidate files with reference counts
- Per-file reference details (normalized path, resolved path, exists status)

**Use Cases**:
- Verify scan scope before running full audit
- Preview reference counts per file
- Identify high-reference files for focused review
- Debug path resolution behavior

**Parameters**:
- `-Roots` - Directories to scan (defaults to current directory)
- `-MaxFiles` - Max files in tree view (default: 200)
- `-MaxRefsPerFile` - Max references per file (default: 50)
- `-RepoRootOverride` - Override detected repository root

**Examples**:
```powershell
# Preview current directory
.\audit-references-report.ps1

# Preview specific directories
.\audit-references-report.ps1 -Roots "specs", "docs"

# Increase limits for large workspace
.\audit-references-report.ps1 -MaxFiles 500 -MaxRefsPerFile 100

# Save to file
.\audit-references-report.ps1 -Roots "specs/scripts" | Out-File report.txt
```

**Exit Codes**:
- `0` - Success
- `1` - Error (invalid roots, no roots resolved, etc.)

**Workflow**:
1. Run `audit-references-report.ps1` to preview scope
2. Review reference counts and candidate files
3. Run `audit-references.ps1` for full validation

---

## # validate-paths.ps1

**Purpose**: Validates file paths in agent prompts and scripts.

**Description**: Ensures that paths referenced in agent definitions, prompts, and scripts exist and are accessible. Helps catch broken references before agent execution.

**Use Cases**:
- Pre-flight validation of agent configurations
- CI/CD checks for agent definitions
- Debugging agent invocation failures

---

# # Relationship to Agent Workflows

These scripts are **not part of agent workflows**. They are tools for:
- Manual validation by developers
- CI/CD integration for quality gates
- Debugging and troubleshooting
- Periodic maintenance tasks

For **automated** reference validation during agent workflows, see the agent-based validation system documented in the main `specs/scripts/README.md`.

---

# # Best Practices

## # When to Use These Scripts

✅ **Use manually**:
- Before committing changes that add/move files
- When investigating broken documentation links
- As part of CI/CD quality gates
- During periodic workspace cleanup

❌ **Do not**:
- Invoke from agent workflows (breaks isolation)
- Run automatically on every agent task (performance)
- Use as real-time validation (too slow for interactive editing)

## # CI/CD Integration

```powershell
# Fail build on broken references
pwsh specs/scripts/manual/audit-references.ps1 -Strict -Roots "specs", "docs", ".github"
```

## # Performance Considerations

- `audit-references-report.ps1` is faster (no validation) - use for quick checks
- `audit-references.ps1` validates all references - use for thorough audits
- Use `-Roots` to limit scope and improve performance
- Use `-MaxRefsPerFile` to control output verbosity

---

# # Issue Tracking

**Issue #10 (Code Duplication)**: Both scripts share pattern matching, normalization, and resolution logic. Refactoring to shared module is deferred. Track progress in project issue tracker.

---

# # Related Documentation

- `specs/scripts/README.md` - Main scripts documentation
- `docs/speckit/ARCHITECTURE_OVERVIEW.md` - System architecture
- `docs/speckit/architecture/ADR-0002-file-based-state.md` - File-based state design


