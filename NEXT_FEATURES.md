# Next version — feature plan

Source material: a Lua grindbot written against a **different** framework (`awm.*`
plus the stock WoW addon API). None of it is copy-pasteable. This plan maps each
behaviour onto the API this project actually uses, and says where it belongs.

Baseline preserved as tag `working-v1.3.38` and as a file copy at
`Desktop/WORKING_MASTER_FARMER`.

---

## 1. What is already done — do not re-port

A large share of the snippets is already implemented here, often better. Porting
it again would be duplicated, divergent logic.

| Snippet behaviour | Already in this repo |
| --- | --- |
| `Death_Run` safe-spot resurrection, 4 × ±10yd offsets | `death.lua` `safe_retrieve_pos()` — same four offsets |
| "enemies within 8 yards of corpse" check | `death.lua` `hostiles_near()`, `HOSTILE_RANGE = 8.0` |
| `NeedHeal` eat/drink below threshold, must be stationary | `healing.lua` `tick()` + rest latch |
| Food/drink item tables | `data/consumables.lua` (conjured + vendor, ranked) |
| Mage `CheckUse` conjured gems / food / water | `data/consumables.lua` + `rotations/mage.lua` |
| Mage armor / Arcane Intellect buff maintenance | `rotations/mage.lua` `buffs_ooc()` |
| Mob blacklisting by GUID | `state.mark_unreachable()` / `state.is_unreachable()` |
| Vendor trips, selling, repair | `vendor.lua` |

**The remaining value is concentrated in two places: class coverage, and three
gaps in death handling.**

---

## 2. API translation table

Nothing from the snippets maps 1:1. This is the reference for the whole port.

| Snippet call | Correct call here | Notes |
| --- | --- | --- |
| `GetTime()` | `izi.now()` | seconds, float |
| `C_Timer.After(s, fn)` | `izi.after(s, fn)` | used in `movement/locks.lua` |
| `CheckBuff("player", x)` | `player:has_buff({ids})` | **ID list, not name** — see §3 |
| `awm.CastSpellByName(name, "player")` | `spell:cast_safe(player, label)` | `spell = izi.spell({ids})` |
| `DoesSpellExist(name)` | `spellbook.has(key)` / `spell:is_learned()` | `spellbook.lua` resolves ranks |
| `GetItemCount(id)` | `izi.item(id):count()` | cache the item object, see `healing.lua item_of()` |
| `awm.UseItemByName(x)` | `item:use_self_safe(label)` | |
| `GetUnitSpeed("player") > 0` | `movement.is_moving()` | |
| `Try_Stop()` | `movement.nav_stop()` | `movement.halt()` for a full stop |
| `IsMounted()` | `player:is_mounted()` | |
| `awm.UnitAffectingCombat("player")` | `player:is_in_combat()` | |
| `awm.UnitHealth/HealthMax` | `healing.lua health_pct()` pattern | already wrapped |
| `RepopMe()` | `core.input.release_spirit()` | already used in `death.lua` |
| `awm.GetObjectCount()` + index loop | `unit_helper:get_enemy_list_around(pos, yards, ...)` | already used in `death.lua` |
| `awm.FindClosestPointOnMesh(...)` | `movement` ground-snap | **not exported** — see §5.1 |
| `select(5, GetItemInfo(id))` (required level) | — | **no equivalent** — see §5.2 |
| `GetWeaponEnchantInfo()` | — | **no equivalent** — see §5.3 |
| `GetPetHappiness()` / `PetHasActionBar()` | — | **needs verification** — see §5.4 |

`CheckBuff` takes localised **names** in the snippets (`rs["Ice Armor"]`, keyed in
Chinese in the original). This project matches on **spell ID lists**, which is
correct and locale-proof. Every buff ported needs its full rank ID list, not a
name — highest rank first, as in `rotations/mage.lua`:

```lua
local ice_armor = make({ 27124, 10220, 10219, 7320, 7302 }, true, false)
```

A wrong ID fails closed — `spellbook.lua` reports the spell as not learned — but
it fails **silently**, so resolve IDs against the client rather than guessing.

Every Chinese string in the source is translated in
[`docs/SOURCE_TRANSLATION.md`](docs/SOURCE_TRANSLATION.md): spell keys, settings
keys, comments and runtime messages. Use it as the bridge, not as code.

---

