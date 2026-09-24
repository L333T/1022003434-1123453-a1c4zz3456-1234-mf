# Reference grindbot — Chinese source strings, translated

Every Chinese string in the reference snippets, translated. The source keys its
spells by **localised name** (`rs["冰甲术"]`), which is why it needs this table at
all. This project keys by **spell ID**, which is locale-proof — so these names
are a bridge for the port, never something to put in code.

Spell IDs are deliberately **not** listed here. Resolve them at implementation
time against the rank-ordered arrays already used in `rotations/mage.lua`. A
wrong ID fails closed — `spellbook.lua` simply reports the spell as not learned —
but it fails silently, so guessing is not worth it.

---

## 1. Spell keys (`rs[...]`)

### Consumable / state auras
| Chinese | English |
| --- | --- |
| 假死 | Feign Death |
| 进食 | Food (eating aura) |
| 喝水 | Drink (drinking aura) |

### Mage
| Chinese | English |
| --- | --- |
| 冰甲术 | Ice Armor |
| 霜甲术 | Frost Armor |
| 法师魔甲术 | Mage Armor |
| 熔岩护甲 | Molten Armor |
| 奥术智慧 | Arcane Intellect |
| 法力红宝石 | Mana Ruby |
| 制造魔法红宝石 | Conjure Mana Ruby |
| 法力黄水晶 | Mana Citrine |
| 制造魔法黄水晶 | Conjure Mana Citrine |
| 法力翡翠 | Mana Jade |
| 制造魔法翡翠 | Conjure Mana Jade |
| 法力玛瑙 | Mana Agate |
| 制造魔法玛瑙 | Conjure Mana Agate |
| 法力刚玉 | Mana Emerald |
| 制造魔法玉石 | Conjure Mana Emerald |

> All of the above are already implemented — see `rotations/mage.lua` and
> `data/consumables.lua`. Listed only for completeness.

### Priest
| Chinese | English |
| --- | --- |
| 暗影形态 | Shadowform |
| 真言术：韧 | Power Word: Fortitude |

### Warlock
| Chinese | English |
| --- | --- |
| 邪甲术 | Fel Armor |
| 恶魔皮肤 | Demon Skin |
| 术士魔甲术 | Demon Armor |
| 灵魂碎片 | Soul Shard (item) |
| 召唤恶魔卫士 | Summon Felguard |
| 召唤魅魔 | Summon Succubus |
| 召唤地狱猎犬 | Summon Felhunter |
| 召唤虚空行者 | Summon Voidwalker |
| 召唤小鬼 | Summon Imp |

### Hunter
| Chinese | English |
| --- | --- |
| 召唤宠物 | Call Pet |
| 复活宠物 | Revive Pet |
| 治疗宠物 | Mend Pet |
| 喂养宠物 | Feed Pet |
| 雄鹰守护 | Aspect of the Hawk |
| 强击光环 | Trueshot Aura |

### Druid
| Chinese | English |
| --- | --- |
| 野性印记 | Mark of the Wild |
| 荆棘术 | Thorns |

### Paladin (auras — only one may be active)
| Chinese | English |
| --- | --- |
| 虔诚光环 | Devotion Aura |
| 冰霜抗性光环 | Frost Resistance Aura |
| 专注光环 | Concentration Aura |
| 暗影抗性光环 | Shadow Resistance Aura |
| 惩戒光环 | Retribution Aura |
| 火焰抗性光环 | Fire Resistance Aura |

### Shaman (weapon imbues)
| Chinese | English |
| --- | --- |
| 石化武器 | Rockbiter Weapon |
| 火舌武器 | Flametongue Weapon |
| 冰封武器 | Frostbrand Weapon |
| 风怒武器 | Windfury Weapon |

### Rogue
| Chinese | English |
| --- | --- |
| 速效药膏 | Instant Poison |
| 速效药膏 II – VII | Instant Poison II – VII |

### NPC
| Chinese | English |
| --- | --- |
| 灵魂医者 | Spirit Healer |

---

## 2. Settings keys (`Easy_Data.Combat[...]`)

These are the source's per-class toggles. They map onto GUI entries here — see
the existing `ice_armor` / `mage_armor` / `molten_armor` toggles.

