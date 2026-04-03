--[[ Imported by: Main ]]
-- Crit Manager menu rendering and keybind UI handling.

local TimMenu = require("TimMenu")

local MenuUI = {}

local activationModes = { "Always", "Hold", "Toggle" }
local storageModes = { "Shots", "Percent" }

local function ensureKeybindTable(bind)
    if type(bind) == "table" then
        bind.key = bind.key or 0
        bind.mode = bind.mode or 1
        return bind
    end
    return { key = 0, mode = 1 }
end

local function renderSlotSettings(menu, slotName)
    local slot = menu.Slots[slotName]
    assert(slot, "renderSlotSettings: slot config missing")

    if slot.StorageMode == nil then
        slot.StorageMode = 1
    end
    if slot.MinStorageValue == nil then
        slot.MinStorageValue = slot.MinStoredShots or 0
    end
    if slot.ChanceModifierPercent == nil then
        slot.ChanceModifierPercent = 100
    end
    if slot.UseProbabilityModifier == nil then
        slot.UseProbabilityModifier = false
    end

    TimMenu.BeginSector(slotName)
    slot.StorageMode = TimMenu.Selector("Storage Mode", slot.StorageMode or 1, storageModes)
    TimMenu.NextLine()
    if slot.StorageMode == 2 then
        slot.MinStorageValue = TimMenu.Slider("Min Stored Crits (%)", slot.MinStorageValue or 0, 0, 100, 1)
    else
        slot.MinStorageValue = TimMenu.Slider("Min Stored Crits (shots)", slot.MinStorageValue or 0, 0, 25, 1)
    end
    TimMenu.NextLine()
    slot.UseProbabilityModifier = TimMenu.Checkbox("Enable Probability Modifier", slot.UseProbabilityModifier)
    TimMenu.NextLine()
    slot.ChanceModifierPercent = TimMenu.Slider("Manual Crit Chance (%)", slot.ChanceModifierPercent or 100, 0, 100, 1)
    TimMenu.NextLine()
    TimMenu.Text("Disabled = regular crit hack (always force on key hold)")
    TimMenu.NextLine()
    TimMenu.Text("Enabled = this percent is absolute manual crit use chance")
    TimMenu.NextLine()
    TimMenu.EndSector()
end

function MenuUI.Render(menu, runtimeState)
    assert(menu, "MenuUI.Render: menu is nil")

    if not (gui.IsMenuOpen() and TimMenu.Begin("Crit Manager")) then
        return
    end

    menu.CritHack = menu.CritHack or { Enabled = true, Keybind = { key = 0, mode = 1 } }
    menu.CritHack.Keybind = ensureKeybindTable(menu.CritHack.Keybind)
    menu.Slots = menu.Slots or {}
    menu.Slots.Primary = menu.Slots.Primary or
    { MinStoredShots = 0, ChanceModifierPercent = 100, UseProbabilityModifier = false }
    menu.Slots.Secondary = menu.Slots.Secondary or
    { MinStoredShots = 0, ChanceModifierPercent = 100, UseProbabilityModifier = false }
    menu.Slots.Melee = menu.Slots.Melee or
    { MinStoredShots = 0, ChanceModifierPercent = 100, UseProbabilityModifier = false }
    menu.Display = menu.Display or { Enabled = true, X = 10, Y = 350, ShowBucket = true, ShowChance = true }

    local tabs = menu.tabs or { "General", "Primary", "Secondary", "Melee", "Display" }
    menu.currentTab = TimMenu.TabControl("crit_manager_tabs", tabs, menu.currentTab or 1)
    TimMenu.NextLine()

    if menu.currentTab == "General" or menu.currentTab == 1 then
        TimMenu.BeginSector("General")
        menu.CritHack.Enabled = TimMenu.Checkbox("Enable Crit Hack", menu.CritHack.Enabled)
        TimMenu.NextLine()

        local bind = menu.CritHack.Keybind
        bind.key = TimMenu.Keybind("Manual Crit Key", bind.key or 0)
        TimMenu.NextLine()
        bind.mode = TimMenu.Selector("Manual Crit Key Mode", bind.mode or 1, activationModes)
        TimMenu.NextLine()
        TimMenu.Text("If key is None, RMB/IN_ATTACK2 acts as auto crit key")
        TimMenu.NextLine()
        TimMenu.Text("Key mode uses Lmaobox key input semantics.")
        TimMenu.NextLine()
        TimMenu.EndSector()
    end

    if menu.currentTab == "Primary" or menu.currentTab == 2 then
        renderSlotSettings(menu, "Primary")
    end

    if menu.currentTab == "Secondary" or menu.currentTab == 3 then
        renderSlotSettings(menu, "Secondary")
    end

    if menu.currentTab == "Melee" or menu.currentTab == 4 then
        renderSlotSettings(menu, "Melee")
    end

    if menu.currentTab == "Display" or menu.currentTab == 5 then
        TimMenu.BeginSector("Display")
        menu.Display.Enabled = TimMenu.Checkbox("Show Indicator", menu.Display.Enabled)
        TimMenu.NextLine()
        menu.Display.ShowBucket = TimMenu.Checkbox("Show Bucket Stats", menu.Display.ShowBucket)
        TimMenu.NextLine()
        menu.Display.ShowChance = TimMenu.Checkbox("Show Chance Stats", menu.Display.ShowChance)
        TimMenu.NextLine()
        TimMenu.Text("Drag the indicator while menu is open to reposition it")
        TimMenu.NextLine()

        if runtimeState and runtimeState.lastSlotName then
            TimMenu.Text(string.format("Current Slot: %s", runtimeState.lastSlotName))
            TimMenu.NextLine()
        end

        TimMenu.EndSector()
    end

    TimMenu.End()
end

return MenuUI
