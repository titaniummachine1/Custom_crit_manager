--[[ Crit Manager ]]
-- Modular entry for crit storage and crit chance control.

local MenuUI = require("Menu")
local Config = require("utils.Config")
local DefaultConfig = require("utils.DefaultConfig")

local SCRIPT_CONFIG_NAME = "Crit_manager"

local IN_ATTACK_CONST = IN_ATTACK or 1
local IN_ATTACK2_CONST = IN_ATTACK2 or 2
local TF2_SPY_CLASS = TF2_Spy or 8
local MIN_TICKS = 1
local MAX_TICKS = 23

local colors = {
    white = { 255, 255, 255, 255 },
    gray = { 190, 190, 190, 255 },
    red = { 255, 0, 0, 255 },
    green = { 36, 255, 122, 255 },
    blue = { 30, 139, 195, 255 },
    yellow = { 255, 255, 0, 255 },
    darkRed = { 97, 97, 76, 255 },
    flashRed = { 255, 150, 150, 255 },
}

local hardcoded_weapon_ids = {}
local hardcoded_list = {
    441, 416, 40, 594, 595, 813, 834, 141, 1004, 142, 232, 61, 1006, 525, 132, 1082, 266, 482, 327, 307, 357,
    404, 812, 833, 237, 265, 155, 230, 460, 1178, 14, 201, 56, 230, 402, 526, 664, 752, 792, 801, 851, 881,
    890, 899, 908, 957, 966, 1005, 1092, 1098, 15000, 15007, 15019, 15023, 15033, 15059, 15070, 15071, 15072,
    15111, 15112, 15135, 15136, 15154, 30665, 194, 225, 356, 461, 574, 638, 649, 665, 727, 794, 803, 883, 892,
    901, 910, 959, 968, 15062, 15094, 15095, 15096, 15118, 15119, 15143, 15144, 131, 406, 1099, 1144, 46, 42,
    311, 863, 1002, 159, 433, 1190, 129, 226, 354, 1001, 1101, 1179, 642, 133, 444, 405, 608, 57, 231, 29,
    211, 35, 411, 663, 796, 805, 885, 894, 903, 912, 961, 970, 998, 15008, 15010, 15025, 15039, 15050, 15078,
    15097, 15121, 15122, 15123, 15145, 15146, 30, 212, 59, 60, 297, 947, 735, 736, 810, 831, 933, 1080, 1102,
    140, 1086, 30668, 25, 737, 26, 28, 222, 1121, 1180, 58, 1083, 1105,
}

for i = 1, #hardcoded_list do
    hardcoded_weapon_ids[hardcoded_list[i]] = true
end

local menuSettings = Config.LoadCFG(DefaultConfig.Menu, SCRIPT_CONFIG_NAME)
local fontId = draw.CreateFont("Smallest Pixel", 11, 400, FONTFLAG_OUTLINE, 1)

local keyRuntime = {
    wasDown = false,
    toggledOn = false,
}

local runtime = {
    lastSlotName = "Primary",
    svAllowCrit = false,
    isCritBoosted = false,
    storedCrits = 0,
    minStoredShots = 0,
    usableCrits = 0,
    bucketCurrent = 0,
    bucketMax = 0,
    shotsUntilFull = 0,
    baseCritChance = 0,
    modifiedCritChance = 0,
    observedCritChance = 0,
    requiredDamage = 0,
    manualKeyActive = false,
    manualDecision = "idle",
    slotModifierPrimary = 100,
    slotModifierSecondary = 100,
    slotModifierMelee = 100,
    critCostNow = 0,
    bucketAfterForce = 0,
    bucketSpentPct = 0,
    shotsNeededForTokens = 0,
    weaponBaseDamage = 0,
}

local weaponInfoCache = {}

local function getCenterPos(textWidth)
    local screenWidth = draw.GetScreenSize()
    return math.floor((screenWidth / 2) - (textWidth / 2))
end