| Chinese | English toggle |
| --- | --- |
| 法师冰甲术 | Mage: Ice Armor |
| 法师魔甲术 | Mage: Mage Armor |
| 法师熔岩护甲 | Mage: Molten Armor |
| 术士邪甲术 | Warlock: Fel Armor |
| 术士恶魔皮肤 | Warlock: Demon Skin |
| 术士魔甲术 | Warlock: Demon Armor |
| 术士召唤恶魔卫士 | Warlock: Summon Felguard |
| 术士召唤魅魔 | Warlock: Summon Succubus |
| 术士召唤地狱猎犬 | Warlock: Summon Felhunter |
| 术士召唤虚空行者 | Warlock: Summon Voidwalker |
| 术士召唤小鬼 | Warlock: Summon Imp |
| 盗贼毒药 | Rogue: Poisons |
| 骑士虔诚光环 | Paladin: Devotion Aura |
| 骑士冰霜抗性光环 | Paladin: Frost Resistance Aura |
| 骑士专注光环 | Paladin: Concentration Aura |
| 骑士暗影抗性光环 | Paladin: Shadow Resistance Aura |
| 骑士惩戒光环 | Paladin: Retribution Aura |
| 骑士火焰抗性光环 | Paladin: Fire Resistance Aura |
| 萨满石化武器 | Shaman: Rockbiter Weapon |
| 萨满火舌武器 | Shaman: Flametongue Weapon |
| 萨满冰封武器 | Shaman: Frostbrand Weapon |
| 萨满风怒武器 | Shaman: Windfury Weapon |

Other settings keys:

| Chinese | English |
| --- | --- |
| 需要召唤宠物 | Summon pet enabled |
| 宠物食物 | Pet food (item id) |

---

## 3. Code comments

| Chinese | English |
| --- | --- |
| 盗贼消失计时 | Rogue Vanish timer |
| 猎人陷阱计时 | Hunter trap timer |
| 猎人子弹 | Hunter ammo |
| 猎人宠物食物 | Hunter pet food |
| 盗贼毒药 | Rogue poison |
| 盗贼闪光粉 | Rogue flash powder |
| 判断角色是否死亡 | Check whether the character is dead |
| 角色死亡，用寻路call跑尸体 | Character died — corpse run via pathfinding |
| 判断血蓝吃喝 | Decide whether to eat / drink |

---

## 4. Runtime messages

The source is bilingual already via `Check_UI(chinese, english)`; these are the
few where only the Chinese side carries meaning, plus the `textout` strings.

| Chinese | English |
| --- | --- |
| < GUID > 黑名单 | `< GUID > added to blacklist` |
| 等待跑尸复活时间 = | `Waiting to release, seconds =` |
| 跑尸超过十分钟, 自动天使复活 = | `Corpse run exceeded 10 minutes — using Spirit Healer =` |
| 安全地点剩余距离 = | `Distance to safe point =` |
| 剩余距离 = | `Distance to corpse =` |
| 复活尸体 | `Retrieving corpse` |
| 更换安全地点复活 | `Relocating to a safe resurrection point` |
| 附近8码有敌人, 不宜复活 | `Enemies within 8 yards — unsafe to resurrect` |
| 使用回血... | `Restoring health...` |
| 使用回血物品 = | `Eating food =` |
| 回蓝中... | `Restoring mana...` |
| 使用回蓝物品 = | `Drinking =` |
| 回血中... | `Restoring health...` |
| 尝试召唤宠物... | `Summoning pet...` |
| 复活宠物中... | `Reviving pet...` |
| 宠物死亡, 复活宠物中... | `Pet died — reviving...` |
| 治疗宠物中... | `Mending pet...` |
| 喂养宠物... | `Feeding pet...` |
| 上毒 - | `Applying poison -` |
| 武器增强 - | `Weapon enhancement -` |

---

## 5. Legacy `Easy_Data` config keys → GUI keys

This table used to live in `config.lua` as `config.KEY_MAP`. It mapped the
original bot's Chinese `Easy_Data` setting names onto this project's GUI keys.
Nothing ever read it — `config.lua` is required by no module, and `Easy_Data`
appears nowhere in this codebase — so it was moved here rather than left as
Chinese string data in shipping code. The `mfg_*` targets are real and live in
`gui.lua`.