## 3. Phase 1 — class coverage (highest value)

Only Mage exists (`rotations/mage.lua`, registered in `rotation.lua`). The
snippets contain OOC buff logic for seven more classes. The seam already exists:

```lua
-- rotations/<class>.lua
function <class>.class_id() return enums.class_id.<CLASS> end
function <class>.buffs_ooc(player) ... end
function <class>.combat_profile() ... end   -- optional, movement rules
```

then one line in `rotation.lua`:

```lua
local priest = require("rotations/priest")
if priest and priest.class_id then by_class[priest.class_id()] = priest end
```

Follow `mage.buffs_ooc()` exactly: guard on `is_in_combat` and `is_mounted`,
check `has_buff({ranks})`, cast with `cast_self_buff`, `return true` after one
action so only one cast happens per tick.

Ordered by effort, lowest first. Ability names below are the translated source
keys — see [`docs/SOURCE_TRANSLATION.md`](docs/SOURCE_TRANSLATION.md).

**3.1 Priest** — *Power Word: Fortitude*, *Shadowform*. Two buffs, no pet, no
consumables. Best first port; it validates the registration path end to end.
Note the source casts Shadowform unconditionally if known — gate it behind a GUI
toggle, since it locks out healing.

**3.2 Druid** — *Mark of the Wild*, *Thorns*. Same shape as Priest.

**3.3 Paladin** — six auras: *Devotion*, *Concentration*, *Retribution*,
*Frost Resistance*, *Shadow Resistance*, *Fire Resistance*. **Only one may be
active at a time**, so this needs a single GUI dropdown, not six toggles — the
source uses six independent booleans and will thrash between them if more than
one is enabled. Do not replicate that.

**3.4 Warlock** — armor spells are straightforward: *Fel Armor* (TBC) supersedes
*Demon Armor*, which supersedes *Demon Skin*; cast the best known one, and treat
all three as one "armor" slot the way `mage.buffs_ooc` treats Ice/Frost Armor.
Pet summoning is **not** straightforward: it gates on Soul Shard count and
`PetHasActionBar()`, and serialises casts behind a 20-second latch. Port armor
first; defer *Summon Imp / Voidwalker / Felhunter / Succubus / Felguard* to
Phase 3 with the other pet work.

**3.5 Shaman** — weapon imbues: *Rockbiter*, *Flametongue*, *Frostbrand*,
*Windfury*. **Blocked on §5.3** (no `GetWeaponEnchantInfo` equivalent). Note the
source has a real bug here worth not copying: it tests `MainHand_Enchant` but
then casts every enabled imbue in sequence without re-checking, so enabling two
makes them overwrite each other every tick.

**3.6 Rogue** — *Instant Poison* I–VII on main and off hand. **Blocked on §5.3**
for the same reason, and additionally needs `UseInventoryItem(16/17)`
(main/off-hand slots), which has no obvious equivalent. Lowest priority; confirm
both APIs exist before starting.

**3.7 Hunter** — *Call Pet*, *Revive Pet*, *Mend Pet*, *Feed Pet*,
*Aspect of the Hawk*, *Trueshot Aura*. Largest job, see Phase 3.

---

## 4. Phase 2 — death handling gaps

`death.lua` already covers the hard part. Three things are missing, all small.

**4.1 Blacklist the mob that killed you.** The snippet adds the killer's GUID to
`Monster_Has_Killed` on death, so the target selector stops offering the thing
that just killed you. The hook already exists — `state.mark_unreachable(guid)`,
which `movement/combat.lua` already calls for unreachable mobs. In
`death.lua begin_death()`, read the current combat target
(`movement.combat_unit()`) and its GUID, and mark it. ~10 lines.

**4.2 Spirit healer fallback after 10 minutes.** The snippet gives up on the
corpse run after 600s and walks to the Spirit Healer, accepting XP loss. Today
a corpse run that cannot succeed retries forever. Add a `RUN_GIVE_UP = 600`
constant and a branch in `death.tick()` that navigates to the healer and uses
`core.quests.select_gossip_option` — the same gossip path `vendor.lua` already
uses. Confirm an "accept resurrection sickness" confirm step is handled.

**4.3 Level-gap filter on corpse threat.** The snippet ignores mobs more than 6
levels below the player when deciding whether a spot is safe — a grey mob near
your corpse is not a threat and currently forces a pointless relocation. Add to
`hostiles_near()`:

```lua
local gap = player_level - safe(function() return u:get_level() end)
if gap > 6 then -- not a threat, skip
```

---

## 5. Known API gaps — resolve before the dependent work

These are the parts that cannot be ported as-is. Each needs a decision.

**5.1 Ground snapping for safe-spot candidates.** The snippet snaps offset
points onto the navmesh (`FindClosestPointOnMesh`). `death.lua` builds raw
`vec3.new(corpse.x ± 10, corpse.y ± 10, corpse.z)` with no snap, so a candidate
can land inside terrain on sloped ground. `movement/util.lua` already has
`U.ground_z(x, y, hint_z)`. **Action:** export it as `movement.ground_z(pos)` in
the facade and use it in `safe_retrieve_pos()`. Cheap, self-contained, and it
improves existing behaviour.

**5.2 Item required-level.** The snippets gate every food/drink on
`select(5, GetItemInfo(id)) <= UnitLevel("player")` — essential, or a level 12
character tries to eat level 55 food. `core.quests.get_item_info()` is used in
`vendor.lua` for quality; **verify whether it exposes required level.**
- If yes: gate at runtime, and the big ID lists can be used directly.
- If no: bake `min_level` into `data/consumables.lua` as
  `{ id = 8932, min_level = 45 }` and extend `healing.lua`'s ranked lists to
  filter on it. This is the likely outcome and is the more robust option anyway.

**5.3 Weapon enchant state.** `GetWeaponEnchantInfo()` drives both rogue poisons
and shaman imbues. No equivalent is in use anywhere in this codebase. **Verify
before committing to 3.5/3.6.** If absent, a time-based fallback (re-apply every
N minutes, tracked in `state`) is workable but inferior — it will waste
reagents. Do not start those classes until this is settled.

**5.4 Pet API. RESOLVED (v1.4.5).** `unit:get_pet`, `unit:is_pet`,
`core.spell_book.get_pet_happiness` and the `core.input.set_pet_*` family all
exist. Implemented as the shared `pets.lua`, used by both
`rotations/hunter.lua` and `rotations/warlock.lua`.

---

## 6. Phase 3 — pets (gated on 5.4)

Hunter is the biggest single feature in the snippets: call pet, revive pet, mend
pet below 50%, feed when happiness < 3, Aspect of the Hawk, Trueshot Aura, and
passive mode out of combat. Warlock summoning shares the same infrastructure.

Do not start this until §5.4 is answered. If pets are exposed, build a shared
`pets.lua` rather than duplicating the logic in two rotation files — both
classes need summon / revive / heal / feed, differing only in spell IDs.

---

## 7. Phase 4 — consumable purchasing

The snippet's `Auto_Purchase` table is a set of intent flags
(`Hunter_Ammo`, `Rogue_Poison`, `Food`, `Lack_Money`, …) that a vendor routine
consumes. `vendor.lua` currently only **sells and repairs**.

Extend it with a buy list: on a vendor trip, top up food/drink to a target
count, plus class reagents (ammo, poison, flash powder, pet food). Model the
data as a per-class table in `data/consumables.lua`. The `Lack_Money` flag maps
to a `core.inventory.get_gold()` check that suppresses retries.

The snippet's arrow/bullet/poison ID lists are directly reusable as **data**,
once level-gated per §5.2.

---

## 8. Suggested order

1. §5.2 and §5.3 verification — two API probes, they unblock the most work
2. §4.1 killer blacklist — smallest real win, ~10 lines
3. §5.1 export `ground_z`, fix `safe_retrieve_pos` — improves existing behaviour
4. §3.1 Priest — validates the class-registration path end to end
5. §3.2 Druid, §3.3 Paladin, §3.4 Warlock armor — same pattern, now proven
6. §4.2 spirit healer fallback
7. §5.4 pet API probe → Phase 3 if viable
8. Phase 4 purchasing

## 9. Ground rules

- `main` stays the verified working version. Feature work happens on `dev`.
- One class per commit, each registered and tested before the next.
- No behaviour goes into `rotation.lua`; classes own their own rules. The
  movement controller owns positioning — classes supply `combat_profile()` only,
  never movement commands.
- Every new module stays well under 200 top-level locals.
- Regenerate `manifest.lua` in the same commit as any `.lua` change.
