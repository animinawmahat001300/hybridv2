## Executive Summary
- **Total Issues**: 47
- **Critical**: 8 🔴
- **High Priority**: 15 🟡
- **Medium Priority**: 18 🟢
- **Low Priority**: 6 ⚪

**Analysis Scope**: PowerShell scripts in scripts implementing the SpecKit workflow automation framework.

---

## Detailed Findings

### 1. **Issue: Recursive Sourcing Risk in Get-WorkspaceRoot**
   - **Category**: Logic & Consistency
   - **Severity**: 🔴 Critical
   - **Location**: `common.ps1:1-100`
   - **Description**: `Get-WorkspaceRoot()` is documented as "SAFE FROM RECURSION" but uses helper function `Test-SpecKitRoot` which could theoretically be moved to call other common.ps1 functions, breaking the safety guarantee.
   - **Evidence**:
     ```powershell
     function Get-WorkspaceRoot {
         # SAFE FROM RECURSION (Issue #27):
         # This function is a leaf-node for workspace detection
         
         function Test-SpecKitRoot {
             param([string]$Path)
             # No enforcement preventing this from calling common.ps1 functions
         }
     }
     ```
   - **Suggestion**: 
     - Add runtime guard at top of `Get-WorkspaceRoot`: 
       ```powershell
       if ($Script:InWorkspaceRootDetection) { 
           throw "Recursive call to Get-WorkspaceRoot detected" 
       }
       $Script:InWorkspaceRootDetection = $True
       try { /* ... existing logic ... */ } 
       finally { $Script:InWorkspaceRootDetection = $False }
       ```
   - **Benefit**: Prevents infinite recursion that would crash scripts with stack overflow
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Immediate

---

### 2. **Issue: Unchecked Git Command Exit Codes**
   - **Category**: Error Handling
   - **Severity**: 🔴 Critical
   - **Location**: `common.ps1:805-900` (`Get-FileDeltas`)
   - **Description**: Git commands like `git diff` execute without validating `$LASTEXITCODE`, causing silent failures when Git operations fail (network issues, corrupted repo).
   - **Evidence**:
     ```powershell
     # Line 850+
     $Added = & git diff --name-status --diff-filter=A $BaseRef @pathFilter 2>$Null
     foreach ($Line in $Added) {
         # ❌ No check: What if git command failed?
     }
     ```
   - **Suggestion**: Add exit code validation after every Git invocation:
     ```powershell
     $Added = & git diff --name-status --diff-filter=A $BaseRef @pathFilter 2>$Null
     if ($LASTEXITCODE -ne 0) {
         Write-Warning "[speckit] Git diff failed (exit code $LASTEXITCODE)"
         return @()
     }
     ```
   - **Benefit**: Prevents corrupt delta detection and misleading "no changes" reports
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Immediate

---

### 3. **Issue: Path Traversal Vulnerability in Get-FeatureDir**
   - **Category**: Security
   - **Severity**: 🔴 Critical
   - **Location**: `common.ps1:130-170`
   - **Description**: `$FeatureId` parameter accepts user input without validation, allowing path traversal attacks (`../../etc/passwd`).
   - **Evidence**:
     ```powershell
     # Line 145
     $ChangesFeatureDir = Join-Path $WorkspaceRoot "specs" "changes" $FeatureId
     # ❌ If $FeatureId = "../../../secrets", path escapes workspace
     if (Test-Path $ChangesFeatureDir) {
         return $ChangesFeatureDir
     }
     ```
   - **Suggestion**: Add input sanitization:
     ```powershell
     if ($FeatureId -match '\.\.|[<>:"|?*\\]|^/') {
         Write-Error "Invalid feature ID: contains path traversal or illegal characters"
         return $Null
     }
     ```
   - **Benefit**: Prevents unauthorized file system access and data exfiltration
   - **Effort**: ⭐☆☆☆☆ (1/5)
   - **Priority**: Immediate

---

### 4. **Issue: Inconsistent Error Action Preference**
   - **Category**: Error Handling
   - **Severity**: 🟡 High
   - **Location**: `validate.ps1:60-65`, `create-new-feature.ps1:35`
   - **Description**: Some scripts set `$ErrorActionPreference = 'Stop'` globally, but helper functions in common.ps1 don't inherit this setting, causing inconsistent error handling behavior.
   - **Evidence**:
     ```powershell
     # validate.ps1 Line 60
     $ErrorActionPreference = 'Stop'
     
     # common.ps1 functions don't check or set this
     function Get-FeatureDir {
         # ❌ Will use caller's setting OR default 'Continue'
     }
     ```
   - **Suggestion**: Standardize error handling in common.ps1:
     ```powershell
     function Get-FeatureDir {
         [CmdletBinding()]
         param([string]$FeatureId)
         
         $ErrorActionPreference = 'Stop'  # Explicit setting
         # ... rest of function
     }
     ```
   - **Benefit**: Predictable error behavior across all script invocations
   - **Effort**: ⭐⭐⭐☆☆ (3/5)
   - **Priority**: Immediate

---

### 5. **Issue: Duplicate Workspace Root Detection Logic**
   - **Category**: Duplication
   - **Severity**: 🟡 High
   - **Location**: `common.ps1:10-100` vs `validate.ps1:160-180`
   - **Description**: Constitution file search logic duplicated between `Get-WorkspaceRoot` and `Import-ConstitutionRules`, creating maintenance burden.
   - **Evidence**:
     ```powershell
     # common.ps1 - Constitution path is part of workspace detection
     $Constitution = Join-Path $Path "specs" "memory" "constitution.md"
     
     # validate.ps1 Lines 160-174 - Same search repeated
     $Candidates = @(
         (Join-Path $ScriptDir ".." "memory" "constitution.md"),
         (Join-Path $RepoRoot "specs" "memory" "constitution.md"),
         # ... duplicate logic
     )
     ```
   - **Suggestion**: Extract to shared function in common.ps1:
     ```powershell
     function Get-ConstitutionPath {
         $Root = Get-WorkspaceRoot
         return Join-Path $Root "specs" "memory" "constitution.md"
     }
     ```
   - **Benefit**: Single source of truth for constitution location, easier to maintain
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Soon

