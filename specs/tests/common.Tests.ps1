$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$commonPath = Join-Path $repoRoot 'specs' 'scripts' 'common.ps1'
. $commonPath

Describe 'SpecKit common.ps1 helpers' {
    It 'resolves absolute paths' {
        $tempPath = Join-Path $TestDrive 'relative-path'
        $resolved = Resolve-AbsolutePath -Path $tempPath
        $resolved | Should -Not -BeNullOrEmpty
        [System.IO.Path]::IsPathRooted($resolved) | Should -BeTrue
    }

    It 'validates safe path segments' {
        Test-SafePathSegment -Segment 'valid-segment' | Should -BeTrue
        Test-SafePathSegment -Segment '..\invalid' | Should -BeFalse
    }

    It 'updates cached file content when files change' {
        $filePath = Join-Path $TestDrive 'cache.txt'
        Set-Content -LiteralPath $filePath -Value 'one' -Encoding UTF8
        $firstRead = Get-FileContentCached -Path $filePath -Raw
        Set-Content -LiteralPath $filePath -Value 'two' -Encoding UTF8
        $secondRead = Get-FileContentCached -Path $filePath -Raw
        $firstRead | Should -Be 'one'
        $secondRead | Should -Be 'two'
    }

    It 'detects filesystem deltas without git' {
        $featureDir = Join-Path $TestDrive 'feature'
        New-Item -Path $featureDir -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $featureDir 'example.md') -Value 'content' -Encoding UTF8

        $deltas = Get-FileSystemDeltas -FeatureDir $featureDir
        ($deltas | Where-Object { $_.Operation -eq 'ADDED' }).Count | Should -Be 1
    }

    It 'detects workspace root when available' {
        $root = Get-WorkspaceRoot
        $root | Should -Not -BeNullOrEmpty
        (Test-Path (Join-Path $root 'specs' 'memory' 'constitution.md')) | Should -BeTrue
    }
}
