[CmdletBinding()]
param(
    [Parameter()]
    [string]$BrowserServicePath,

    [Parameter()]
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Find-BrowserService {
    $runtimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
    $matches = Get-ChildItem -LiteralPath $runtimeRoot -Filter 'browser-service.mjs' -File -Recurse |
        Where-Object { $_.FullName -like '*\node_modules\@oai\browser-desktop\scripts\browser-service.mjs' } |
        Sort-Object LastWriteTimeUtc -Descending

    if (-not $matches) {
        throw 'No bundled @oai/browser-desktop browser-service.mjs was found.'
    }

    return $matches[0].FullName
}

if ([string]::IsNullOrWhiteSpace($BrowserServicePath)) {
    $BrowserServicePath = Find-BrowserService
}

$serviceFile = Get-Item -LiteralPath $BrowserServicePath
if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    $backup = Get-ChildItem -LiteralPath $serviceFile.Directory.FullName -File |
        Where-Object { $_.Name -like "$($serviceFile.Name).bak-codex-browser-header-policy-*" } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $backup) {
        throw "No patch backup was found beside $($serviceFile.FullName)"
    }
    $BackupPath = $backup.FullName
}

$restoreSource = Get-Item -LiteralPath $BackupPath
$preRestoreBackup = "$($serviceFile.FullName).bak-before-restore-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $serviceFile.FullName -Destination $preRestoreBackup
Copy-Item -LiteralPath $restoreSource.FullName -Destination $serviceFile.FullName -Force

try {
    $binDirectory = $serviceFile.Directory.Parent.Parent.Parent.Parent.FullName
    $bundledNode = Join-Path $binDirectory 'node.exe'
    $node = if (Test-Path -LiteralPath $bundledNode) {
        $bundledNode
    } else {
        (Get-Command node -ErrorAction Stop).Source
    }

    & $node --check $serviceFile.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "node --check failed with exit code $LASTEXITCODE"
    }
} catch {
    Copy-Item -LiteralPath $preRestoreBackup -Destination $serviceFile.FullName -Force
    throw "Restore validation failed; the pre-restore file was put back. $($_.Exception.Message)"
}

Write-Host "Restored: $($serviceFile.FullName)"
Write-Host "From:     $($restoreSource.FullName)"
Write-Host "Safety backup: $preRestoreBackup"
Write-Host 'Restart Codex Desktop before testing browser control.'