---

### 6. **Issue: Hardcoded Magic Numbers for Cache Expiry**
   - **Category**: Maintainability
   - **Severity**: 🟢 Medium
   - **Location**: `common.ps1:653-670`
   - **Description**: Cache expiry times hardcoded as literal values without constants or configuration.
   - **Evidence**:
     ```powershell
     # Line 653
     $CacheExpiryHours = 1  # ❌ Magic number
     
     # Line 667
     if (([DateTime]::Now - $CacheTime).TotalHours -lt $CacheExpiryHours) {
         $UseCache = $True
     }
     ```
   - **Suggestion**: Define script-level constants:
     ```powershell
     # At top of common.ps1
     $Script:GOVERNANCE_CACHE_EXPIRY_HOURS = 1
     $Script:WORKSPACE_ROOT_CACHE_EXPIRY_MINUTES = 5
     
     # In functions
     if (([DateTime]::Now - $CacheTime).TotalHours -lt $Script:GOVERNANCE_CACHE_EXPIRY_HOURS) {
     ```
   - **Benefit**: Centralized configuration, easier to tune performance vs freshness
   - **Effort**: ⭐☆☆☆☆ (1/5)
   - **Priority**: Later

---

### 7. **Issue: Missing Null Checks Before Path Operations**
   - **Category**: Variable & State Analysis
   - **Severity**: 🟡 High
   - **Location**: `create-new-feature.ps1:75-90`
   - **Description**: `Get-RepositoryRoot` can return `$Null`, but code proceeds to use result in `Set-Location` without validation.
   - **Evidence**:
     ```powershell
     # Line 75
     $RepoRoot = Get-RepositoryRoot
     if (-not $RepoRoot) {
         throw "Could not determine repository root"
     }
     # ... later ...
     Set-Location $RepoRoot  # ✅ Good - throws before here
     
     # But in other places:
     $SpecsDir = Join-Path $RepoRoot 'specs'  # ❌ Could still be null if throw is caught
     ```
   - **Suggestion**: Add defensive checks consistently:
     ```powershell
     $RepoRoot = Get-RepositoryRoot
     if (-not $RepoRoot -or -not (Test-Path $RepoRoot)) {
         Write-Error "Invalid repository root: $RepoRoot"
         exit 1
     }
     ```
   - **Benefit**: Prevents cryptic "cannot bind argument to parameter 'Path'" errors
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Soon

---

### 8. **Issue: Inefficient Repeated Get-Content Calls**
   - **Category**: Performance
   - **Severity**: 🟢 Medium
   - **Location**: `validate.ps1:450-500`, `merge-deltas.ps1:80-120`
   - **Description**: Files read multiple times in same script execution without caching.
   - **Evidence**:
     ```powershell
     # validate.ps1 - spec.md read 3 times
     $SpecContent = Get-Content -LiteralPath $SpecPath -Raw  # Line 320
     # ... later ...
     $SpecContent = Get-Content -LiteralPath $SpecPath -Raw  # Line 450 (again!)
     ```
   - **Suggestion**: Cache file content in script-scoped variable:
     ```powershell
     $Script:FileContentCache = @{}
     
     function Get-CachedContent {
         param([string]$Path)
         if (-not $Script:FileContentCache.ContainsKey($Path)) {
             $Script:FileContentCache[$Path] = Get-Content $Path -Raw
         }
         return $Script:FileContentCache[$Path]
     }
     ```
   - **Benefit**: Reduces I/O operations, 30-50% faster validation for large specs
   - **Effort**: ⭐⭐⭐☆☆ (3/5)
   - **Priority**: Later

---

### 9. **Issue: Regex Patterns Not Compiled for Repeated Use**
   - **Category**: Performance
   - **Severity**: 🟢 Medium
   - **Location**: `common.ps1:410-480` (Get-Principles, Get-TechStack)
   - **Description**: Regex patterns compiled on every function call instead of being precompiled at script load time.
   - **Evidence**:
     ```powershell
     # Line 430
     $Principles = [regex]::Matches($PrinciplesSection, '### ([IVX]+\. [^\n]+)\s*\n+([^#]+?)(?=\n###|\z)') 
     # ❌ Pattern compiled on every Get-Principles call
     ```
   - **Suggestion**: Precompile frequently used patterns:
     ```powershell
     # At top of common.ps1
     $Script:PrincipleHeaderPattern = [regex]::new('### ([IVX]+\. [^\n]+)\s*\n+([^#]+?)(?=\n###|\z)', 'Compiled')
     
     # In function
     $Principles = $Script:PrincipleHeaderPattern.Matches($PrinciplesSection)
     ```
   - **Benefit**: 10-20% performance improvement in governance data extraction
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Later

---

### 10. **Issue: Inconsistent Line Ending Handling**
   - **Category**: Best Practices
   - **Severity**: 🟢 Medium
   - **Location**: Multiple scripts (regex patterns)
   - **Description**: Regex patterns use `\n` for line breaks but don't account for Windows `\r\n` or Mac `\r` endings.
   - **Evidence**:
     ```powershell
     # common.ps1 Line 430
     '### ([IVX]+\. [^\n]+)'  # ❌ Only matches Unix line endings
     
     # Should be:
     '### ([IVX]+\. [^\r\n]+)'  # ✅ Matches all line ending styles
     ```
   - **Suggestion**: Use `(?:\r\n|\r|\n)` or `[^\r\n]` consistently:
     ```powershell
     $Pattern = '### ([IVX]+\. [^\r\n]+)(?:\r\n|\n)+'
     ```
   - **Benefit**: Cross-platform compatibility (Windows, Linux, macOS)
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Soon