local function drawBar(x, y, w, h, value, maxValue, color)
    local safeMax = maxValue
    if safeMax <= 0 then
        safeMax = 1
    end

    local clampedValue = value
    if clampedValue < 0 then
        clampedValue = 0
    elseif clampedValue > safeMax then
        clampedValue = safeMax
    end

    local fill = math.floor((clampedValue / safeMax) * w)
    draw.Color(40, 40, 40, 200)
    draw.FilledRect(x, y, x + w, y + h)
    draw.Color(color[1], color[2], color[3], color[4])
    draw.FilledRect(x, y, x + fill, y + h)
    draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    draw.OutlinedRect(x, y, x + w, y + h)
    return y + h + 5
end

local function ensureMenuDefaults()
    if type(menuSettings) ~= "table" then
        menuSettings = Config.LoadCFG(DefaultConfig.Menu, SCRIPT_CONFIG_NAME)
        return
    end

    if type(menuSettings.CritHack) ~= "table" then
        menuSettings.CritHack = { Enabled = true, Keybind = { key = 0, mode = 2 } }
    end
    if type(menuSettings.CritHack.Keybind) ~= "table" then
        menuSettings.CritHack.Keybind = { key = 0, mode = 2 }
    end
    if menuSettings.CritHack.Keybind.mode == nil then
        menuSettings.CritHack.Keybind.mode = 2
    end

    if type(menuSettings.Slots) ~= "table" then
        menuSettings.Slots = {}
    end
    if type(menuSettings.Slots.Primary) ~= "table" then
        menuSettings.Slots.Primary = { MinStoredShots = 0, ChanceModifierPercent = 100 }
    end
    if type(menuSettings.Slots.Secondary) ~= "table" then
        menuSettings.Slots.Secondary = { MinStoredShots = 0, ChanceModifierPercent = 100 }
    end
    if type(menuSettings.Slots.Melee) ~= "table" then
        menuSettings.Slots.Melee = { MinStoredShots = 0, ChanceModifierPercent = 100 }
    end

    if type(menuSettings.Display) ~= "table" then
        menuSettings.Display = { Enabled = true, X = 10, Y = 350, ShowBucket = true, ShowChance = true }
    end
end

local function canFireCriticalShot(localPlayer, weapon)
    assert(localPlayer, "canFireCriticalShot: localPlayer missing")
    assert(weapon, "canFireCriticalShot: weapon missing")

    if localPlayer:GetPropInt("m_iClass") == TF2_SPY_CLASS and weapon:IsMeleeWeapon() then
        return false
    end

    local className = weapon:GetClass()
    if className == "CTFSniperRifle" or className == "CTFBuffItem" or className == "CTFWeaponLunchBox" then
        return false
    end

    if hardcoded_weapon_ids[weapon:GetPropInt("m_iItemDefinitionIndex")] then
        return false
    end

    if weapon:GetCritChance() <= 0 then
        return false
    end

    if weapon:GetWeaponBaseDamage() <= 0 then
        return false
    end

    return true
end

local function getSlotName(weapon)
    if weapon:IsMeleeWeapon() then
        return "Melee"
    end

    local slot = -1
    local okGetSlot, slotValue = pcall(function()
        return weapon:GetSlot()
    end)
    if okGetSlot and type(slotValue) == "number" then
        slot = slotValue
    else
        local okLoadoutSlot, loadoutSlotValue = pcall(function()
            return weapon:GetLoadoutSlot()
        end)
        if okLoadoutSlot and type(loadoutSlotValue) == "number" then
            slot = loadoutSlotValue
        end
    end

    if slot == 1 then
        return "Secondary"
    end
    if slot == 2 then
        return "Melee"
    end

    return "Primary"
end

local function getSlotSettings(slotName)
    local slots = menuSettings.Slots
    local slotCfg = slots[slotName]
    if slotCfg == nil then
        slotCfg = { MinStoredShots = 0, ChanceModifierPercent = 100 }
        slots[slotName] = slotCfg
    end
    return slotCfg
end

