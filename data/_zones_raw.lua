-- Compatibility shim. Grind loads one race via grind/zones/<race>.
return {
    troll = require("grind/zones/troll"),
    undead = require("grind/zones/undead"),
    gnome = require("grind/zones/gnome"),
    human = require("grind/zones/human"),
}