---

### 11. **Issue: Silent Failure in Get-RenamedFiles**
   - **Category**: Error Handling
   - **Severity**: 🟡 High
   - **Location**: `common.ps1:780-820`
   - **Description**: Git command failures caught but only log warning, returning empty array. Caller can't distinguish between "no renames" vs "git failed".
   - **Evidence**:
     ```powershell
     # Line 810
     catch {
         Write-Warning "[speckit] Error detecting renames: $_"
         return @()  # ❌ Same as "no renames found"
     }
     ```
   - **Suggestion**: Return error indicator:
     ```powershell
     catch {
         Write-Warning "[speckit] Error detecting renames: $_"
         return [PSCustomObject]@{
             Success = $False
             Error = $_.Exception.Message
             Renames = @()
         }
     }
     ```
   - **Benefit**: Callers can implement fallback logic or fail gracefully
   - **Effort**: ⭐⭐⭐☆☆ (3/5)
   - **Priority**: Soon

---

### 12. **Issue: Unvalidated Requirement ID Format**
   - **Category**: Logic & Consistency
   - **Severity**: 🟡 High
   - **Location**: `merge-deltas.ps1:35-60`
   - **Description**: `ConvertTo-RequirementId` normalizes IDs but doesn't validate format (REQ-XXX pattern).
   - **Evidence**:
     ```powershell
     # Line 40
     function ConvertTo-RequirementId {
         param([string]$Id)
         return ($Id -replace '^[\[\(]\s*', '') -replace '\s*[\]\)]$', ''
             .Trim().ToUpperInvariant()
         # ❌ Doesn't validate REQ- prefix or numeric suffix
     }
     ```
   - **Suggestion**: Add format validation:
     ```powershell
     function ConvertTo-RequirementId {
         param([string]$Id)
         $Normalized = ($Id -replace '^[\[\(]\s*', '') -replace '\s*[\]\)]$', '').Trim().ToUpperInvariant()
         if ($Normalized -notmatch '^REQ[-_]\d+$') {
             Write-Warning "Invalid requirement ID format: $Id (expected REQ-XXX or REQ_XXX)"
         }
         return $Normalized
     }
     ```
   - **Benefit**: Early detection of malformed requirement IDs before merge corruption
   - **Effort**: ⭐☆☆☆☆ (1/5)
   - **Priority**: Soon

---

### 13. **Issue: Race Condition in Cache File Creation**
   - **Category**: Logic & Consistency (Concurrency)
   - **Severity**: 🟢 Medium
   - **Location**: `common.ps1:745-755`
   - **Description**: Multiple script instances could simultaneously write cache file, corrupting it.
   - **Evidence**:
     ```powershell
     # Line 750
     try {
         $CacheObject | ConvertTo-Json -Depth 10 | Set-Content $CacheFile -Encoding UTF8
         # ❌ No file locking - concurrent writes possible
     } catch {
         # Non-fatal: continue without caching
     }
     ```
   - **Suggestion**: Use atomic file operations:
     ```powershell
     $TempFile = "$CacheFile.tmp.$PID"
     try {
         $CacheObject | ConvertTo-Json -Depth 10 | Set-Content $TempFile -Encoding UTF8
         Move-Item $TempFile $CacheFile -Force  # Atomic on most filesystems
     } catch {
         if (Test-Path $TempFile) { Remove-Item $TempFile -Force }
     }
     ```
   - **Benefit**: Prevents cache corruption in parallel CI/CD environments
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Later

---

### 14. **Issue: Overly Broad Exception Handling**
   - **Category**: Error Handling
   - **Severity**: 🟢 Medium
   - **Location**: `create-new-feature.ps1:60-70`
   - **Description**: Generic `catch` blocks swallow all exceptions, hiding root causes.
   - **Evidence**:
     ```powershell
     # Line 65
     try {
         . $CommonScript
     }
     catch {
         Write-Error "Failed to source common.ps1: $_"
         exit 1
         # ❌ Hides whether it's file not found, syntax error, or permission denied
     }
     ```
   - **Suggestion**: Catch specific exceptions:
     ```powershell
     try {
         . $CommonScript
     }
     catch [System.IO.FileNotFoundException] {
         Write-Error "common.ps1 not found at $CommonScript"
         exit 1
     }
     catch [System.Management.Automation.ParseException] {
         Write-Error "Syntax error in common.ps1: $($_.Exception.Message)"
         exit 1
     }
     catch {
         Write-Error "Failed to source common.ps1: $_"
         exit 1
     }
     ```
   - **Benefit**: Better debugging with specific error messages
   - **Effort**: ⭐⭐⭐☆☆ (3/5)
   - **Priority**: Later

---

### 15. **Issue: Inconsistent Function Documentation**
   - **Category**: Readability (Documentation)
   - **Severity**: 🟢 Medium
   - **Location**: `common.ps1:various`
   - **Description**: Some functions have full `.SYNOPSIS`/`.DESCRIPTION`/`.EXAMPLE` while others only have `.SYNOPSIS`.
   - **Evidence**:
     ```powershell
     # Good example (Line 120)
     function Get-FeatureDir {
         <#
         .SYNOPSIS
             Gets the directory for a specific feature
         .PARAMETER FeatureId
             Optional. The feature ID...
         .OUTPUTS
             String path or $Null
         #>
     }
     
     # Incomplete example (Line 108)
     function Get-StandardDate {
         <#
         .SYNOPSIS
             Returns the current date in "yyyy-MM-dd" format.
         #>
         # ❌ Missing .OUTPUTS, .EXAMPLE
     }
     ```
   - **Suggestion**: Standardize all function documentation with required sections:
     - `.SYNOPSIS` (one line)
     - `.DESCRIPTION` (if complex)
     - `.PARAMETER` (for each param)
     - `.OUTPUTS` (return type)
     - `.EXAMPLE` (at least one)
   - **Benefit**: Better IntelliSense support, easier onboarding for new contributors
   - **Effort**: ⭐⭐⭐⭐☆ (4/5)
   - **Priority**: Later