local function isKeybindActive(bind)
    if type(bind) ~= "table" then
        return false
    end

    local key = bind.key or 0
    local mode = bind.mode or 2

    if mode == 1 then
        return true
    end

    if key == 0 then
        return false
    end

    local isDown = input.IsButtonDown(key)
    local pressed = isDown and not keyRuntime.wasDown

    if mode == 2 then
        keyRuntime.wasDown = isDown
        return isDown
    end

    if mode == 3 and pressed then
        keyRuntime.toggledOn = not keyRuntime.toggledOn
    end

    keyRuntime.wasDown = isDown
    return keyRuntime.toggledOn
end

local function calcWeaponInfo(weapon)
    assert(weapon, "calcWeaponInfo: weapon missing")

    local weaponIndex = weapon:GetIndex()
    local critCheckCount = weapon:GetCritCheckCount()
    local cached = weaponInfoCache[weaponIndex]
    if cached and cached.critCheckCount == critCheckCount then
        return cached
    end

    local weaponData = weapon:GetWeaponData() or {}
    local info = setmetatable({}, { __index = weaponData })
    info.currentWeapon = weaponIndex
    info.critCheckCount = critCheckCount
    info.critRequestCount = weapon:GetCritSeedRequestCount() or 0
    info.isRapidFire = info.useRapidFireCrits or weapon:GetClass() == "CTFMinigun"
    info.addedPerShot = weapon:GetWeaponBaseDamage() or 1
    if info.addedPerShot <= 0 then
        info.addedPerShot = 1
    end

    info.bucketCurrent = weapon:GetCritTokenBucket() or 0
    info.bucketMax = client.GetConVar("tf_weapon_criticals_bucket_cap") or 1000
    info.bucketMin = client.GetConVar("tf_weapon_criticals_bucket_bottom") or 0
    info.shotsToFill = info.bucketMax / info.addedPerShot
    info.storedCrits = 0
    info.shotsUntilFull = 0
    info.costs = {}

    local temp = info.bucketMin
    local tempSpend = info.bucketCurrent
    local tempFill = info.bucketCurrent

    if weapon:IsMeleeWeapon() then
        local critCost = weapon:GetCritCost(temp, info.critRequestCount, info.critCheckCount)
        while tempSpend > critCost do
            info.storedCrits = info.storedCrits + 1
            critCost = critCost +
                weapon:GetCritCost(critCost, info.critRequestCount + info.storedCrits, info.critCheckCount)

            if tempFill < info.bucketMax then
                tempFill = math.min(tempFill + info.addedPerShot, info.bucketMax)
                info.shotsUntilFull = info.shotsUntilFull + 1
            end

            local nextBreak = critCost +
                weapon:GetCritCost(critCost, info.critRequestCount + info.storedCrits + 1, info.critCheckCount) +
                info.addedPerShot - info.shotsToFill
            if nextBreak > info.bucketMax then
                break
            end
        end
    else
        for i = 0, info.shotsToFill + 1, 1 do
            if temp < info.bucketMax then
                temp = math.min(temp + info.addedPerShot, info.bucketMax)
                info.costs[i] = weapon:GetCritCost(temp, info.critRequestCount + i, info.critCheckCount)
            end

            if tempSpend >= info.costs[i] then
                tempSpend = tempSpend - info.costs[i]
                info.storedCrits = info.storedCrits + 1
            end

            if tempFill < info.bucketMax then
                tempFill = math.min(tempFill + info.addedPerShot, info.bucketMax)
                info.shotsUntilFull = info.shotsUntilFull + 1
            end
        end
    end

    weaponInfoCache[weaponIndex] = info
    return info
end

