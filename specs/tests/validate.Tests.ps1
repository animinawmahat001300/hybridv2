$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$validatePath = Join-Path $repoRoot 'specs' 'scripts' 'validate.ps1'
$featureDir = Join-Path $repoRoot 'specs' 'changes' 'test-validation'
$specPath = Join-Path $featureDir 'spec.md'

BeforeAll {
    if (-not (Test-Path $featureDir)) {
        New-Item -Path $featureDir -ItemType Directory -Force | Out-Null
    }

    $specContent = @"
# Spec: Validation Test

## Overview
Minimal spec to validate the workflow paths.

## Requirements

### Requirement: Example requirement **REQ-001**
The system MUST log a message when the action occurs.

#### Scenario: Basic
- Given a user performs the action
- When the action completes
- Then the system logs the message
"@

    Set-Content -LiteralPath $specPath -Value $specContent -Encoding UTF8
}

AfterAll {
    if (Test-Path $featureDir) {
        Remove-Item -LiteralPath $featureDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'validate.ps1 workflow paths' {
    It 'returns success for a valid spec' {
        $result = & $validatePath -Target $specPath -Json | ConvertFrom-Json
        $result.status | Should -Be 'success'
        $result.data.valid | Should -BeTrue
    }

    It 'returns validation_error for a missing target' {
        $missingPath = Join-Path $featureDir 'missing.md'
        $result = & $validatePath -Target $missingPath -Json | ConvertFrom-Json
        $result.status | Should -Be 'validation_error'
        $result.data.valid | Should -BeFalse
    }
}