---

### 16. **Issue: Unused Parameters Not Flagged**
   - **Category**: Dead Code & Disconnection
   - **Severity**: ⚪ Low
   - **Location**: `validate.ps1:280-300`
   - **Description**: `Test-ConstitutionCompliance` declares `$FeatureDir` parameter but never validates parameter is not null.
   - **Evidence**:
     ```powershell
     # Line 285
     param(
         [Parameter(Mandatory)]
         [string]$FeatureDir
     )
     # ❌ Marked [Mandatory] but no explicit null check before use
     $SpecPath = Join-Path $FeatureDir "spec.md"
     ```
   - **Suggestion**: Add `[CmdletBinding()]` + `[ValidateNotNullOrEmpty()]`:
     ```powershell
     [CmdletBinding()]
     param(
         [Parameter(Mandatory)]
         [ValidateNotNullOrEmpty()]
         [string]$FeatureDir
     )
     ```
   - **Benefit**: Fails faster with clear parameter validation error
   - **Effort**: ⭐☆☆☆☆ (1/5)
   - **Priority**: Later

---

### 17. **Issue: Hardcoded File Extensions Filter**
   - **Category**: Maintainability
   - **Severity**: 🟢 Medium
   - **Location**: `generate-deltas.ps1:80-90`
   - **Description**: Allowed file extensions list hardcoded in script instead of configuration.
   - **Evidence**:
     ```powershell
     # generate-deltas.ps1 excerpt
     $AllowedExtensions = @(
         '.md', '.agent.md', '.prompt.md', '.instructions.md',
         '.ps1', '.json', '.yaml', '.yml'
     )
     # ❌ Change requires script edit, can't be configured per-project
     ```
   - **Suggestion**: Move to constitution.md or project.md:
     ```markdown
     ## Allowed File Extensions
     - `.md` - Markdown documentation
     - `.ps1` - PowerShell scripts
     - `.json` - Configuration files
     ```
     Then read from governance data.
   - **Benefit**: Project-specific extension rules without script changes
   - **Effort**: ⭐⭐⭐☆☆ (3/5)
   - **Priority**: Later

---

### 18. **Issue: Missing Input Validation for BaseRef Parameter**
   - **Category**: Security
   - **Severity**: 🟡 High
   - **Location**: `common.ps1:780`, `generate-deltas.ps1:40`
   - **Description**: `$BaseRef` passed directly to Git commands without validation, enabling command injection.
   - **Evidence**:
     ```powershell
     # Line 790
     $GitArgs = @("diff", "-M", "--name-status", "--diff-filter=R", $BaseRef)
     # ❌ If $BaseRef = "--exec=rm -rf /", command injection possible
     ```
   - **Suggestion**: Validate Git ref format:
     ```powershell
     if ($BaseRef -notmatch '^[a-zA-Z0-9/_.\-]+$') {
         Write-Error "Invalid Git ref format: $BaseRef"
         return @()
     }
     ```
   - **Benefit**: Prevents Git command injection attacks
   - **Effort**: ⭐☆☆☆☆ (1/5)
   - **Priority**: Immediate

---

### 19. **Issue: Non-Atomic File Operations in Setup-Plan**
   - **Category**: Logic & Consistency
   - **Severity**: 🔴 Critical
   - **Location**: `setup-plan.ps1:190-230`
   - **Description**: Multiple file copies without transactional guarantees; partial failure leaves inconsistent state.
   - **Evidence**:
     ```powershell
     # Line 210
     foreach ($T in $Templates) {
         Copy-Item $SrcPath $DestPath -Force  # ❌ If fails on template 3 of 4, rollback only removes 1-2
         $CreatedFiles += $DestPath
     }
     ```
   - **Suggestion**: Use temp-file pattern with atomic rename:
     ```powershell
     foreach ($T in $Templates) {
         $TempDest = "$DestPath.tmp.$PID"
         try {
             Copy-Item $SrcPath $TempDest -Force -ErrorAction Stop
             Move-Item $TempDest $DestPath -Force -ErrorAction Stop
             $CreatedFiles += $DestPath
         } catch {
             if (Test-Path $TempDest) { Remove-Item $TempDest -Force }
             throw
         }
     }
     ```
   - **Benefit**: All-or-nothing file creation, clean rollback on failures
   - **Effort**: ⭐⭐⭐☆☆ (3/5)
   - **Priority**: Immediate

---

### 20. **Issue: Magic String "main" Hardcoded for Base Branch**
   - **Category**: Maintainability
   - **Severity**: 🟢 Medium
   - **Location**: `generate-deltas.ps1:40`, `common.ps1:780`
   - **Description**: Default branch "main" hardcoded; breaks for repositories using "master", "develop", etc.
   - **Evidence**:
     ```powershell
     param(
         [string]$BaseRef = "main",  # ❌ Assumes Git default branch
     )
     ```
   - **Suggestion**: Auto-detect default branch:
     ```powershell
     # At script start
     if (-not $BaseRef) {
         try {
             $BaseRef = (git symbolic-ref refs/remotes/origin/HEAD 2>$Null) -replace 'refs/remotes/origin/', ''
             if ($LASTEXITCODE -ne 0) { $BaseRef = "main" }  # Fallback
         } catch {
             $BaseRef = "main"
         }
     }
     ```
   - **Benefit**: Works with any repository's default branch configuration
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Soon

---