local function applyCritLogic(pCmd, localPlayer, weapon)
    assert(pCmd, "applyCritLogic: pCmd missing")
    assert(localPlayer, "applyCritLogic: localPlayer missing")
    assert(weapon, "applyCritLogic: weapon missing")

    local info = calcWeaponInfo(weapon)
    local slotName = getSlotName(weapon)
    local slotSettings = getSlotSettings(slotName)

    local baseChance = weapon:GetCritChance() or 0
    if info.isRapidFire then
        baseChance = 0.0102
    end

    local modifierPct = slotSettings.ChanceModifierPercent or 100
    local modifiedChance = baseChance * (modifierPct / 100)
    local observedChance = weapon:CalcObservedCritChance() or 0

    local damageStats = weapon:GetWeaponDamageStats() or {}
    local criticalDamage = damageStats["critical"] or 0
    local totalDamage = damageStats["total"] or 0

    local cmpCritChance = baseChance + 0.1
    local requiredDamage = 0
    if cmpCritChance > 0 then
        local requiredTotalDamage = (criticalDamage * (2.0 * cmpCritChance + 1.0)) / cmpCritChance / 3.0
        requiredDamage = requiredTotalDamage - totalDamage
    end

    local minStoredShots = slotSettings.MinStoredShots or 0
    local storedCrits = info.storedCrits or 0
    local usableCrits = math.max(0, storedCrits - minStoredShots)

    local manualActive = false
    local manualDecision = "idle"
    if menuSettings.CritHack.Enabled then
        manualActive = isKeybindActive(menuSettings.CritHack.Keybind)
    end

    local attackPressed = (pCmd:GetButtons() & IN_ATTACK_CONST) ~= 0
    if manualActive and attackPressed then
        if usableCrits <= 0 then
            pCmd:SetButtons(pCmd:GetButtons() & (~IN_ATTACK2_CONST))
            manualDecision = "blocked (minimum storage)"
        else
            local decisionChance = 1.0
            if baseChance > 0 then
                decisionChance = math.min(1.0, math.max(0.0, modifiedChance / baseChance))
            end

            if math.random() <= decisionChance then
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2_CONST)
                manualDecision = "allowed"
            else
                pCmd:SetButtons(pCmd:GetButtons() & (~IN_ATTACK2_CONST))
                manualDecision = "blocked (chance modifier)"
            end
        end
    end

    local svAllowCrit = weapon:CanRandomCrit()
    if weapon:IsMeleeWeapon() then
        local tfWeaponCriticalsMelee = client.GetConVar("tf_weapon_criticals_melee")
        svAllowCrit = (svAllowCrit and tfWeaponCriticalsMelee == 1) or (tfWeaponCriticalsMelee == 2)
    end

    runtime.lastSlotName = slotName
    runtime.svAllowCrit = svAllowCrit
    runtime.isCritBoosted = localPlayer:IsCritBoosted() or localPlayer:InCond(TFCond_CritCola)
    runtime.storedCrits = storedCrits
    runtime.minStoredShots = minStoredShots
    runtime.usableCrits = usableCrits
    runtime.bucketCurrent = info.bucketCurrent or 0
    runtime.bucketMax = info.bucketMax or 0
    runtime.shotsUntilFull = info.shotsUntilFull or 0
    runtime.baseCritChance = baseChance * 100
    runtime.modifiedCritChance = modifiedChance * 100
    runtime.observedCritChance = observedChance * 100
    runtime.requiredDamage = math.max(0, requiredDamage)
    runtime.manualKeyActive = manualActive
    runtime.manualDecision = manualDecision
    runtime.slotModifierPrimary = (menuSettings.Slots.Primary.ChanceModifierPercent or 100)
    runtime.slotModifierSecondary = (menuSettings.Slots.Secondary.ChanceModifierPercent or 100)
    runtime.slotModifierMelee = (menuSettings.Slots.Melee.ChanceModifierPercent or 100)

    local critCostNow = 0
    local okCritCost, critCostValue = pcall(function()
        return weapon:GetCritCost(info.bucketCurrent, info.critRequestCount, info.critCheckCount)
    end)
    if okCritCost and type(critCostValue) == "number" then
        critCostNow = critCostValue
    end

    local bucketAfterForce = (info.bucketCurrent or 0) - critCostNow
    if bucketAfterForce < 0 then
        bucketAfterForce = 0
    end

    local bucketSpentPct = 0
    if (info.bucketMax or 0) > 0 then
        bucketSpentPct = (critCostNow / info.bucketMax) * 100
    end

    local shotsNeededForTokens = 0
    if (info.bucketCurrent or 0) < critCostNow then
        local missingToken = critCostNow - (info.bucketCurrent or 0)
        shotsNeededForTokens = math.ceil(missingToken / math.max(1, info.addedPerShot or 1))
    end

    runtime.critCostNow = critCostNow
    runtime.bucketAfterForce = bucketAfterForce
    runtime.bucketSpentPct = bucketSpentPct
    runtime.shotsNeededForTokens = shotsNeededForTokens
    runtime.weaponBaseDamage = info.addedPerShot or 0
