# Master Farmer - Grindbot :: network bootstrap

A three-file Sylvanas plugin that downloads the rest of the bot from GitHub at
runtime. Nothing else lives here.

```
bootstrap/
  header.lua       load gate - local checks only, must be synchronous
  main.lua         drives the fetch, then hands off to the downloaded main.lua
  net_loader.lua   the HTTP loader itself
```

## Install

**Copy this folder out** into your Sylvanas plugins directory as its own plugin,
e.g. `plugins/Master_Farmer_Grindbot_Net/`. Do not run it from inside the source
checkout: Sylvanas expects `header.lua` at the plugin root, and the checkout
already has one of its own.

Do not install both this and the full plugin at the same time. Both register the
same folder key in the session guard, so they would each try to drive the bot.

## Point it at a commit

`main.lua` has two constants:

```lua
local REPO = "L333T/90123-12333-44a-asd32r1f324fg-3f3fqwf-mf"
local SHA  = "e072643382437e557519d6c6aab696f5014be0e8"
```

`SHA` is pinned deliberately. `raw.githubusercontent.com` caches branch URLs for
a few minutes and does not invalidate every path at the same instant, so a
branch URL can serve a fresh `manifest.lua` next to a stale cached module. The
hash check then fails and the whole load aborts — intermittently, only for a few
minutes after each push, which is miserable to diagnose. A commit URL is
immutable, so that cannot happen.

## Shipping an update

From the source checkout, after any `.lua` change:

```bash
python make_manifest.py && git add -A && git commit -m "..." && git push && git rev-parse HEAD
```

Paste the printed SHA into `main.lua`. The manifest must be regenerated and
pushed in the same commit as the code, or the loader rejects the mismatch.

## What you should see in the log

```
[Master Farmer - Grindbot] network bootstrap armed
[Master Farmer - Grindbot] loading v1.3.38 from L333T/90123-... @ e0726433
[MFG/net] fetching https://raw.githubusercontent.com/.../manifest.lua
[MFG/net] manifest 1.3.38: 66 modules
[MFG/net] installed 66 modules into package.preload
[MFG/net] ready: 66 modules in 2.3s
[Master Farmer - Grindbot] handed off to remote main.lua
[Master Farmer - Grindbot] v1.3.38 loaded by BLIZZ - Anthonyk
```

The last line comes from the *downloaded* `main.lua`. If you see it, the handoff
worked.

## Failure modes

| Log line | Cause |
| --- | --- |
| `core.http_get is unavailable` | Build has no HTTP API. Use the normal plugin. |
| `manifest: http 404` | Bad `REPO`/`SHA`, or the commit was never pushed. |
| `html body (portal or error page?)` | Pointed at `github.com` instead of `raw.githubusercontent.com`, or a captive portal. |
| `<file>: hash … expected …` | Manifest and code are out of sync. Regenerate and push together. |
| `timeout after 30s (n/66 modules)` | Slow or blocked connection. |
| `manifest delivered no main.lua` | `main.lua` missing from the manifest; handoff refused to avoid re-entering the bootstrap. |

## Keeping `net_loader.lua` in sync

This is a **copy** of the one in the repo root, because the folder has to be
self-contained. If you change the root copy, re-copy it here.

## Note on trust

This executes code fetched over the network. The Adler-32 in the manifest is an
integrity check — it catches truncation, proxy mangling and half-written files.
It is not an authenticity check: the manifest travels the same channel as the
code, so anyone who can serve you the manifest can serve you anything. The repo
is public, so treat the SHA pin as your real control — it is the one thing that
makes the delivered bytes reproducible.