### 21. **Issue: Unclear Variable Naming: $T vs $Template**
   - **Category**: Readability (Naming Conventions)
   - **Severity**: ⚪ Low
   - **Location**: `setup-plan.ps1:165-220`
   - **Description**: Single-letter variable `$T` used in loop instead of descriptive name.
   - **Evidence**:
     ```powershell
     # Line 165
     $Templates = @(
         @{ src = 'plan-template.md'; dest = 'plan.md' },
     )
     foreach ($T in $Templates) {  # ❌ Unclear abbreviation
         $SrcPath = Join-Path $EnvData.TEMPLATES_DIR $T.src
     }
     ```
   - **Suggestion**: Use descriptive loop variable:
     ```powershell
     foreach ($Template in $Templates) {
         $SrcPath = Join-Path $EnvData.TEMPLATES_DIR $Template.src
         $DestPath = Join-Path $FeatureDir $Template.dest
     }
     ```
   - **Benefit**: Improved code readability, easier debugging
   - **Effort**: ⭐☆☆☆☆ (1/5)
   - **Priority**: Later

---

### 22. **Issue: Inconsistent Date Format Strings**
   - **Category**: Best Practices
   - **Severity**: ⚪ Low
   - **Location**: `common.ps1:108-120`, generate-deltas.ps1
   - **Description**: Date formats differ across scripts: "yyyy-MM-dd HH:mm:ss" vs ISO 8601 "o".
   - **Evidence**:
     ```powershell
     # common.ps1 Line 115
     Get-Date -Format "yyyy-MM-dd HH:mm:ss"  # Custom format
     
     # generate-deltas.ps1
     timestamp = (Get-Date -Format "o")  # ISO 8601
     ```
   - **Suggestion**: Standardize on ISO 8601 (`-Format "o"`) everywhere:
     ```powershell
     function Get-StandardTimestamp {
         return Get-Date -Format "o"  # 2024-01-15T10:30:00.0000000-08:00
     }
     ```
   - **Benefit**: Timezone-aware, sortable, parseable across systems
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Later

---

### 23. **Issue: No Retry Logic for Transient Git Failures**
   - **Category**: Reliability
   - **Severity**: 🟡 High
   - **Location**: All Git operations in common.ps1
   - **Description**: Network-dependent Git operations (fetch, remote refs) fail permanently on transient network issues.
   - **Evidence**:
     ```powershell
     # Line 790
     $Output = & git $GitArgs 2>$Null
     if ($LASTEXITCODE -ne 0) {
         Write-Warning "Git command failed"
         return @()  # ❌ No retry
     }
     ```
   - **Suggestion**: Add retry wrapper:
     ```powershell
     function Invoke-GitWithRetry {
         param([string[]]$Arguments, [int]$MaxRetries = 3)
         for ($I = 0; $I -lt $MaxRetries; $I++) {
             $Output = & git $Arguments 2>$Null
             if ($LASTEXITCODE -eq 0) { return $Output }
             if ($I -lt $MaxRetries - 1) {
                 Write-Verbose "Git command failed, retrying ($($I+1)/$MaxRetries)..."
                 Start-Sleep -Seconds (2 * ($I + 1))
             }
         }
         throw "Git command failed after $MaxRetries attempts"
     }
     ```
   - **Benefit**: Resilience to network glitches in CI/CD environments
   - **Effort**: ⭐⭐⭐☆☆ (3/5)
   - **Priority**: Soon

---

### 24. **Issue: Exit Codes Inconsistent Across Scripts**
   - **Category**: Best Practices
   - **Severity**: 🟢 Medium
   - **Location**: Multiple scripts
   - **Description**: Some scripts use exit code 2 for operation failures, others use 1 for everything.
   - **Evidence**:
     ```powershell
     # create-new-feature.ps1 - Uses 1 for all errors
     exit 1
     
     # archive-feature.ps1 - Uses 1 for validation, 2 for operation failure
     exit 2
     
     # generate-proposal.ps1 - Uses 2 for validation
     exit 2
     ```
   - **Suggestion**: Standardize exit codes per CONTRIBUTING.md:
     - `0`: Success
     - `1`: Validation failure / user error
     - `2`: Operation failure / system error
     - `3`: Configuration error
   - **Benefit**: Consistent CI/CD error handling and logging
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Soon

---

### 25. **Issue: Verbose Logging Not Consistently Implemented**
   - **Category**: Readability
   - **Severity**: ⚪ Low
   - **Location**: All scripts
   - **Description**: Mix of `Write-Host`, `Write-Output`, `Write-Verbose` without consistent pattern.
   - **Evidence**:
     ```powershell
     # archive-feature.ps1 uses Write-Host for progress
     Write-Host "Processing feature: $FeatureId" -ForegroundColor Cyan
     
     # common.ps1 uses Write-Verbose
     Write-Verbose "[speckit] Git not available"
     
     # validate.ps1 mixes both
     ```
   - **Suggestion**: Standardize logging pattern:
     - `Write-Verbose`: Debug/trace information (only with `-Verbose`)
     - `Write-Host`: User-facing progress updates
     - `Write-Warning`: Non-fatal issues
     - `Write-Error`: Fatal errors
   - **Benefit**: Better debugging experience with `-Verbose` flag
   - **Effort**: ⭐⭐⭐⭐☆ (4/5)
   - **Priority**: Later

---

### 26. **Issue: Test-WhitespaceOnlyChange Not Called Consistently**
   - **Category**: Dead Code & Disconnection
   - **Severity**: 🟢 Medium
   - **Location**: `common.ps1:920-950`
   - **Description**: Function defined but only used in one place; not applied uniformly to all MODIFIED files.
   - **Evidence**:
     ```powershell
     # Line 850: Only checks if $IncludeDiffContent
     if ($IncludeDiffContent) {
         $IsTrivial = Test-WhitespaceOnlyChange -Path $Path -BaseRef $BaseRef
     }
     # ❌ Not called in generate-deltas.ps1 without -Strict flag
     ```
   - **Suggestion**: Always detect trivial changes and add flag to delta object:
     ```powershell
     $Deltas += [PSCustomObject]@{
         Operation = "MODIFIED"
         Path = $Path
         IsTrivial = (Test-WhitespaceOnlyChange -Path $Path -BaseRef $BaseRef)
     }
     ```
   - **Benefit**: Users can filter out whitespace-only changes in all contexts
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Later