end

local function drawIndicator(localPlayer, weapon)
    if not menuSettings.Display.Enabled then
        return
    end

    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end

    if not localPlayer or not weapon then
        return
    end

    draw.SetFont(fontId)
    local baseX = math.floor(menuSettings.Display.X or 10)
    local y = math.floor(menuSettings.Display.Y or 350)

    local headerText = "CRIT MANAGER"
    local headerWidth = draw.GetTextSize(headerText)
    draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    draw.Text(getCenterPos(headerWidth), y, headerText)
    y = y + 15

    local chargedTicks = MIN_TICKS
    local isWarping = false
    local canDoubleTap = false
    if warp and warp.GetChargedTicks and warp.IsWarping and warp.CanDoubleTap then
        chargedTicks = math.max(MIN_TICKS, math.min(warp.GetChargedTicks(), MAX_TICKS))
        isWarping = warp.IsWarping()
        canDoubleTap = warp.CanDoubleTap(weapon)
    end

    local dtColor = canDoubleTap and colors.green or colors.darkRed
    y = drawBar(baseX, y, 150, 12, chargedTicks, MAX_TICKS, dtColor)

    local statusText = string.format("%d/%d TICKS", chargedTicks, MAX_TICKS)
    if isWarping then
        statusText = "WARPING!"
        draw.Color(colors.red[1], colors.red[2], colors.red[3], colors.red[4])
    elseif canDoubleTap then
        statusText = "DT READY!"
        draw.Color(colors.green[1], colors.green[2], colors.green[3], colors.green[4])
    else
        draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    end
    local statusWidth = draw.GetTextSize(statusText)
    draw.Text(getCenterPos(statusWidth), y - 17, statusText)

    local weaponText = "CRIT " .. (weapon:GetName() or "Unknown")
    local weaponWidth = draw.GetTextSize(weaponText)
    draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    draw.Text(getCenterPos(weaponWidth), y, weaponText)
    y = y + 15

    if menuSettings.Display.ShowBucket then
        y = drawBar(baseX, y, 150, 12, math.floor(runtime.bucketCurrent or 0),
            math.max(1, math.floor(runtime.bucketMax or 1000)),
            colors.blue)
        draw.Text(baseX + 45, y - 16,
            string.format("%.0f/%.0f", runtime.bucketCurrent or 0, runtime.bucketMax or 0))

        local reserveText = string.format("Stored:%d  Min:%d  Usable:%d", runtime.storedCrits or 0,
            runtime.minStoredShots or 0, runtime.usableCrits or 0)
        local reserveWidth = draw.GetTextSize(reserveText)
        draw.Text(getCenterPos(reserveWidth), y)
        y = y + 15

        local forceBarColor = colors.green
        if runtime.shotsNeededForTokens > 0 then
            forceBarColor = colors.red
        end
        y = drawBar(baseX, y, 150, 8, runtime.critCostNow or 0, math.max(1, math.floor(runtime.bucketMax or 1000)),
            forceBarColor)

        if runtime.shotsNeededForTokens > 0 then
            draw.Color(colors.red[1], colors.red[2], colors.red[3], colors.red[4])
            draw.Text(baseX, y - 15,
                string.format("Force cost %.0f (%.1f%%) | need %d shots", runtime.critCostNow or 0,
                    runtime.bucketSpentPct or 0, runtime.shotsNeededForTokens or 0))
        else
            draw.Color(colors.green[1], colors.green[2], colors.green[3], colors.green[4])
            draw.Text(baseX, y - 15,
                string.format("Force cost %.0f (%.1f%%) | post-bucket %.0f", runtime.critCostNow or 0,
                    runtime.bucketSpentPct or 0, runtime.bucketAfterForce or 0))
        end
        y = y + 3
    end

    if menuSettings.Display.ShowChance then
        y = drawBar(baseX, y, 150, 12, runtime.modifiedCritChance or 0, 100, colors.yellow)
        draw.Text(baseX + 32, y - 16,
            string.format("Base %.1f%% | Mod %.1f%%", runtime.baseCritChance or 0, runtime.modifiedCritChance or 0))

        local chanceText = string.format("Observed %.1f%% | Needed dmg %.0f", runtime.observedCritChance or 0,
            runtime.requiredDamage or 0)
        local chanceWidth = draw.GetTextSize(chanceText)
        draw.Text(getCenterPos(chanceWidth), y)
        y = y + 15
    end

    local decisionText = string.format("Manual: %s | %s", runtime.manualKeyActive and "ON" or "OFF",
        runtime.manualDecision or "idle")
    local decisionWidth = draw.GetTextSize(decisionText)
    draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    draw.Text(getCenterPos(decisionWidth), y)
    y = y + 20

    local seed = 0
    if weapon.GetCurrentCritSeed then
        seed = weapon:GetCurrentCritSeed() or 0
    end

    local seedText = string.format("Seed: %d", math.floor(seed))
    local seedWidth = draw.GetTextSize(seedText)
    local seedColor = colors.red
    if seed > 200 then
        seedColor = colors.yellow
    elseif seed > 100 then
        seedColor = colors.white
    end
    draw.Color(seedColor[1], seedColor[2], seedColor[3], seedColor[4])
    draw.Text(getCenterPos(seedWidth), y)
    y = y + 20

    if weapon.GetRapidFireCritTime then
        local rapidTime = weapon:GetRapidFireCritTime() or 0
        if rapidTime > 0 then
            local flashText = string.format("RAPID FIRE: %.1fs", rapidTime)
            local flashWidth = draw.GetTextSize(flashText)
            local flashColor = colors.flashRed
            if math.sin(globals.RealTime() * 10) > 0 then
                flashColor = colors.red
            end
            draw.Color(flashColor[1], flashColor[2], flashColor[3], flashColor[4])
            draw.Text(getCenterPos(flashWidth), y, flashText)
        end
    end
