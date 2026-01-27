# Quickstart: Workflow audit logging for scripts

**Feature**: 003-workflow-audit-logging
**Date**: 2026-01-27

---

# # Overview

This guide shows how workflow scripts record append-only audit entries for every state-changing action using a shared PowerShell helper.

---

# # Prerequisites

- PowerShell 7.4+ installed
- Repository cloned with write access to `specs/logs/`
- Workflow scripts run from the repo root or can resolve it

---

# # Quick Integration

## # Scenario: Capture audit entries during validation

**Goal**: Add audit logging to a workflow script action and verify the JSONL entry appears.

**Steps**:

1. Import the shared helper from `specs/scripts/common.ps1` in the workflow script.
2. Wrap the state-changing action with audit logging calls.
3. Run the workflow script and confirm a new JSONL entry appears in `specs/logs/workflow-audit.jsonl`.
4. Check that `Write-WorkflowAuditEntry` returns `Success = true` to verify append-only logging.

```powershell
Import-Module "$PSScriptRoot/common.ps1"

$actionContext = @{ script_name = "validate.ps1"; action = "validate"; change_id = $env:SPECIFY_CHANGE_ID }
try {
	Write-WorkflowAuditEntry -Context $actionContext -Outcome "success"
} catch {
	Write-WorkflowAuditEntry -Context $actionContext -Outcome "failure" -ErrorRecord $_
	throw
}
```

	---

	## # Scenario: Verify audit visibility and performance

	**Goal**: Confirm audit entries become visible within 5 seconds and measure append latency.

	**Steps**:

	1. Write a single audit entry and confirm the log updates within 5 seconds.
	2. Run a short batch and record p95 append latency (target ≤ 50 ms).
	3. Run a 20-entry visibility sample and confirm ≥ 95% are retrievable within 5 seconds using `Get-WorkflowAuditEntries` or log tail.
	4. Compare a representative workflow run with and without logging to confirm runtime impact ≤ 10% (baseline: pre-audit commit).

	```powershell
	$logPath = Resolve-WorkflowAuditLogPath -RepoRoot $RepoRoot
	$context = @{ script_name = "validate.ps1"; action = "validate"; change_id = "003-workflow-audit-logging"; run_id = [Guid]::NewGuid().ToString() }

	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	Write-WorkflowAuditEntry -Context $context -Outcome "success" | Out-Null
	Get-Content -LiteralPath $logPath -Tail 1 | Out-Null
	$stopwatch.Stop()
	$stopwatch.Elapsed.TotalSeconds  # Must be ≤ 5 seconds

	$durations = 1..20 | ForEach-Object {
		(Measure-Command { Write-WorkflowAuditEntry -Context $context -Outcome "success" | Out-Null }).TotalMilliseconds
	}
	$sorted = $durations | Sort-Object
	$p95Index = [Math]::Max([Math]::Ceiling($sorted.Count * 0.95) - 1, 0)
	$p95 = $sorted[$p95Index]
	$p95  # Target ≤ 50 ms

	# Runtime impact check (manual): measure a representative workflow with logging on/off
	# and confirm total duration delta ≤ 10%.
	```

	**Sample measurements (2026-01-27)**:
	- Visibility sample (20 entries): **100%** within 5 seconds
	- p95 append latency (20 samples): **12.98 ms**
	- Runtime impact baseline (pre-audit commit) not measured in this workspace; use a representative workflow comparison for compliance.
	- `validate.ps1 -Target 003-workflow-audit-logging -Strict`: **PASS**
	- Manual constitution check fallback: compare `spec.md` against `specs/memory/constitution.md` if strict validation is unavailable.
	- Manual constitution check result: not required (strict validation passed).

	## # Validation Gate Evidence

	- **Phase 0 Gate**: `validate.ps1 -Target 003-workflow-audit-logging -Strict` passed on 2026-01-27.
	- **Phase 1 Gate**: `validate.ps1 -Target 003-workflow-audit-logging -Strict` passed on 2026-01-27.
	- **Phase 2 Gate**: `validate.ps1 -Target 003-workflow-audit-logging -Strict` passed on 2026-01-27.

---

# # API Reference

| Endpoint | Method | Purpose | Contract |
|----------|--------|---------|----------|
| /api/workflow-audit | POST | Record an audit entry | `contracts/workflow-audit/create.yaml` |
| /api/workflow-audit | GET | List audit entries | `contracts/workflow-audit/list.yaml` |

---

# # Error Handling

| Error Code | Meaning | Resolution |
|------------|---------|------------|
| LOG_WRITE_FAILED | Audit entry could not be appended | Retry append, confirm file permissions, log failure before exit |
| LOG_DIR_CREATED | Audit log directory was missing | Directory auto-created; verify path if unexpected |
| SANITIZATION_FAILED | Error summary was rejected or truncated | Ensure error summary is string-safe and under length limit |

---

# # Testing

Use Pester to validate audit logging behavior:

```powershell
It "writes an audit entry for successful actions" {
	$logPath = Join-Path $RepoRoot "specs/logs/workflow-audit.jsonl"
	Write-WorkflowAuditEntry -Context @{ action = "validate"; changeId = "003-workflow-audit-logging" } -Outcome "success"
	(Get-Content $logPath -Tail 1) | Should -Match "\"action\":\"validate\""
}
```

---

# # Common Issues

- **File locked**: Retry after a short delay; concurrent runs should append without truncation.
- **Missing permissions**: Ensure the runner can write to `specs/logs/`.
- **Large log file**: Follow repository rotation/archival guidance; this change does not auto-rotate logs.
- **Clock skew**: Entries use host timestamps; ensure time sync on runners when audit ordering matters.
- **Unexpected placeholders**: Re-run `specs/scripts/validate.ps1 -Json` to confirm artifacts are valid.




