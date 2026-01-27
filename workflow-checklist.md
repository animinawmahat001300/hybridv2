# Workflow remediation checklist

Concise, actionable checklist synthesized from `analysis.md` and `output.md` for the SpecKit PowerShell workflow. Focuses on workflow integrity, reliability, and maintainability (not purely security).

## Critical (workflow integrity)

- [x] **WL-01** Add recursion guard in `Get-WorkspaceRoot` to prevent self-referential workspace detection.
- [x] **WL-02** Normalize workspace paths after Git root detection (separator + `GetFullPath`) to avoid mixed-path failures.
- [x] **WL-03** Validate feature IDs before `Join-Path` in `Get-FeatureDir` to prevent invalid or escaping paths in workflow operations.
- [x] **WL-04** Validate Git ref input (`BaseRef`) before invoking Git commands to avoid bad refs breaking delta generation.
- [x] **WL-05** Standardize rollback/transaction tracking across scripts (use `archive-feature.ps1` as reference).
- [x] **WL-06** Implement atomic file copy operations in `setup-plan.ps1` to prevent partial template writes.

## High priority (reliability & consistency)

- [x] **WL-07** Check `$LASTEXITCODE` after every Git command and surface meaningful warnings/errors when Git is unavailable.
- [x] **WL-08** Implement filesystem-based delta detection fallback when Git is missing (ADDED/MODIFIED/REMOVED at minimum).
- [x] **WL-09** Standardize strict validation rules in `validate.ps1` (REQ-ID, unchecked checklists, clarification markers).
- [x] **WL-10** Centralize constitution resolution into a shared helper to remove duplicated path probing.
- [x] **WL-11** Expand constitution-not-found warning to show all candidate paths and existence status.
- [x] **WL-12** Standardize JSON output format across scripts (status, timestamp, script, data, errors, warnings).
- [x] **WL-13** Add retry wrapper for transient Git failures (3 retries with backoff).
- [x] **WL-14** Enforce deprecation migration for `SPECIFY_FEATURE` → `SPECIFY_CHANGE_ID` with auto-migration then hard error in next major.
- [x] **WL-15** Standardize `$ErrorActionPreference` handling in `common.ps1` to ensure consistent error behavior.
- [x] **WL-16** Return error indicators from `Get-RenamedFiles` so callers can distinguish “no renames” vs “git failed”.
- [x] **WL-17** Standardize exit codes across scripts (0=success, 1=validation, 2=operation).

## Medium priority (performance & correctness)

- [x] **WL-18** Add workspace root caching with expiration to avoid repeated disk traversal.
- [x] **WL-19** Cache frequently read files (specs, governance data) during single script runs.
- [x] **WL-20** Improve cache integrity with content hashes and atomic cache writes.
- [x] **WL-21** Precompile frequently used regex patterns in `common.ps1`.
- [x] **WL-22** Normalize regex line-ending handling to `\r?\n` to support Windows/Linux/macOS.
- [x] **WL-23** Track all created files/directories before operations complete so rollback can remove partial output.
- [x] **WL-24** Validate delta specs for REQ-ID format, duplicates, and “MODIFIED actually changed” checks.
- [x] **WL-25** Auto-detect default Git base branch instead of hardcoding `main`.
- [x] **WL-26** Move allowed extensions list to governance configuration and read from `Get-GovernanceData`.
- [x] **WL-27** Apply whitespace-only change detection consistently and expose a trivial-change flag in deltas.
- [x] **WL-28** Standardize placeholder formats (templates `{SCREAMING_SNAKE}`, agent instructions avoid ``<kebab-case>``).

## Low priority (maintainability & clarity)

- [x] **WL-29** Standardize date/time formatting to ISO 8601 (`-Format "o"`) across scripts.
- [x] **WL-30** Replace magic numbers (cache expiry, thresholds) with named constants.
- [x] **WL-31** Replace single-letter loop variables (e.g., `$T`) with descriptive names.
- [x] **WL-32** Standardize logging strategy (`Write-Verbose`, `Write-Host`, `Write-Warning`, `Write-Error`).
- [x] **WL-33** Convert boolean parameters to `[switch]` for idiomatic PowerShell.
- [x] **WL-34** Ensure comment-based help sections are complete for all public functions.
- [x] **WL-35** Add `[ValidateNotNullOrEmpty()]` for mandatory parameters in public functions.
- [x] **WL-36** Refine exception handling specificity for `common.ps1` sourcing and other critical operations.

## Testing & validation

- [x] **WL-37** Add Pester test baseline for `common.ps1` (workspace detection, path resolution, delta detection, caching).
- [x] **WL-38** Add JSON schema validation for all `-Json` outputs.
- [x] **WL-39** Run `validate.ps1` on all workflow paths (success + failure paths).

## Definition of done

- [ ] All critical and high items completed or explicitly deferred with rationale.
- [ ] Rollback works for partial failures in all destructive scripts.
- [ ] Non-Git environments produce usable delta output or explicit, actionable warnings.
- [ ] JSON output format is consistent across scripts.
- [ ] Unit tests cover critical helpers and pass in CI.

## Tracking

- **Owner**: ____________
- **Target milestone**: ____________
- **Last reviewed**: ____________