end

local function onCreateMove(pCmd)
    ensureMenuDefaults()

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or not localPlayer:IsAlive() then
        runtime.manualDecision = "idle"
        return
    end

    local weapon = localPlayer:GetPropEntity("m_hActiveWeapon")
    if not weapon or not weapon:IsWeapon() then
        runtime.manualDecision = "idle"
        return
    end

    if not canFireCriticalShot(localPlayer, weapon) then
        runtime.manualDecision = "not eligible"
        return
    end

    applyCritLogic(pCmd, localPlayer, weapon)
end

local function onDraw()
    ensureMenuDefaults()
    local localPlayer = entities.GetLocalPlayer()
    local weapon = nil
    if localPlayer and localPlayer:IsAlive() then
        weapon = localPlayer:GetPropEntity("m_hActiveWeapon")
    end

    MenuUI.Render(menuSettings, runtime)
    drawIndicator(localPlayer, weapon)
end

local function onUnload()
    Config.CreateCFG(menuSettings, SCRIPT_CONFIG_NAME)
end

callbacks.Unregister("CreateMove", "CritManager_CreateMove")
callbacks.Unregister("Draw", "CritManager_Draw")
callbacks.Unregister("Unload", "CritManager_Unload")

callbacks.Register("CreateMove", "CritManager_CreateMove", onCreateMove)
callbacks.Register("Draw", "CritManager_Draw", onDraw)
callbacks.Register("Unload", "CritManager_Unload", onUnload)

printc(100, 255, 200, 255, "[Crit Manager] Loaded")
