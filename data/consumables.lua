-- ============================================================================
-- Master Farmer - Grindbot
-- Consumables — conjured + vendor food/water from Orca tables
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- Source: orca de.lua conjuredFood / food / conjuredDrinks / drinks / foodordrink
-- Highest rank / best restore first.
-- ============================================================================

local consumables = {}

-- Conjure Food spell IDs (rank 8 -> rank 1)
consumables.CONJURE_FOOD_SPELL_IDS = {
    33717, -- Rank 8
    28612, -- Rank 7
    10145, -- Rank 6
    10144, -- Rank 5
    6129,  -- Rank 4
    990,   -- Rank 3
    597,   -- Rank 2
    587,   -- Rank 1
}

-- Conjure Water spell IDs (rank 9 -> rank 1)
consumables.CONJURE_WATER_SPELL_IDS = {
    27090, -- Rank 9
    37420, -- Rank 8
    10140, -- Rank 7
    10139, -- Rank 6
    10138, -- Rank 5
    6127,  -- Rank 4
    5506,  -- Rank 3
    5505,  -- Rank 2
    5504,  -- Rank 1
}

-- Conjured food item IDs (highest first)
consumables.CONJURED_FOOD_ITEM_IDS = {
    22019, -- Conjured Croissant
    34062, -- Conjured Manna Biscuit
    22895, -- Conjured Cinnamon Roll
    8076,  -- Conjured Sweet Roll
    8075,  -- Conjured Sourdough
    1487,  -- Conjured Pumpernickel
    1114,  -- Conjured Rye
    1113,  -- Conjured Bread
    5349,  -- Conjured Muffin
}

-- Conjured water item IDs (highest first)
consumables.CONJURED_WATER_ITEM_IDS = {
    22018, -- Conjured Glacier Water
    30703, -- Conjured Mountain Spring Water
    8079,  -- Conjured Crystal Water
    8078,  -- Conjured Sparkling Water
    8077,  -- Conjured Mineral Water
    3772,  -- Conjured Spring Water
    2136,  -- Conjured Purified Water
    2288,  -- Conjured Fresh Water
    5350,  -- Conjured Water
}

-- Dual-purpose (food + drink)
consumables.MANNA_ITEM_IDS = {
    34062, -- Conjured Manna Biscuit
    19301, -- Alterac Manna Biscuit
    13724, -- Enriched Manna Biscuit
    34780, -- Naaru Ration
}

-- Vendor / drop water and juice (not alcohol)
consumables.VENDOR_WATER_ITEM_IDS = {
    28399, -- Filtered Draenic Water
    27860, -- Purified Draenic Water
    38431, -- Blackrock Fortified Water
    38430, -- Blackrock Mineral Water
    38429, -- Blackrock Spring Water
    32453, -- Star's Tears
    32455, -- Star's Lament
    32722, -- Enriched Terocone Juice
    30457, -- Gilneas Sparkling Water
    19300, -- Bottled Winterspring Water
    18300, -- Hyjal Nectar
    8766,  -- Morning Glory Dew
    1645,  -- Moonberry Juice
    1708,  -- Sweet Nectar
    1205,  -- Melon Juice
    4791,  -- Enchanted Water
    9451,  -- Bubbling Water
    33042, -- Black Coffee
    1179,  -- Ice Cold Milk
    159,   -- Refreshing Spring Water
}

-- Vendor / cooked / drop food (not alcohol, not pet feed)
consumables.VENDOR_FOOD_ITEM_IDS = {
    35565, 32721, 33052, 33053, 33048, 33872, 33866, 33867, 33825, 32686, 32685,
    31673, 31672, 30816, 30610, 30458, 30361, 30359, 30358, 30357, 30355, 30155,
    29453, 29452, 29451, 29450, 29449, 29448, 29412, 29394, 29393, 29293, 29292,
    28501, 28486, 28112, 27859, 27858, 27857, 27856, 27855, 27854, 27667, 27666,
    27665, 27664, 27663, 27662, 27661, 27660, 27659, 27658, 27657, 27656, 27655,
    27651, 24539, 24338, 24105, 24072, 24009, 24008, 23756, 23495, 23172, 23160,
    22645, 22324, 21552, 21254, 21240, 21236, 21235, 21217, 21215, 21072, 21033,
    21031, 21030, 21023, 20857, 20516, 20452, 20074, 20031, 19996, 19995, 19994,
    19696, 19306, 19305, 19304, 19301, 19225, 19224, 19223, 18635, 18633, 18632,
    18255, 18254, 18045, 17408, 17407, 17406, 17344, 17222, 17197, 17119, 16971,
    16766, 16171, 16170, 16169, 16168, 16167, 16166, 13935, 13934, 13933, 13932,
    13931, 13930, 13929, 13928, 13927, 13893, 13851, 13810, 13755, 13724, 13546,
    12763, 12238, 12224, 12218, 12217, 12216, 12215, 12214, 12213, 12212, 12211,
    12210, 12209, 11951, 11584, 11444, 11415, 9681, 8957, 8953, 8952, 8950, 8948,
    8932, 8364, 7808, 7807, 7806, 733, 724, 7228, 7097, 6890, 6888, 6887, 6807,
    6657, 6522, 6316, 6299, 6290, 6038, 5527, 5526, 5525, 5480, 5479, 5478, 5477,
    5476, 5474, 5473, 5472, 5095, 5066, 4656, 4608, 4607, 4606, 4605, 4604, 4602,
    4601, 4599, 4593, 4592, 4544, 4542, 4541, 4540, 4539, 4538, 4537, 4536, 4457,
    422, 414, 3927, 3771, 3770, 3729, 3728, 3727, 3726, 3666, 3665, 3664, 3663,
    3662, 35710, 3448, 33924, 33004, 3220, 30816, 2888, 2687, 2685, 2684, 2683,
    2682, 2681, 2680, 2679, 23495, 2287, 2070, 1707, 1326, 117, 1082, 1017, 787,
}

local function merge_unique(lists)
    local seen = {}
    local out = {}
    for i = 1, #lists do
        local list = lists[i]
        if type(list) == "table" then
            for j = 1, #list do
                local id = list[j]
                if type(id) == "number" and id > 0 and not seen[id] then
                    seen[id] = true
                    out[#out + 1] = id
                end
            end
        end
    end
    return out
end

consumables.FOOD_ITEM_IDS = merge_unique({
    consumables.CONJURED_FOOD_ITEM_IDS,
    consumables.MANNA_ITEM_IDS,
    consumables.VENDOR_FOOD_ITEM_IDS,
})

consumables.WATER_ITEM_IDS = merge_unique({
    consumables.CONJURED_WATER_ITEM_IDS,
    consumables.MANNA_ITEM_IDS,
    consumables.VENDOR_WATER_ITEM_IDS,
})

-- Eat / drink buff spell IDs (not item IDs)
consumables.FOOD_AURA_IDS = {
    434, 435, 5004, 5005, 5006, 5007,
    10256, 10257, 18229, 18230, 18231, 18233, 18234,
    22731, 24869, 25660, 26401, 27094, 28616,
    33252, 33253, 33254, 33257, 33259, 33261, 33263, 33265, 33268,
    33725, 35270, 35271, 40768, 42293, 43763, 45618, 46683, 46899,
}

consumables.DRINK_AURA_IDS = {
    430, 431, 432, 433,
    1133, 1135, 1137,
    10250, 22734, 27089, 34291, 43182, 43183,
    43706, 46755,
}

return consumables
