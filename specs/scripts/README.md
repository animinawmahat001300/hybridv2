# SpecKit Scripts

This directory contains PowerShell automation scripts for the SpecKit workflow.

# # Coding Conventions

## # Placeholder Format Standards

SpecKit uses context-specific placeholder formats to avoid ambiguity:

| Context | Format | Example | When to Use |
|---------|--------|---------|-------------|
| **Template tokens** | `{SCREAMING_SNAKE}` | `{SRC_ROOT}`, `{CHANGE_ID}` | In template files (specs/templates/*.md) |
| **Variable references** | `$camelCase` or `$PascalCase` | `$srcRoot`, `$FeatureDir` | In code examples and scripts |
| **Documentation examples** | `<kebab-case>` | `<change-id>` | ONLY in human-readable docs, NOT in agent instructions |

**Critical Rules**:
- Agent instructions MUST use `{PLACEHOLDER}` format to match templates
- NEVER use `<placeholder>` format in agent instructions (causes parsing issues)
- Scripts use PowerShell variable syntax: `$variableName`

## # Variable Naming Conventions

| Scope | Convention | Example | Rationale |
|-------|-----------|---------|------------|
| **Function parameters** | PascalCase | `$FeatureDir` | PowerShell standard |
| **Local variables** | camelCase | `$featureDir` | Distinguish from params |
| **Script-level constants** | SCREAMING_SNAKE | `$REPO_ROOT` | Indicates immutable value |
| **Environment variables** | SCREAMING_SNAKE | `$env:SPECIFY_CHANGE_ID` | OS convention |
| **Hashtable keys (data)** | PascalCase | `$data.FeatureDir` | PowerShell object convention |
| **Template placeholders** | `{SCREAMING_SNAKE}` | `{FEATURE_DIR}` | Clearly indicates replacement token |

**Examples**:
```powershell
# ✅ CORRECT
function Get-FeaturePath {
    param([string]$FeatureDir)  # Parameter: PascalCase
    
    $repoRoot = $env:REPO_ROOT  # Local var: camelCase, env: SCREAMING
    return Join-Path $repoRoot $FeatureDir
}

# ❌ INCORRECT
function Get-FeaturePath {
    param([string]$feature_dir)  # Wrong: snake_case
    
    $RepoRoot = $env:repo_root  # Wrong: PascalCase for local, lowercase for env
    return Join-Path $RepoRoot $feature_dir
}
```

## # PowerShell Function Naming

All functions MUST use approved PowerShell verbs. Common mappings:

| Non-Approved | Approved | Example |
|--------------|----------|---------|
| `Load-*` | `Import-*` | `Import-ConstitutionRules` |
| `Validate-*` | `Test-*` | `Test-SpecFile` |
| `Extract-*` | `Get-*` | `Get-GovernanceContext` |
| `Normalize-*` | `ConvertTo-*` | `ConvertTo-RequirementId` |

Check approved verbs with: `Get-Verb`

## # Path Reference Standards

SpecKit uses different path formats depending on document context:

| Document Type | Format | Example | Rationale |
|--------------|--------|---------|------------|
| **Templates** | Full relative with `{PLACEHOLDER}` | `specs/changes/{CHANGE_ID}/spec.md` | Absolute clarity for code generation |
| **Agent instructions** | `FEATURE_DIR/` prefix | `FEATURE_DIR/spec.md` | Agents replace FEATURE_DIR with actual path |
| **PowerShell code** | Variable | `$FeatureDir/spec.md` or `Join-Path $FeatureDir 'spec.md'` | Proper PS syntax |
| **README examples** | Generic with `<>` | `<change-id>` | Human-readable, not for agents |

**Key Distinctions**:
- `{CHANGE_ID}` = The identifier slug (e.g., "markdown-normalization")
- `FEATURE_DIR` = The full resolved path (e.g., "specs/changes/markdown-normalization")
- **Never use them interchangeably**

**Path Reference Examples for Agents**:

When reading from templates:
- Templates contain: `specs/changes/{CHANGE_ID}/spec.md`
- Replace `{CHANGE_ID}` with the actual feature identifier

When writing instructions:
- Use `FEATURE_DIR/spec.md` format
- FEATURE_DIR will be replaced with full path during execution

When writing PowerShell code:
- Use variables: `$FeatureDir/spec.md`
- Or Join-Path: `Join-Path $FeatureDir 'spec.md'`

## # Audit Logging

Workflow scripts MUST emit audit log entries for state-changing operations
(create, update, validate, archive). Follow the constitution requirements:

- Write append-only JSON lines to `specs/logs/workflow-audit.jsonl`
- Use `Write-WorkflowAuditEntry` from `specs/scripts/common.ps1` to ensure
   schema compliance and append-only writes
- Use `New-WorkflowScriptRunMetadata` and `New-WorkflowAuditContext` to populate
   `run_id`, `change_id`, and `duration_ms` consistently across scripts
- Use `Get-WorkflowAuditEntries` to read audit history (GET /api/workflow-audit)
- Include: `timestamp` (ISO 8601), `script`, `action`, `change_id`, `outcome`,
   and sanitized error summaries (if applicable)
- Create the log directory if it does not exist
- Log failures before exiting with non-zero status
- Warn if audit log append fails to preserve append-only verification
- Exclude secrets or PII and avoid sensitive data in audit payloads

# # Automated Workflow Scripts

These scripts are integrated into the agent workflow and run automatically:

| Script | Purpose | Used By | Status |
|--------|---------|---------|--------|
| `validate.ps1` | Validates spec completeness with optional strict mode | speckit.checklist.agent.md | ✅ Active |
| `create-new-feature.ps1` | Creates new feature directory structure | speckit.specify.agent.md | ✅ Active |
| `setup-document.ps1` | Gathers context for workflow guide (read-only) | speckit.document.agent.md | ✅ Active |
| `setup-plan.ps1` | Scaffolds plan.md with sections | speckit.plan.agent.md | ✅ Active |
| `archive-feature.ps1` | Archives completed features | speckit.archive.agent.md | ✅ Active |
| `update-agent-context.ps1` | Refreshes agent memory files | Multiple agents | ✅ Active |

# # Manual Development Tools

These scripts are for manual troubleshooting and auditing. Located in `manual/`:

| Script | Purpose | Usage | When to Use |
|--------|---------|-------|-------------|
| `validate-paths.ps1` | Audits agent files for invalid path references | `./manual/validate-paths.ps1` | When debugging agent path issues |
| | | `./manual/validate-paths.ps1 -Strict` | Enforce zero warnings |
| | | `./manual/validate-paths.ps1 -Json` | For CI/CD integration |
| `test-placeholder-consistency.ps1` | Validates template placeholders match agent instructions | `./manual/test-placeholder-consistency.ps1` | Before agent deployment |
| | | `./manual/test-placeholder-consistency.ps1 -Json` | For CI/CD validation |

## # validate-paths.ps1 Details

**Purpose**: Validates that all 11 SpecKit agent files use workspace-relative paths correctly.

**Detects**:
- ❌ Absolute paths from root (e.g., `hybrid/specs/` instead of `specs/`)
- ❌ Wrong workspace references (e.g., `.specify/` instead of `specs/`)
- ⚠️ Hardcoded OS-specific paths (e.g., `c:\`, `/Users/`, `/home/`)

**Parameters**:
- `-AgentDir`: Directory containing agent files (default: `.github/agents`)
- `-Json`: Output results in JSON format
- `-Strict`: Fail on warnings (treats warnings as errors)

**Exit Codes**:
- `0` = PASS (all validations passed)
- `1` = FAIL (invalid paths detected)
- `2` = ERROR (agent directory not found)

**Example Output**:
```
=== Path Validation Results ===

Agents checked: 11
Agents passed:  11
Agents failed:  0

Status: PASS
```

**When to Run**:
- After modifying agent file paths
- When debugging "file not found" errors in agents
- During agent file refactoring
- As part of pre-commit validation (optional)

# # Library Files

| File | Purpose | Status |
|------|---------|--------|
| `common.ps1` | Shared utility functions | ✅ Active |
| `artifact-registry.json` | Template registry for create-new-feature.ps1 | ✅ Active |

# # Manual Tools (manual/)

Scripts for manual use by developers/maintainers, not invoked by agents:

- `audit-references.ps1` - Full validation of file references (use with -Strict for CI)
- `audit-references-report.ps1` - Preview scan scope before running audit-references.ps1
- `validate-paths.ps1` - Validates file paths in agent prompts and scripts

# # Deprecated/Archive Scripts

The following scripts are no longer used and located in `archive/`:

- `generate-deltas.ps1` - Superseded by direct spec editing
- `generate-proposal.ps1` - Reserved for Phase 3 OpenSpec integration
- `list-features.ps1` - Superseded by agent context management
- `merge-deltas.ps1` - No longer needed
- `populate-project.ps1` - Superseded by create-new-feature.ps1
- `run-gates.ps1` - Superseded by validate.ps1

# # Testing

Unit tests for scripts are located in `tests/` subdirectory.

Run all tests:
```powershell
Invoke-Pester ./tests/
```

# # Contributing

When adding new scripts:

1. **Determine category**:
   - Automated workflow → Place in root `specs/scripts/`
   - Manual tool → Place in `specs/scripts/manual/`
   - Archive → Place in `specs/scripts/archive/`

2. **Add documentation**:
   - Include synopsis, description, parameters, examples in script header
   - Update this README.md with usage information

3. **Add tests**:
   - Create Pester test file in `tests/`
   - Test all parameters and edge cases

4. **Agent integration** (if automated):
   - Update relevant agent file with script reference
   - Document in agent step with usage example
   - Add validation criteria in agent

# # Quick Reference

| Task | Command |
|------|---------|
| Validate spec completeness | `./validate.ps1` |
| Validate spec (strict mode) | `./validate.ps1 -Strict` |
| Create new feature | `./create-new-feature.ps1 -FeatureName "my-feature"` |
| Archive feature | `./archive-feature.ps1 -FeatureName "my-feature"` |
| Audit agent paths | `./manual/validate-paths.ps1` |
| Update agent context | `./update-agent-context.ps1` |