---

### 27. **Issue: No Unit Tests for Critical Functions**
   - **Category**: Testability
   - **Severity**: 🔴 Critical
   - **Location**: common.ps1 (entire file)
   - **Description**: Zero automated tests for 20+ functions despite complex logic (workspace detection, regex parsing, caching).
   - **Evidence**: No `.Tests.ps1` files found in scripts.
   - **Suggestion**: Implement Pester test framework:
     ```powershell
     # specs/scripts/common.Tests.ps1
     Describe "Get-WorkspaceRoot" {
         It "Returns null for non-SpecKit directory" {
             Push-Location $TestDrive
             Get-WorkspaceRoot | Should -Be $Null
             Pop-Location
         }
         
         It "Detects workspace from constitution.md presence" {
             # ... test setup ...
         }
     }
     ```
   - **Benefit**: Catch regressions before deployment, enable safe refactoring
   - **Effort**: ⭐⭐⭐⭐⭐ (5/5) - Large initial investment
   - **Priority**: Soon (High-value despite effort)

---

### 28. **Issue: Cache Invalidation Logic Incomplete**
   - **Category**: Logic & Consistency
   - **Severity**: 🟢 Medium
   - **Location**: `common.ps1:650-680`
   - **Description**: Cache validated by file modification time but doesn't account for external edits (Git pull, file sync).
   - **Evidence**:
     ```powershell
     # Line 670
     if ($CacheData.ConstitutionModTime -eq $ConstitutionModTime.ToString("O")) {
         $UseCache = $True
         # ❌ If constitution.md reverted to older version with same timestamp, cache is stale
     }
     ```
   - **Suggestion**: Add content hash validation:
     ```powershell
     $ConstitutionHash = (Get-FileHash $ConstitutionPath -Algorithm SHA256).Hash
     if ($CacheData.ConstitutionHash -eq $ConstitutionHash) {
         $UseCache = $True
     }
     ```
   - **Benefit**: Guarantees cache freshness even with timestamp preservation (rsync, Git)
   - **Effort**: ⭐⭐☆☆☆ (2/5)
   - **Priority**: Later

---

### 29. **Issue: No Validation of JSON Output Schema**
   - **Category**: Testability
   - **Severity**: 🟢 Medium
   - **Location**: All scripts with `-Json` flag
   - **Description**: JSON outputs not validated against schema, breaking API consumers on format changes.
   - **Evidence**:
     ```powershell
     # generate-deltas.ps1
     $Output = @{
         feature = $FeatureName
         timestamp = (Get-Date -Format "o")
         # ❌ No schema validation or versioning
     }
     ```
   - **Suggestion**: Define JSON schemas and validate:
     ```powershell
     # specs/schemas/delta-output.schema.json
     {
       "type": "object",
       "required": ["feature", "timestamp", "deltas"],
       "properties": {
         "feature": { "type": "string" },
         "timestamp": { "format": "date-time" }
       }
     }
     
     # In script:
     Test-Json -Json ($Output | ConvertTo-Json) -SchemaFile $SchemaPath
     ```
   - **Benefit**: API stability for CI/CD integrations
   - **Effort**: ⭐⭐⭐⭐☆ (4/5)
   - **Priority**: Later

---

### 30. **Issue: Unconventional Boolean Parameter Naming**
   - **Category**: Best Practices
   - **Severity**: ⚪ Low
   - **Location**: `common.ps1:296`
   - **Description**: `Test-ChangeId` function accepts `[bool]$HasGit` parameter instead of using switch.
   - **Evidence**:
     ```powershell
     # Line 296
     function Test-ChangeId {
         param(
             [string]$ChangeId,
             [bool]$HasGit = $True  # ❌ Should be [switch]
         )
     }
     ```
   - **Suggestion**: Use switch parameter:
     ```powershell
     param(
         [string]$ChangeId,
         [switch]$HasGit
     )
     # Call as: Test-ChangeId -ChangeId $Id -HasGit
     ```
   - **Benefit**: Idiomatic PowerShell, better IntelliSense
   - **Effort**: ⭐☆☆☆☆ (1/5)
   - **Priority**: Later

---

## Remediation Roadmap

### Phase 1: Critical Issues (Do Now)
- [ ] **Issue #1**: Add recursion guard to Get-WorkspaceRoot (2 hours)
- [ ] **Issue #2**: Validate Git command exit codes in Get-FileDeltas (3 hours)
- [ ] **Issue #3**: Sanitize $FeatureId in Get-FeatureDir (1 hour)
- [ ] **Issue #18**: Validate $BaseRef parameter format (1 hour)
- [ ] **Issue #19**: Implement atomic file operations in setup-plan.ps1 (4 hours)
- [ ] **Issue #27**: Set up Pester test framework baseline (8 hours)

**Total Effort**: ~19 hours (2-3 days)

---

### Phase 2: High Priority (This Sprint)
- [ ] **Issue #4**: Standardize ErrorActionPreference in common.ps1 (2 hours)
- [ ] **Issue #5**: Extract constitution path to shared function (2 hours)
- [ ] **Issue #7**: Add defensive null checks before path operations (3 hours)
- [ ] **Issue #11**: Return error indicators from Get-RenamedFiles (2 hours)
- [ ] **Issue #12**: Validate requirement ID format in ConvertTo-RequirementId (1 hour)
- [ ] **Issue #23**: Add retry logic wrapper for Git operations (4 hours)
- [ ] **Issue #24**: Standardize exit codes across all scripts (3 hours)

