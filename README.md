# Codex Browser Request-Header Timeout Fix

Temporary, reversible workaround for a Codex Desktop browser-control failure in
which Edge or Chrome is discovered, but tab RPC calls wait roughly 21 seconds
and then fail with:

```text
nodeRepl.fetch request failed
```

The tested failure occurs before the request is sent to the browser extension.
The bundled browser service waits indefinitely for caller identity while
deciding whether to attach an agent request header. If the identity request does
not settle, unrelated browser RPC calls such as `openTabs()` are blocked too.

This repository contains a narrowly scoped local workaround. It does **not**
contain or redistribute OpenAI's bundled runtime.

Upstream report: [openai/codex#45014](https://github.com/openai/codex/issues/45014)

## Tested environment

- Codex Desktop `26.903.9818.0`
- Windows 11 x64, build `26200`
- `@oai/browser-desktop` `0.1.1`
- bundled Node.js `v24.20.0`
- Microsoft Edge `152.0.4191.66`
- ChatGPT browser extension `1.26.901.11451`
- original `browser-service.mjs` SHA-256:
  `C96DBF28F0854B00B0CF79E936ADFB3754ECB6B0714F94C50A594D3B68940E3E`

## What the workaround changes

The request-header policy lookup is changed to:

1. preserve the normal policy result when identity resolves promptly;
2. fall back to `false` after 2.5 seconds or on rejection;
3. cache the bounded policy result;
4. allow browser RPC dispatch to continue instead of waiting indefinitely.

The fallback only disables the optional agent request header for that browser
service process. It does not bypass browser permissions or authentication.

## Apply

Close Codex Desktop first, then run PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Patch-CodexBrowserService.ps1
```

The script:

- locates the newest bundled `browser-service.mjs`, unless `-BrowserServicePath`
  is supplied;
- requires the exact vulnerable function to occur once;
- creates a timestamped backup beside the runtime file;
- applies the bounded wait;
- runs `node --check` and restores the backup if validation fails;
- is idempotent when the patch is already present.

Start Codex Desktop again after the script succeeds.

## Restore

Close Codex Desktop, then run:

```powershell
.\scripts\Restore-CodexBrowserService.ps1
```

The newest backup created by the patch script is restored and syntax-checked.

## Verify

In a new local Codex task, select Edge or Chrome and request a tab list. In the
tested environment:

| Operation | Before | After |
| --- | ---: | ---: |
| Browser discovery | succeeds | about 0.3 s |
| First `openTabs()` | fails after about 21 s | about 2.5 s |
| Following `tabs.list()` | fails or never dispatches | about 0.003 s |

Exact timings vary by machine and network. The important result is that tab RPC
calls are dispatched after a bounded wait and no longer fail with the opaque
fetch error.

## Limitations

- Codex updates can replace the bundled runtime and remove this workaround.
- The script intentionally stops when the vulnerable code shape has changed.
- This does not address the separate intermittent `Debugger unattached` state.
  Reclaiming the tab or creating a new controlled tab may be required for that
  issue.
- This is an unofficial workaround, not an OpenAI-supported patch.

See [docs/root-cause.md](docs/root-cause.md) for the diagnostic chain and
[patches/request-header-policy-timeout.diff](patches/request-header-policy-timeout.diff)
for a readable conceptual diff.

## License

The scripts and documentation in this repository are MIT licensed. OpenAI's
runtime remains subject to its own license and is not included here.
