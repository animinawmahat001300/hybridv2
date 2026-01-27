# Integration test for Capture audit entries during validation
# (specs/changes/003-workflow-audit-logging/quickstart.md#capture-audit-entries-during-validation)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CommonPath = Join-Path $RepoRoot 'specs' 'scripts' 'common.ps1'

. $CommonPath

Describe 'Workflow audit logging' {
    It 'writes a JSONL entry for validation actions' {
        $logPath = Resolve-WorkflowAuditLogPath -RepoRoot $RepoRoot
        $context = @{
            script_name = 'validate.ps1'
            action = 'validate'
            change_id = '003-workflow-audit-logging'
            run_id = ([Guid]::NewGuid().ToString())
            log_path = $logPath
        }

        $writeResult = Write-WorkflowAuditEntry -Context $context -Outcome 'success' -DurationMs 1
        $writeResult.Success | Should -BeTrue

        $lastLine = Get-Content -LiteralPath $logPath -Tail 1
        $entry = $lastLine | ConvertFrom-Json

        $entry.action | Should -Be 'validate'
        $entry.outcome | Should -Be 'success'
        $entry.script_name | Should -Be 'validate.ps1'
    }

    It 'makes audit entries visible within 5 seconds for 95% of runs' {
        $logPath = Resolve-WorkflowAuditLogPath -RepoRoot $RepoRoot
        $context = @{
            script_name = 'validate.ps1'
            action = 'validate'
            change_id = '003-workflow-audit-logging'
            run_id = ([Guid]::NewGuid().ToString())
            log_path = $logPath
        }

        $durations = 1..20 | ForEach-Object {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $writeResult = Write-WorkflowAuditEntry -Context $context -Outcome 'success' -DurationMs 1
            $writeResult.Success | Should -BeTrue

            $lastLine = Get-Content -LiteralPath $logPath -Tail 1
            $lastLine | Should -Not -BeNullOrEmpty

            $stopwatch.Stop()
            $stopwatch.Elapsed.TotalSeconds
        }

        $withinThreshold = ($durations | Where-Object { $_ -le 5 }).Count
        $percentWithin = ($withinThreshold / $durations.Count) * 100
        $percentWithin | Should -BeGreaterOrEqual 95
    }

    It 'writes failure audit entries with sanitized summaries' {
        $logPath = Resolve-WorkflowAuditLogPath -RepoRoot $RepoRoot
        $context = @{
            script_name = 'validate.ps1'
            action = 'validate'
            change_id = '003-workflow-audit-logging'
            run_id = ([Guid]::NewGuid().ToString())
            log_path = $logPath
        }

        $errorMessage = 'token=supersecret; password=example'
        $writeResult = Write-WorkflowAuditEntry -Context $context -Outcome 'failure' -ErrorRecord $errorMessage
        $writeResult.Success | Should -BeTrue

        $lastLine = Get-Content -LiteralPath $logPath -Tail 1
        $entry = $lastLine | ConvertFrom-Json

        $entry.outcome | Should -Be 'failure'
        $entry.error_summary | Should -Not -Match 'supersecret'
        $entry.error_summary | Should -Not -Match 'example'
        $entry.error_summary.Length | Should -BeLessOrEqual 512
    }

    It 'emits a warning when audit append fails' {
        $context = @{
            script_name = 'validate.ps1'
            action = 'validate'
            change_id = '003-workflow-audit-logging'
            run_id = ([Guid]::NewGuid().ToString())
            log_path = '?:\invalid\path\workflow-audit.jsonl'
        }

        $warnings = @()
        $result = Write-WorkflowAuditEntry -Context $context -Outcome 'success' -WarningVariable warnings -WarningAction Continue

        $result.Success | Should -BeFalse
        $warnings.Count | Should -BeGreaterThan 0
    }

    It 'creates the audit log directory when missing' {
        $tempDir = Join-Path $env:TEMP ("speckit-audit-" + [Guid]::NewGuid().ToString())
        $logPath = Join-Path $tempDir 'workflow-audit.jsonl'
        $context = @{
            script_name = 'validate.ps1'
            action = 'validate'
            change_id = '003-workflow-audit-logging'
            run_id = ([Guid]::NewGuid().ToString())
            log_path = $logPath
        }

        try {
            if (Test-Path $tempDir) {
                Remove-Item -Path $tempDir -Recurse -Force
            }

            $result = Write-WorkflowAuditEntry -Context $context -Outcome 'success'
            $result.Success | Should -BeTrue
            Test-Path $tempDir | Should -BeTrue
        } finally {
            if (Test-Path $tempDir) {
                Remove-Item -Path $tempDir -Recurse -Force
            }
        }
    }

    It 'resolves change_id from SPECIFY_CHANGE_ID first' {
        $original = $Env:SPECIFY_CHANGE_ID
        try {
            $Env:SPECIFY_CHANGE_ID = '003-workflow-audit-logging'
            Get-CurrentChangeId | Should -Be '003-workflow-audit-logging'
        } finally {
            $Env:SPECIFY_CHANGE_ID = $original
        }
    }

    It 'reads audit entries using the list helper' {
        $entries = Get-WorkflowAuditEntries -ChangeId '003-workflow-audit-logging' -Outcome 'success' -Limit 1
        $entries.Count | Should -BeGreaterThan 0
        $entries[-1].change_id | Should -Be '003-workflow-audit-logging'
    }

    It 'returns filtered entries in chronological order' {
        $logPath = Resolve-WorkflowAuditLogPath -RepoRoot $RepoRoot
        $context = @{
            script_name = 'validate.ps1'
            action = 'validate'
            change_id = '003-workflow-audit-logging'
            run_id = ([Guid]::NewGuid().ToString())
            log_path = $logPath
        }

        Write-WorkflowAuditEntry -Context $context -Outcome 'success' -DurationMs 1 | Out-Null
        Start-Sleep -Milliseconds 10
        Write-WorkflowAuditEntry -Context $context -Outcome 'success' -DurationMs 1 | Out-Null

        $entries = Get-WorkflowAuditEntries -ChangeId '003-workflow-audit-logging' -Outcome 'success' -Limit 2
        $entries.Count | Should -Be 2

        $firstTimestamp = [DateTime]::Parse($entries[0].timestamp)
        $secondTimestamp = [DateTime]::Parse($entries[1].timestamp)
        $firstTimestamp | Should -BeLessOrEqual $secondTimestamp
    }

    It 'stores audit log output as JSON lines' {
        $logPath = Resolve-WorkflowAuditLogPath -RepoRoot $RepoRoot
        $lines = Get-Content -LiteralPath $logPath -ErrorAction Stop
        $lines.Count | Should -BeGreaterThan 0

        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            { $line | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
        }
    }
}