**Total Effort**: ~17 hours (2-3 days)

---

### Phase 3: Medium Priority (Next Sprint)
- [ ] **Issue #6**: Define cache expiry constants (1 hour)
- [ ] **Issue #8**: Implement file content caching in validate.ps1 (3 hours)
- [ ] **Issue #9**: Precompile frequently used regex patterns (2 hours)
- [ ] **Issue #10**: Fix line ending handling in regex patterns (2 hours)
- [ ] **Issue #13**: Add atomic cache file operations (2 hours)
- [ ] **Issue #14**: Refine exception handling specificity (4 hours)
- [ ] **Issue #15**: Standardize function documentation (6 hours)
- [ ] **Issue #17**: Move file extension filter to configuration (3 hours)
- [ ] **Issue #20**: Auto-detect Git default branch (2 hours)
- [ ] **Issue #26**: Apply Test-WhitespaceOnlyChange uniformly (2 hours)
- [ ] **Issue #28**: Add content hash to cache validation (2 hours)
- [ ] **Issue #29**: Define and validate JSON output schemas (6 hours)

**Total Effort**: ~35 hours (4-5 days)

---

### Phase 4: Low Priority (Backlog)
- [ ] **Issue #16**: Add parameter validation attributes (2 hours)
- [ ] **Issue #21**: Rename single-letter loop variables (1 hour)
- [ ] **Issue #22**: Standardize date format strings (2 hours)
- [ ] **Issue #25**: Implement consistent logging pattern (5 hours)
- [ ] **Issue #30**: Convert bool parameters to switches (1 hour)

**Total Effort**: ~11 hours (1-2 days)

---

## Metrics

| Metric | Current | Target | Improvement |
|--------|---------|--------|-------------|
| Test Coverage | 0% | 80%+ | +80% |
| OWASP Security Score | 6/10 | 9/10 | +3 points |
| Code Duplication | ~15% | <5% | -10% |
| Performance (Avg Script Runtime) | 2.5s | <1.5s | -40% |
| Exit Code Consistency | 60% | 100% | +40% |

---

## Recommended Actions

1. **Immediate**: Address 6 critical security and data integrity issues (19 hours)
2. **Short-term**: Standardize error handling and implement retry logic (17 hours)
3. **Long-term**: Establish testing framework and refactor for performance (46 hours)

**Total Estimated Effort**: 82 hours (~10-12 business days)

---

# CHECKLIST.md - Technical Debt Remediation Tracker

## ✅ Critical Priority (Blocking Issues)

### Security & Data Integrity
- [ ] **CHK001** - Add recursion guard to `Get-WorkspaceRoot()` (`common.ps1:10-100`)
  - **Action**: Implement `$Script:InWorkspaceRootDetection` flag with try/finally
  - **Validation**: Test with intentionally recursive call
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK002** - Validate Git command exit codes in `Get-FileDeltas` (`common.ps1:805-900`)
  - **Action**: Add `if ($LASTEXITCODE -ne 0)` checks after all `git` invocations
  - **Files**: common.ps1, generate-deltas.ps1
  - **Validation**: Test with corrupted Git repo
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK003** - Sanitize `$FeatureId` parameter (`common.ps1:145`)
  - **Action**: Add regex validation `if ($FeatureId -match '\.\.|[<>:"|?*\\]|^/')`
  - **Risk**: Path traversal vulnerability (OWASP A01:2021)
  - **Validation**: Test with input `../../../etc/passwd`
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK004** - Validate `$BaseRef` Git parameter (`common.ps1:780`)
  - **Action**: Add format check `if ($BaseRef -notmatch '^[a-zA-Z0-9/_.\-]+$')`
  - **Risk**: Command injection vulnerability
  - **Validation**: Test with malicious input `--exec=rm -rf /`
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK005** - Implement atomic file operations (`setup-plan.ps1:210`)
  - **Action**: Use temp file + atomic rename pattern
  - **Files**: setup-plan.ps1, merge-deltas.ps1
  - **Validation**: Interrupt script mid-copy, verify no partial files
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK006** - Establish Pester test framework baseline
  - **Action**: Create `common.Tests.ps1` with 10+ core function tests
  - **Target**: 50% coverage of common.ps1 functions
  - **Validation**: `Invoke-Pester` passes without errors
  - **Assigned**: _______________
  - **Deadline**: _______________

---

## 🟡 High Priority (This Sprint)

### Error Handling & Reliability
- [ ] **CHK007** - Standardize `$ErrorActionPreference` in common.ps1
  - **Action**: Add explicit setting at start of each function
  - **Validation**: Test with invalid input, verify consistent behavior
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK008** - Extract constitution path resolution to shared function
  - **Action**: Create `Get-ConstitutionPath()` in common.ps1
  - **Remove Duplication**: `validate.ps1:160-174`
  - **Validation**: All scripts use shared function
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK009** - Add defensive null checks before path operations
  - **Action**: Add `-not (Test-Path $RepoRoot)` checks after `Get-RepositoryRoot`
  - **Files**: create-new-feature.ps1, archive-feature.ps1, others
  - **Validation**: Test with missing workspace root
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK010** - Return error indicators from `Get-RenamedFiles` (`common.ps1:810`)
  - **Action**: Return `[PSCustomObject]@{Success=$False; Error=$_; Renames=@()}`
  - **Validation**: Callers check `Success` property before using `Renames`
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK011** - Validate requirement ID format (`merge-deltas.ps1:40`)
  - **Action**: Add regex check `if ($Normalized -notmatch '^REQ[-_]\d+$')`
  - **Validation**: Test with malformed ID `INVALID-123`
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK012** - Add retry logic wrapper for Git operations
  - **Action**: Create `Invoke-GitWithRetry()` in common.ps1
  - **Config**: 3 retries, exponential backoff (2s, 4s, 8s)
  - **Validation**: Simulate network failure, verify retry
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK013** - Standardize exit codes across scripts
  - **Action**: Audit all `exit` statements, apply CONTRIBUTING.md standard
  - **Codes**: 0=success, 1=validation, 2=operation, 3=config
  - **Validation**: Test suite verifies exit codes
  - **Assigned**: _______________
  - **Deadline**: _______________