Keep this if legacy Chinese config files ever need importing; the Chinese side
is the lookup key and cannot be translated away without breaking that.

| Chinese key | Meaning | GUI key |
| --- | --- | --- |
| 传送检测 | Teleport detection | `mfg_teleport` |
| 传送距离 | Teleport distance | `mfg_teleport_yards` |
| 需要吃喝 | Eat / drink enabled | `mfg_eat_drink` |
| 回血百分比 | Eat below health % | `mfg_eat_hp` |
| 回蓝百分比 | Drink below mana % | `mfg_drink_mana` |
| 使用药水 | Use potions | `mfg_potions` |
| 回血药水百分比 | Health potion below % | `mfg_hp_pot` |
| 回蓝药水百分比 | Mana potion below % | `mfg_mp_pot` |
| 随机路径 | Randomise path | `mfg_random_path` |
| 最大击杀时间 | Max time per kill | `mfg_max_kill` |
| 巡逻反击 | Fight back while patrolling | `mfg_fight_back` |
| 反击百分比 | Fight back below health % | `mfg_fight_back_hp` |
| 采集反击范围 | Fight-back range while gathering | `mfg_fight_back_yards` |
| 玩家检测 | Player detection | `mfg_player_detect` |
| 玩家检测距离 | Player detection distance | `mfg_player_yards` |
| 只击杀无目标怪物 | Only kill untapped mobs | `mfg_untapped` |
| 需要拾取 | Looting enabled | `mfg_loot` |
| 只拾取我击杀 | Only loot my own kills | `mfg_loot_mine` |
| 需要卖物 | Vendor selling enabled | `mfg_vendor_sell` |
| 需要修理 | Repair enabled | `mfg_repair` |
| 灰色 | Sell grey quality | `mfg_sell_grey` |
| 白色 | Sell white quality | `mfg_sell_white` |
| 绿色 | Sell green quality | `mfg_sell_green` |
| 卖物格数 | Free bag slots before a vendor trip | `mfg_bag_free` |
| 修理耐久度 | Repair below durability % | `mfg_repair_pct` |
| 法师Ice Barrier | Mage: Ice Barrier | `mfg_ice_barrier` |
| 法师Mana Sheild | Mage: Mana Shield *(typo in source)* | `mfg_mana_shield` |
| 法师Ice Armor | Mage: Ice Armor | `mfg_ice_armor` |
| Mage Armor | Mage: Mage Armor *(already English)* | `mfg_mage_armor` |
| 法师Molten Armor | Mage: Molten Armor | `mfg_molten_armor` |
| 法师烈焰风暴 | Mage: Flamestrike | `mfg_flamestrike` |
| 法师暴风雪 | Mage: Blizzard | `mfg_blizzard` |
| 法师召唤水元素 | Mage: Summon Water Elemental | `mfg_water_ele` |
| 法师冰枪术 | Mage: Ice Lance | `mfg_ice_lance` |
| 法师冰锥术 | Mage: Cone of Cold | `mfg_cone` |
| 法师炎爆术 | Mage: Pyroblast | `mfg_pyroblast` |
| 法师龙息术 | Mage: Dragon's Breath | `mfg_dragons_breath` |
| 法师冲击波 | Mage: Blast Wave | `mfg_blast_wave` |
| 法师寒冰箭 | Mage: Frostbolt | `mfg_frostbolt` |
| 法师灼烧 | Mage: Scorch | `mfg_scorch` |
| 法师奥术飞弹 | Mage: Arcane Missiles | `mfg_arcane_missiles` |
| 法师火球术 | Mage: Fireball | `mfg_fireball` |

---

## 6. Note on the two "Mage Armor" collisions

The source has three distinct keys that all translate loosely to "armor spell",
and they are **not** interchangeable:

- `法师魔甲术` — Mage Armor (Mage)
- `术士魔甲术` — Demon Armor (Warlock)
- `邪甲术` — Fel Armor (Warlock, TBC, replaces Demon Armor)

The literal characters 魔甲术 appear in both the Mage and Warlock keys, prefixed
by the class name. Translating the prefix away would silently merge two
different spells, so the class prefix is load-bearing — keep it.
