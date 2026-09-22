-- ============================================================================
-- Master Farmer - Grindbot
-- Config accessors + KEY_MAP from Easy_Data Chinese keys (grind-core only)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- ============================================================================

local gui = require("gui")

local config = {}

config.KEY_MAP = {
    ["传送检测"] = "mfg_teleport",
    ["传送距离"] = "mfg_teleport_yards",
    ["需要吃喝"] = "mfg_eat_drink",
    ["回血百分比"] = "mfg_eat_hp",
    ["回蓝百分比"] = "mfg_drink_mana",
    ["使用药水"] = "mfg_potions",
    ["回血药水百分比"] = "mfg_hp_pot",
    ["回蓝药水百分比"] = "mfg_mp_pot",
    ["随机路径"] = "mfg_random_path",
    ["最大击杀时间"] = "mfg_max_kill",
    ["巡逻反击"] = "mfg_fight_back",
    ["反击百分比"] = "mfg_fight_back_hp",
    ["采集反击范围"] = "mfg_fight_back_yards",
    ["玩家检测"] = "mfg_player_detect",
    ["玩家检测距离"] = "mfg_player_yards",
    ["只击杀无目标怪物"] = "mfg_untapped",
    ["需要拾取"] = "mfg_loot",
    ["只拾取我击杀"] = "mfg_loot_mine",
    ["需要卖物"] = "mfg_vendor_sell",
    ["需要修理"] = "mfg_repair",
    ["灰色"] = "mfg_sell_grey",
    ["白色"] = "mfg_sell_white",
    ["绿色"] = "mfg_sell_green",
    ["卖物格数"] = "mfg_bag_free",
    ["修理耐久度"] = "mfg_repair_pct",
    ["法师Ice Barrier"] = "mfg_ice_barrier",
    ["法师Mana Sheild"] = "mfg_mana_shield",
    ["法师Ice Armor"] = "mfg_ice_armor",
    ["Mage Armor"] = "mfg_mage_armor",
    ["法师Molten Armor"] = "mfg_molten_armor",
    ["法师烈焰风暴"] = "mfg_flamestrike",
    ["法师暴风雪"] = "mfg_blizzard",
    ["法师召唤水元素"] = "mfg_water_ele",
    ["法师冰枪术"] = "mfg_ice_lance",
    ["法师冰锥术"] = "mfg_cone",
    ["法师炎爆术"] = "mfg_pyroblast",
    ["法师龙息术"] = "mfg_dragons_breath",
    ["法师冲击波"] = "mfg_blast_wave",
    ["法师寒冰箭"] = "mfg_frostbolt",
    ["法师灼烧"] = "mfg_scorch",
    ["法师奥术飞弹"] = "mfg_arcane_missiles",
    ["法师火球术"] = "mfg_fireball",
}

function config.is_on(key)
    return gui.is_on(key)
end

function config.slider(key, fallback)
    return gui.slider(key, fallback)
end

function config.mode()
    return gui.mode()
end

return config