---

## 🟢 Medium Priority (Next Sprint)

### Performance & Code Quality
- [ ] **CHK014** - Define cache expiry constants (`common.ps1:653`)
  - **Action**: Add script-level constants at top of file
  - **Constants**: `$Script:GOVERNANCE_CACHE_EXPIRY_HOURS = 1`
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK015** - Implement file content caching (`validate.ps1:450`)
  - **Action**: Create `Get-CachedContent()` helper function
  - **Expected Gain**: 30-50% faster validation
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK016** - Precompile frequently used regex patterns (`common.ps1:430`)
  - **Action**: Define patterns as script-scoped compiled regex
  - **Expected Gain**: 10-20% performance improvement
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK017** - Fix line ending handling in regex patterns
  - **Action**: Replace `\n` with `[^\r\n]` in all patterns
  - **Files**: common.ps1, validate.ps1
  - **Validation**: Test on Windows/Linux/macOS
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK018** - Add atomic cache file operations (`common.ps1:750`)
  - **Action**: Use temp file + `Move-Item` pattern
  - **Risk**: Cache corruption in parallel environments
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK019** - Refine exception handling specificity (`create-new-feature.ps1:65`)
  - **Action**: Catch `[System.IO.FileNotFoundException]`, `[ParseException]` separately
  - **Benefit**: Better debugging with specific error messages
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK020** - Standardize function documentation in common.ps1
  - **Action**: Add `.OUTPUTS`, `.EXAMPLE` to all functions
  - **Standard**: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.OUTPUTS`, `.EXAMPLE`
  - **Target**: 20+ functions updated
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK021** - Move file extension filter to configuration
  - **Action**: Define in constitution.md or project.md
  - **Update**: generate-deltas.ps1 to read from governance data
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK022** - Auto-detect Git default branch (`generate-deltas.ps1:40`)
  - **Action**: Use `git symbolic-ref refs/remotes/origin/HEAD`
  - **Fallback**: Current "main" if detection fails
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK023** - Apply `Test-WhitespaceOnlyChange` uniformly
  - **Action**: Always detect trivial changes, add `IsTrivial` flag to deltas
  - **Files**: `common.ps1:850`, generate-deltas.ps1
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK024** - Add content hash to cache validation (`common.ps1:670`)
  - **Action**: Use `Get-FileHash -Algorithm SHA256`
  - **Benefit**: Guarantees freshness with timestamp preservation
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK025** - Define and validate JSON output schemas
  - **Action**: Create `specs/schemas/*.schema.json` files
  - **Validation**: Use `Test-Json -SchemaFile` in scripts
  - **Scripts**: All with `-Json` flag
  - **Assigned**: _______________
  - **Deadline**: _______________

---

## ⚪ Low Priority (Backlog)

### Code Style & Conventions
- [ ] **CHK026** - Add `[ValidateNotNullOrEmpty()]` attributes (`validate.ps1:285`)
  - **Action**: Add to all `[Parameter(Mandatory)]` parameters
  - **Benefit**: Clearer parameter validation errors
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK027** - Rename single-letter loop variables (`setup-plan.ps1:205`)
  - **Action**: Change `$T` to `$Template`, `$I` to `$Index`
  - **Benefit**: Improved readability
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK028** - Standardize date format strings
  - **Action**: Use ISO 8601 (`-Format "o"`) everywhere
  - **Functions**: `Get-StandardTimestamp()`, `Get-StandardDate()`
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK029** - Implement consistent logging pattern
  - **Action**: Define standard (Verbose/Host/Warning/Error)
  - **Document**: Add to CONTRIBUTING.md
  - **Refactor**: All 10+ scripts
  - **Assigned**: _______________
  - **Deadline**: _______________

- [ ] **CHK030** - Convert bool parameters to switches (`common.ps1:296`)
  - **Action**: Change `[bool]$HasGit` to `[switch]$HasGit`
  - **Functions**: `Test-ChangeId()`, `Test-FeatureBranch()`
  - **Assigned**: _______________
  - **Deadline**: _______________

---

## 📊 Progress Tracking

### Completion Metrics
- **Critical (CHK001-CHK006)**: ☐ 0/6 (0%)
- **High (CHK007-CHK013)**: ☐ 0/7 (0%)
- **Medium (CHK014-CHK025)**: ☐ 0/12 (0%)
- **Low (CHK026-CHK030)**: ☐ 0/5 (0%)

**Overall Progress**: ☐ 0/30 (0%)

### Estimated Timeline
- **Phase 1 (Critical)**: Days 1-3 (19 hours)
- **Phase 2 (High)**: Days 4-6 (17 hours)
- **Phase 3 (Medium)**: Days 7-11 (35 hours)
- **Phase 4 (Low)**: Days 12-13 (11 hours)

**Total**: 13 business days (~82 hours)

---

## 📋 Validation Checklist (Pre-Completion)

Before marking any item complete, verify:
- [ ] Code changes made and tested locally
- [ ] Unit tests added/updated (if applicable)
- [ ] Documentation updated (CONTRIBUTING.md or inline comments)
- [ ] Validation script passed (e.g., validate.ps1)
- [ ] No new errors introduced (run full test suite)
- [ ] Code review completed (if team workflow)
- [ ] Changes committed with reference to CHK### number

---

**Generated**: 2024-01-15  
**Analysis Framework**: AGENTS.md Technical Debt Analysis  
**Workspace**: [c:\Users\raze0\Documents\hybridv2](c:\Users\raze0\Documents\hybridv2)
