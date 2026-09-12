# Root-cause analysis

## Symptom boundary

The browser extension and native host can be healthy while browser-control RPCs
still fail. In the reproduced case:

- Edge is discovered as an extension-backed browser;
- the native host process is running;
- extension metadata can be read;
- `getInfo` reaches the extension;
- tab operations such as `openTabs()` wait about 21 seconds and then surface
  `nodeRepl.fetch request failed`.

This places the failure between browser discovery and extension RPC dispatch.

## Blocking dependency

Before sending a browser RPC, the bundled service decides whether to add the
`codex_browser_use_agent_request_header` request header. That decision awaits a
caller-identity promise populated from:

```text
https://chatgpt.com/backend-api/aura/identity
```

The vulnerable implementation waits for that promise without a bound. When the
identity request hangs, tab RPCs never reach the extension even though the
extension connection itself is valid. The outer transport eventually reports
the generic `nodeRepl.fetch request failed` error.

## Why the workaround is narrow

The policy result only controls an optional request header. A bounded fallback
can preserve the header whenever identity resolves normally while preventing
the policy dependency from blocking unrelated browser operations forever.

The workaround races the identity lookup against a 2.5-second timeout, returns
`false` on timeout or rejection, and caches the result for the service process.
No browser permission, site access, tab claim, or authentication check is
removed.

## Validation evidence

After applying the workaround in the tested build:

- JavaScript syntax validation passed with the bundled Node.js executable;
- browser discovery completed in about 299 ms;
- the first tab enumeration completed in about 2534 ms;
- subsequent tab listing completed in about 3 ms;
- a real Edge tab could be claimed and its title and URL read;
- the earlier `nodeRepl.fetch request failed` did not recur in that path.

## Upstream recommendation

The supported fix should be made in the unbundled source rather than in a
generated minified runtime:

- do not make browser RPC dispatch depend indefinitely on identity telemetry or
  optional request-header policy;
- add a bounded timeout and rejection handling;
- cache the resolved policy state;
- expose the underlying dependency failure in diagnostics;
- test extension discovery plus tab enumeration while the identity endpoint is
  stalled or unavailable.
