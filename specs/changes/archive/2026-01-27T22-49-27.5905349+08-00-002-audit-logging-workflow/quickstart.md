# Quickstart: Workflow audit logging

**Feature**: 002-audit-logging-workflow
**Date**: 2026-01-26

---

# # Overview

This guide shows how workflow scripts append audit entries and how operators review audit trails for a change ID.

---

# # Prerequisites

- PowerShell 7+ with access to `specs/scripts` and `specs/logs`.
- Workflow scripts updated to call the shared audit logging helper.
- Write permission to `specs/logs/workflow-audit.jsonl`.

---

# # Quick Integration

## # Scenario: Record an audit entry for a workflow action

**Goal**: Append a structured audit entry after a workflow script completes.

**Steps**:

1. Build a sanitized audit payload when the action completes.
2. Call the shared audit logging helper to append the entry.
3. Confirm the new JSON line is present in `specs/logs/workflow-audit.jsonl`.

```powershell
$entry = [ordered]@{
	schema_version = 1
	timestamp = (Get-Date).ToString("o")
	script_name = "archive-feature.ps1"
	action = "archive"
	change_id = $ChangeId
	outcome = "success"
	duration_ms = $stopwatch.ElapsedMilliseconds
	execution_id = $ExecutionId
	host = $env:COMPUTERNAME
}

Write-WorkflowAuditLog -Entry $entry
```

---

## # Scenario: Review the audit timeline for a change ID

**Goal**: Filter audit entries to reconstruct workflow activity for a change.

**Steps**:

1. Read the JSONL log file and convert each line to JSON.
2. Filter by `change_id` and sort by timestamp.

```powershell
$entries = Get-Content "specs/logs/workflow-audit.jsonl" |
	ForEach-Object { $_ | ConvertFrom-Json }

$entries |
	Where-Object { $_.change_id -eq "002-audit-logging-workflow" } |
	Sort-Object timestamp
```

---

# # API Reference

| Endpoint | Method | Purpose | Contract |
|----------|--------|---------|----------|
| `/api/workflow-audit` | POST | Append an audit entry | `contracts/workflow-audit/create.yaml` |
| `/api/workflow-audit` | GET | List audit entries (filter by change ID) | `contracts/workflow-audit/list.yaml` |

---

# # Error Handling

| Error Code | Meaning | Resolution |
|------------|---------|------------|
| `AUDIT_LOG_PATH_CREATE_FAILED` | Audit log directory could not be created | Verify permissions for `specs/logs` and retry. |
| `AUDIT_LOG_WRITE_FAILED` | Append failed due to lock or permissions | Retry with backoff and confirm file is writable. |
| `AUDIT_LOG_REDACTION_FAILED` | Error summary could not be sanitized | Log a safe fallback summary and notify the operator. |

---

# # Testing

```powershell
Describe "Write-WorkflowAuditLog" {
	It "writes a JSONL entry with required fields" {
		$entry = @{ timestamp = (Get-Date).ToString("o"); script_name = "validate.ps1"; action = "validate"; outcome = "success" }
		Write-WorkflowAuditLog -Entry $entry -LogPath $TestLogPath
		(Get-Content $TestLogPath | Select-Object -Last 1) | Should -Match '"action":"validate"'
	}

	It "redacts sensitive data in error summaries" {
		$entry = @{ timestamp = (Get-Date).ToString("o"); script_name = "validate.ps1"; action = "validate"; outcome = "failure"; error_summary = "token=abcd" }
		Write-WorkflowAuditLog -Entry $entry -LogPath $TestLogPath
		(Get-Content $TestLogPath | Select-Object -Last 1) | Should -Not -Match 'abcd'
	}
}
```

---

# # Common Issues

- **Permission denied**: ensure the repository checkout allows writes to `specs/logs`.
- **Log locked by another process**: use retry/backoff and confirm no stale file handles remain open.
- **Unexpected large log size**: archive the log and start a new file if size limits are exceeded.




