# Master Farmer - Grindbot :: HTTP plugin loader

A three-file Sylvanas plugin that downloads the bot from GitHub at runtime.

```
plugin_loader/
  header.lua        load gate - local checks only, must be synchronous
  main.lua          drives the load, then hands off to the downloaded main.lua
  http_loader.lua   the loader itself
```

This replaces the earlier `bootstrap/` folder. See **What changed** below.

## Install

Copy this folder into your Sylvanas plugins directory as its own plugin. Do not
install it alongside a local copy of the bot — both would register update
callbacks and drive the same character.

It appears in Sylvanas as **Master Farmer - Grindbot (HTTP)** so it is
distinguishable from a normal install at a glance.

## Point it at a commit

`main.lua`:

```lua
local REPO = "L333T/90123-12333-44a-asd32r1f324fg-3f3fqwf-mf"
local SHA  = "e072643382437e557519d6c6aab696f5014be0e8"
```

The SHA pin is deliberate. `raw.githubusercontent.com` caches branch URLs for a
few minutes and does not invalidate every path at the same instant, so a branch
URL can serve a fresh `manifest.lua` beside a stale cached module. The hash
check then fails and the whole load aborts — intermittently, only for a few
minutes after each push. A commit URL is immutable, so that cannot happen.

For a private repo, set `HEADERS` in `main.lua`. The token then ships inside the
file, so scope it read-only to that one repo.

## Shipping an update

```bash
python make_manifest.py && git add -A && git commit -m "..." && git push && git rev-parse HEAD
```

Paste the printed SHA into `main.lua`. The manifest must be regenerated and
pushed in the same commit as the code, or the loader rejects the mismatch.

## API this is written against

```
core.http_get(url, callback)
core.http_get(url, headers, callback)
callback(http_code, content_type, response_data, response_headers)
```

Both overloads are used: `headers` is passed only when configured, because
passing `nil` in that slot would land the callback in the headers position.
`core.http_post` exists but a loader only reads, so it is unused.

`http_code` may be **0** on transport failure — that is treated as retryable.

## What changed from `bootstrap/`

Each of these was found by running the loader against a mock of the documented
API in a real Lua interpreter, not by reading it.

| Fix | Why it mattered |
| --- | --- |
| `http_code` is coerced with `tonumber()` before any comparison | A `nil` code made `http_code >= 500` raise *inside the HTTP callback*, propagating an error back across the native boundary. |
| Duplicate deliveries no longer advance the counter | A module delivered twice could push `got` to `want` while another was still outstanding, installing an incomplete set. |
| Retries are queued and re-issued from `pulse()` with a backoff | A code-0 transport failure can return instantly; inline retries burned the entire retry budget inside one frame without pausing. |
| The bot's `folder` key is read from the downloaded `version.lua` | The old loader hardcoded it. It drifted to `1.3.39` while the repo said `1.3.38`, and a drifted key breaks `is_stale()` **silently** — the bot watches a counter nobody increments, so stale callbacks survive reloads and stack. |
| `require()` is probed with a sentinel before trusting `package.preload` | Testing that `package.preload` *exists* does not prove `require` *consults* it. A host with its own plugin-scoped require leaves a normal-looking `package.preload` untouched — so every module "installed" was unreachable while the loader reported success. Now a sentinel module is installed and required for real; if it does not resolve, the require wrapper is used instead. |
| `package.loaded[name]` is cleared before installing each module | `require` checks `package.loaded` *before* `package.preload`. A generic name like `version` or `state` already cached by another plugin shadowed ours permanently, and we silently read that plugin's table instead. |
| 408 added to the retryable set; `^%a+://` rejected in manifest paths | Request Timeout is retryable; an absolute URL in a manifest entry would otherwise escape `base_url`. |

## Expected log

```
[MFG-HTTP] armed
[MFG-HTTP] loading from L333T/90123-... @ e0726433
[MFG/http] fetching https://raw.githubusercontent.com/.../manifest.lua
[MFG/http] manifest 1.3.38: 66 modules
[MFG/http] installed 66 modules into package.preload
[MFG/http] ready: 66 modules in 2.3s
[MFG-HTTP] handed off to Master Farmer - Grindbot v1.3.38
[Master Farmer - Grindbot] v1.3.38 loaded by BLIZZ - Anthonyk
```

The last line comes from the *downloaded* `main.lua`. If you see it, the handoff
worked.

## Failure modes

| Log | Cause |
| --- | --- |
| `core.http_get is unavailable` | Build has no HTTP API. |
| `manifest: http 404` | Bad `REPO`/`SHA`, or the commit was never pushed. |
| `html body (wrong URL, or a captive portal?)` | Pointed at `github.com` instead of `raw.githubusercontent.com`, or a portal intercepted it. |
| `hash …, expected … (manifest and code are out of sync)` | Regenerate the manifest and push it in the same commit. |
| `timeout after 30s (n/66 modules)` | Slow or blocked connection. |
| `the manifest delivered no main.lua` | Handoff refused rather than re-entering the loader. |
| `base_url must be https` | Plain http is rejected. |

## Note on trust

This executes code fetched over the network. The Adler-32 in the manifest is an
**integrity** check — truncation, proxy mangling, half-written files. It is not
**authenticity**: the manifest travels the same channel as the code, so whoever
can serve the manifest can serve anything. The repo is public, so the SHA pin is
the real control — it is what makes the delivered bytes reproducible.

This does **not** work around Lua's 200-local limit. `load()` runs the same
compiler as the disk loader, so an oversized chunk fails identically.
