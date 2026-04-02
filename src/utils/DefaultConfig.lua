--[[ Imported by: Main ]]
-- Default config for Crit Manager.

local DefaultConfig = {}

DefaultConfig.Menu = {
    currentTab = 1,
    tabs = { "General", "Primary", "Secondary", "Melee", "Display" },

    CritHack = {
        Enabled = true,
        -- mode: 1 = Always, 2 = Hold, 3 = Toggle
        Keybind = { key = 0, mode = 2 },
    },

    Slots = {
        Primary = {
            MinStoredShots = 0,
            ChanceModifierPercent = 100,
        },
        Secondary = {
            MinStoredShots = 0,
            ChanceModifierPercent = 100,
        },
        Melee = {
            MinStoredShots = 0,
            ChanceModifierPercent = 100,
        },
    },

    Display = {
        Enabled = true,
        X = 10,
        Y = 350,
        ShowBucket = true,
        ShowChance = true,
    },
}

return DefaultConfig
