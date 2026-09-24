# Master Farmer - Grindbot

Standalone IZI plugin for Project Sylvanas (TBC). Authors: BLIZZ - Anthonyk.

This repository is the **full bot** (engine, GUI, grind/quest packs, paths, loot, movement). Current payload version: **1.3.39**.

## Install the engine (local copy)

Copy this folder into your Sylvanas scripts directory as `Master_Farmer_Grindbot_v1.3.39`.

## Install the HTTP runner (1.4.0)

Copy `bootstrap/` from this repo into your Sylvanas scripts directory as `Master_Farmer_Grindbot_v1.4.0` (or use the sibling folder of that name). That plugin:

1. GETs `manifest.json` from this repo
2. GETs each listed `.lua` file from `raw.githubusercontent.com`
3. Caches them under `scripts_data/mfg_http/`
4. Compiles and runs `main.lua`

Raw base:

`https://raw.githubusercontent.com/L333T/1022003434-1123453-a1c4zz3456-1234-mf/main/`

The GitHub repo should be **public** so `core.http_get` can read it without a token.

Do not enable 1.3.39 and 1.4.0 at the same time.
