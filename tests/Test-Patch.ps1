Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repositoryRoot 'scripts\Patch-CodexBrowserService.ps1'
$restoreScript = Join-Path $repositoryRoot 'scripts\Restore-CodexBrowserService.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-browser-patch-test-" + [guid]::NewGuid())
$fixturePath = Join-Path $temporaryRoot 'browser-service.mjs'

New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
    $fixture = 'const fm=Promise.resolve();const ak=()=>true;async function eD(){if(fm==null)throw new Error("Browser request-header policy requires caller identity.");return await fm,ak("codex_browser_use_agent_request_header")}await eD();'
    [System.IO.File]::WriteAllText($fixturePath, $fixture, [System.Text.UTF8Encoding]::new($false))

    & $patchScript -BrowserServicePath $fixturePath -TimeoutMilliseconds 250
    if ($LASTEXITCODE -ne 0) {
        throw "Patch script exited with $LASTEXITCODE"
    }

    $patched = [System.IO.File]::ReadAllText($fixturePath, [System.Text.Encoding]::UTF8)
    if (-not $patched.Contains('var __codexRequestHeaderPolicyPromise')) {
        throw 'Patched marker was not found.'
    }
    if (-not $patched.Contains('setTimeout(()=>e(!1),250)')) {
        throw 'Requested timeout was not written.'
    }

    & $patchScript -BrowserServicePath $fixturePath -TimeoutMilliseconds 250
    if ($LASTEXITCODE -ne 0) {
        throw "Idempotence check exited with $LASTEXITCODE"
    }

    & $restoreScript -BrowserServicePath $fixturePath
    if ($LASTEXITCODE -ne 0) {
        throw "Restore script exited with $LASTEXITCODE"
    }

    $restored = [System.IO.File]::ReadAllText($fixturePath, [System.Text.Encoding]::UTF8)
    if ($restored -ne $fixture) {
        throw 'The restored fixture does not match the original input.'
    }

    Write-Host 'PATCH_AND_RESTORE_TEST=PASS'
} finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
