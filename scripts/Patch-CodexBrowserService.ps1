[CmdletBinding()]
param(
    [Parameter()]
    [string]$BrowserServicePath,

    [Parameter()]
    [ValidateRange(250, 30000)]
    [int]$TimeoutMilliseconds = 2500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Find-BrowserService {
    $runtimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
    if (-not (Test-Path -LiteralPath $runtimeRoot)) {
        throw "Codex CUA runtime directory was not found: $runtimeRoot"
    }

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
$source = [System.IO.File]::ReadAllText($serviceFile.FullName, [System.Text.Encoding]::UTF8)

$patchedMarker = 'var __codexRequestHeaderPolicyPromise;async function eD()'
if ($source.Contains($patchedMarker)) {
    Write-Host "Already patched: $($serviceFile.FullName)"
    exit 0
}

$vulnerable = 'async function eD(){if(fm==null)throw new Error("Browser request-header policy requires caller identity.");return await fm,ak("codex_browser_use_agent_request_header")}'
$matchCount = ([regex]::Matches($source, [regex]::Escape($vulnerable))).Count
if ($matchCount -ne 1) {
    throw "Expected one vulnerable policy function, found $matchCount. This runtime build is not supported; no file was changed."
}

$replacement = 'var __codexRequestHeaderPolicyPromise;async function eD(){return __codexRequestHeaderPolicyPromise??=(async()=>{if(fm==null)return!1;try{return await Promise.race([fm.then(()=>ak("codex_browser_use_agent_request_header")),new Promise(e=>setTimeout(()=>e(!1),' + $TimeoutMilliseconds + '))])}catch{return!1}})()}'
$patched = $source.Replace($vulnerable, $replacement)

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$($serviceFile.FullName).bak-codex-browser-header-policy-$timestamp"
Copy-Item -LiteralPath $serviceFile.FullName -Destination $backupPath

try {
    [System.IO.File]::WriteAllText(
        $serviceFile.FullName,
        $patched,
        [System.Text.UTF8Encoding]::new($false)
    )

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
    Copy-Item -LiteralPath $backupPath -Destination $serviceFile.FullName -Force
    throw "Patch validation failed and the original file was restored. $($_.Exception.Message)"
}

Write-Host "Patched: $($serviceFile.FullName)"
Write-Host "Backup:  $backupPath"
Write-Host 'Restart Codex Desktop before testing browser control.'
