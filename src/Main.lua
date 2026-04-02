--[[ Crit Manager ]]
-- Modular entry for crit storage and crit chance control.

local MenuUI = require("Menu")
local Config = require("utils.Config")
local DefaultConfig = require("utils.DefaultConfig")

local SCRIPT_CONFIG_NAME = "Crit_manager"

local IN_ATTACK_CONST = IN_ATTACK or 1
local IN_ATTACK2_CONST = IN_ATTACK2 or 2
local TF2_SPY_CLASS = TF2_Spy or 8

local colors = {
    white = { 255, 255, 255, 255 },
    gray = { 190, 190, 190, 255 },
    red = { 255, 0, 0, 255 },
    green = { 36, 255, 122, 255 },
    blue = { 30, 139, 195, 255 },
    yellow = { 255, 255, 0, 255 },
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

local dragRuntime = {
    active = false,
    wasMouseDown = false,
    offsetX = 0,
    offsetY = 0,
    initializedPos = false,
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
    critBanThreshold = 0,
    critBanned = false,
    critBanDamageCurrent = 0,
    critBanDamageGoal = 0,
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
    weaponDisplayName = "Unknown",
    serverAllowCrit = false,
    rapidFireWeapon = false,
    critCapPercent = 0,
    prevCanCritNow = false,
    readyTransitionActive = false,
    readyTransitionStart = 0,
    readyTransitionEnd = 0,
    readyTransitionFrom = 0,
    readyTransitionPhase = 0,
    readyTransitionTarget = 0,
}

local weaponInfoCache = {}
local weaponNameCache = {}

local function getNowTime()
    local okRealTime, realTime = pcall(function()
        return globals.RealTime()
    end)
    if okRealTime and type(realTime) == "number" then
        return realTime
    end
    return os.clock()
end

local function getWeaponName(any)
    if any == nil then
        return "Unknown"
    end

    if type(any) == "number" then
        if weaponNameCache[any] then
            return weaponNameCache[any]
        end

        local okItem, itemDef = pcall(function()
            return itemschema.GetItemDefinitionByID(any)
        end)
        if okItem and itemDef then
            local resolved = getWeaponName(itemDef)
            weaponNameCache[any] = resolved
            return resolved
        end

        return tostring(any)
    end

    local okMeta, meta = pcall(getmetatable, any)
    if not okMeta or type(meta) ~= "table" then
        return "Unknown"
    end

    if meta["__name"] == "Entity" then
        local okIsWeapon, isWeapon = pcall(function()
            return any:IsWeapon()
        end)
        if okIsWeapon and isWeapon then
            local okIndex, itemIndex = pcall(function()
                return any:GetPropInt("m_iItemDefinitionIndex")
            end)
            if okIndex and type(itemIndex) == "number" then
                return getWeaponName(itemIndex)
            end
        end
        return "Unknown"
    end

    if meta["__name"] == "ItemDefinition" then
        local okId, itemId = pcall(function()
            return any:GetID()
        end)
        if okId and weaponNameCache[itemId] then
            return weaponNameCache[itemId]
        end

        local special = tostring(any):match("TF_WEAPON_[%a%A]*")
        if special then
            local localized = client.Localize(special)
            if localized and localized:len() ~= 0 then
                if okId then weaponNameCache[itemId] = localized end
                return localized
            end

            local fallback = client.Localize(any:GetTypeName():gsub("_Type", ""))
            if okId then weaponNameCache[itemId] = fallback end
            return fallback
        end

        local okAttrs, attrs = pcall(function()
            return any:GetAttributes()
        end)
        if okAttrs and type(attrs) == "table" then
            for attrDef, _ in pairs(attrs) do
                local attrName = attrDef:GetName()
                if attrName == "paintkit_proto_def_index" or attrName == "limited quantity item" then
                    local fallback = client.Localize(any:GetTypeName():gsub("_Type", ""))
                    if okId then weaponNameCache[itemId] = fallback end
                    return fallback
                end
            end
        end

        local translated = tostring(any:GetNameTranslated())
        if okId then weaponNameCache[itemId] = translated end
        return translated
    end

    return "Unknown"
end

local function isRapidFireWeapon(weapon)
    return weapon:GetLastRapidFireCritCheckTime() > 0 or weapon:GetClass() == "CTFMinigun"
end

local function getCritCapPercent(baseChance)
    local chance = (baseChance or 0) + 0.1
    if chance < 0 then
        chance = 0
    elseif chance > 1 then
        chance = 1
    end
    return chance * 100
end

local function getCenterPos(textWidth)
    local screenWidth = draw.GetScreenSize()
    return math.floor((screenWidth / 2) - (textWidth / 2))
end

local function drawSegmentTicks(x, y, w, h, maxValue, segmentValue)
    local safeMax = maxValue
    if safeMax <= 0 then
        return
    end

    local safeSegment = segmentValue
    if safeSegment <= 0 then
        return
    end

    local segmentCount = math.floor(safeMax / safeSegment)
    if segmentCount <= 1 or segmentCount > 120 then
        return
    end

    for i = 1, segmentCount - 1 do
        local xPos = x + math.floor((i * safeSegment / safeMax) * w)
        local alpha = 38
        if (i % 5) == 0 then
            alpha = 78
        end

        draw.Color(255, 255, 255, alpha)
        draw.FilledRect(xPos, y + 1, xPos + 1, y + h - 1)
    end
end

local function drawBar(x, y, w, h, value, maxValue, color, segmentValue)
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
    drawSegmentTicks(x, y, w, h, safeMax, segmentValue or 0)
    draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    draw.OutlinedRect(x, y, x + w, y + h)
    return y + h + 5
end

local function drawForcePreviewBar(x, y, w, h, currentValue, costValue, maxValue, overlayAlpha)
    local safeMax = maxValue
    if safeMax <= 0 then
        safeMax = 1
    end

    local currentClamped = currentValue
    if currentClamped < 0 then
        currentClamped = 0
    elseif currentClamped > safeMax then
        currentClamped = safeMax
    end

    local costClamped = costValue
    if costClamped < 0 then
        costClamped = 0
    end

    local currentFill = math.floor((currentClamped / safeMax) * w)
    local greenStartValue = currentClamped - costClamped
    if greenStartValue < 0 then
        greenStartValue = 0
    end
    local greenStart = x + math.floor((greenStartValue / safeMax) * w)
    local greenEnd = x + math.floor((currentClamped / safeMax) * w)

    draw.Color(40, 40, 40, 200)
    draw.FilledRect(x, y, x + w, y + h)

    -- Base: current bucket in red.
    draw.Color(colors.red[1], colors.red[2], colors.red[3], colors.red[4])
    draw.FilledRect(x, y, x + currentFill, y + h)

    -- Overlay: crit cost (next shot) shown in green.
    if costClamped > 0 and greenStart < greenEnd then
        local alpha = overlayAlpha
        if type(alpha) ~= "number" then
            alpha = colors.green[4]
        end
        draw.Color(colors.green[1], colors.green[2], colors.green[3], alpha)
        draw.FilledRect(greenStart, y, greenEnd, y + h)
    end

    draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    draw.OutlinedRect(x, y, x + w, y + h)
    return y + h + 5
end

local function drawSteppedBar(x, y, w, h, filledSegments, totalSegments, fillColor)
    local segments = math.max(1, math.floor(totalSegments or 1))
    local filled = math.floor(filledSegments or 0)
    if filled < 0 then
        filled = 0
    elseif filled > segments then
        filled = segments
    end

    draw.Color(40, 40, 40, 200)
    draw.FilledRect(x, y, x + w, y + h)

    local left = x
    local baseWidth = math.floor(w / segments)
    local remainder = w - (baseWidth * segments)

    for i = 1, segments do
        local segWidth = baseWidth
        if i <= remainder then
            segWidth = segWidth + 1
        end

        local right = left + segWidth
        if i <= filled then
            draw.Color(fillColor[1], fillColor[2], fillColor[3], fillColor[4])
            draw.FilledRect(left, y, right, y + h)
        end

        if i < segments then
            local alpha = 40
            if (i % 5) == 0 then
                alpha = 85
            end
            draw.Color(255, 255, 255, alpha)
            draw.FilledRect(right - 1, y + 1, right, y + h - 1)
        end

        left = right
    end

    draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    draw.OutlinedRect(x, y, x + w, y + h)
    return y + h + 5
end

local function drawStoredCritHints(x, y, w, h, currentValue, costValue, maxValue, availableChunks)
    local safeMax = math.max(1, math.floor(maxValue or 1))
    local safeCurrent = math.max(0, math.floor(currentValue or 0))
    local count = math.max(0, math.floor(availableChunks or 0))

    if count <= 1 then
        return
    end

    -- Calculate fill ratio and filled width
    local fillRatio = safeCurrent / safeMax
    local filledWidth = fillRatio * w

    -- Divide filled area into equal segments
    local segmentWidth = filledWidth / count

    -- Draw boundaries between each segment
    for i = 1, count - 1 do
        local boundaryX = x + math.floor(i * segmentWidth)
        if boundaryX >= x + filledWidth then
            break
        end

        local alpha = 54 - ((i - 1) * 9)
        if alpha < 10 then
            alpha = 10
        end

        draw.Color(255, 255, 255, alpha)
        draw.FilledRect(boundaryX - 1, y + 1, boundaryX, y + h - 1)
    end
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
        menuSettings.Display = { Enabled = true, X = -1, Y = -1, ShowBucket = true, ShowChance = true }
    end
end

local function ensureDisplayPosition(panelW, panelH)
    if dragRuntime.initializedPos then
        return
    end

    local screenW, screenH = draw.GetScreenSize()
    local x = menuSettings.Display.X
    local y = menuSettings.Display.Y

    if type(x) ~= "number" or x < 0 then
        x = math.floor((screenW - panelW) / 2)
    end
    if type(y) ~= "number" or y < 0 then
        y = math.floor((screenH - panelH) / 2)
    end

    menuSettings.Display.X = x
    menuSettings.Display.Y = y
    dragRuntime.initializedPos = true
end

local function updateHudDrag(panelX, panelY, panelW, panelH)
    if not gui.IsMenuOpen() then
        dragRuntime.active = false
        dragRuntime.wasMouseDown = false
        return
    end

    local mousePos = input.GetMousePos()
    local mouseX = mousePos[1]
    local mouseY = mousePos[2]
    local mouseDown = input.IsButtonDown(KEY_MOUSE1 or MOUSE_LEFT or 107)

    local insidePanel = mouseX >= panelX and mouseX <= (panelX + panelW) and mouseY >= panelY and
        mouseY <= (panelY + panelH)

    if mouseDown and (not dragRuntime.wasMouseDown) and insidePanel then
        dragRuntime.active = true
        dragRuntime.offsetX = mouseX - panelX
        dragRuntime.offsetY = mouseY - panelY
    end

    if not mouseDown then
        dragRuntime.active = false
    end

    if dragRuntime.active then
        local screenW, screenH = draw.GetScreenSize()
        local nextX = mouseX - dragRuntime.offsetX
        local nextY = mouseY - dragRuntime.offsetY
        local maxX = math.max(0, screenW - panelW)
        local maxY = math.max(0, screenH - panelH)

        if nextX < 0 then nextX = 0 end
        if nextY < 0 then nextY = 0 end
        if nextX > maxX then nextX = maxX end
        if nextY > maxY then nextY = maxY end

        menuSettings.Display.X = math.floor(nextX)
        menuSettings.Display.Y = math.floor(nextY)
    end

    dragRuntime.wasMouseDown = mouseDown
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
            local critCost = weapon:GetCritCost(tempSpend, info.critRequestCount + i, info.critCheckCount)
            info.costs[i] = critCost

            if tempSpend >= critCost then
                tempSpend = tempSpend - critCost
                info.storedCrits = info.storedCrits + 1
            end

            if temp < info.bucketMax then
                temp = math.min(temp + info.addedPerShot, info.bucketMax)
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
    local critBanThreshold = cmpCritChance
    local critBannedByChance = false
    local critBanDamageGoal = 0
    local requiredDamage = 0
    if cmpCritChance > 0 then
        local requiredTotalDamage = (criticalDamage * (2.0 * cmpCritChance + 1.0)) / cmpCritChance / 3.0
        critBanDamageGoal = requiredTotalDamage
        requiredDamage = requiredTotalDamage - totalDamage
        critBannedByChance = observedChance >= cmpCritChance
    end

    local minStoredShots = slotSettings.MinStoredShots or 0
    local storedCrits = info.storedCrits or 0
    local usableCrits = math.max(0, storedCrits - minStoredShots)

    local svAllowCrit = weapon:CanRandomCrit()
    local serverAllowCrit = false
    local canCriticalsMelee = client.GetConVar("tf_weapon_criticals_melee")
    local canWeaponCriticals = client.GetConVar("tf_weapon_criticals")

    if weapon:IsMeleeWeapon() then
        if canCriticalsMelee == 2 or (canWeaponCriticals == 1 and canCriticalsMelee == 1) then
            serverAllowCrit = true
        end
    elseif weapon:IsShootingWeapon() then
        if canWeaponCriticals == 1 then
            serverAllowCrit = true
        end
    end

    if weapon:IsMeleeWeapon() then
        local tfWeaponCriticalsMelee = client.GetConVar("tf_weapon_criticals_melee")
        svAllowCrit = (svAllowCrit and tfWeaponCriticalsMelee == 1) or (tfWeaponCriticalsMelee == 2)
    end

    local manualActive = false
    local manualDecision = "idle"
    local isCritBoosted = localPlayer:IsCritBoosted() or localPlayer:InCond(TFCond_CritCola)
    if menuSettings.CritHack.Enabled then
        manualActive = isKeybindActive(menuSettings.CritHack.Keybind)
    end

    local attackPressed = (pCmd:GetButtons() & IN_ATTACK_CONST) ~= 0
    if manualActive and attackPressed then
        if not serverAllowCrit or not svAllowCrit then
            pCmd:SetButtons(pCmd:GetButtons() & (~IN_ATTACK2_CONST))
            manualDecision = "blocked (crit banned)"
        elseif critBannedByChance and not isCritBoosted then
            pCmd:SetButtons(pCmd:GetButtons() & (~IN_ATTACK2_CONST))
            manualDecision = "blocked (crit bucket ban)"
        elseif usableCrits <= 0 then
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

    runtime.lastSlotName = slotName
    runtime.svAllowCrit = svAllowCrit
    runtime.isCritBoosted = isCritBoosted
    runtime.storedCrits = storedCrits
    runtime.minStoredShots = minStoredShots
    runtime.usableCrits = usableCrits
    runtime.bucketCurrent = info.bucketCurrent or 0
    runtime.bucketMax = info.bucketMax or 0
    runtime.shotsUntilFull = info.shotsUntilFull or 0
    runtime.baseCritChance = baseChance * 100
    runtime.modifiedCritChance = modifiedChance * 100
    runtime.observedCritChance = observedChance * 100
    runtime.critBanThreshold = critBanThreshold * 100
    runtime.critBanned = critBannedByChance
    runtime.critBanDamageCurrent = math.max(0, totalDamage)
    runtime.critBanDamageGoal = math.max(0, critBanDamageGoal)
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
    runtime.weaponDisplayName = getWeaponName(weapon)
    runtime.serverAllowCrit = serverAllowCrit
    runtime.rapidFireWeapon = isRapidFireWeapon(weapon)
    runtime.critCapPercent = getCritCapPercent(baseChance)
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
    local menuOpen = gui.IsMenuOpen()
    local panelW = 340
    local panelH = 62
    local panelTopOffset = 34
    local barH = 20
    local rowH = 11
    local leftPad = 6
    local rightInset = 8
    local barW = 236

    ensureDisplayPosition(barW, barH + rowH + 2)

    local baseX = math.floor(menuSettings.Display.X or 10)
    local baseY = math.floor(menuSettings.Display.Y or 350)
    if menuOpen then
        updateHudDrag(baseX - 6, baseY - panelTopOffset, panelW + 6, panelH)
    end

    baseX = math.floor(menuSettings.Display.X or 10)
    baseY = math.floor(menuSettings.Display.Y or 350)
    local y = baseY + 5
    local rightX = baseX + panelW - rightInset

    local canCritNow = false
    local hasBucketForCrit = (runtime.bucketCurrent or 0) >= (runtime.critCostNow or 0)
    if runtime.isCritBoosted then
        canCritNow = true
    elseif runtime.serverAllowCrit and runtime.svAllowCrit and (not runtime.critBanned) and hasBucketForCrit then
        canCritNow = true
    end

    local nowTime = getNowTime()
    if canCritNow and (not runtime.prevCanCritNow) and (not runtime.critBanned) and (not runtime.isCritBoosted) then
        local progressMax = math.max(1, math.floor(runtime.critCostNow or 1))
        local progressValue = math.floor(runtime.bucketCurrent or 0)
        local fromRatio = progressValue / progressMax
        if fromRatio < 0 then
            fromRatio = 0
        elseif fromRatio > 1 then
            fromRatio = 1
        end

        runtime.readyTransitionActive = true
        runtime.readyTransitionPhase = 1
        runtime.readyTransitionStart = nowTime
        runtime.readyTransitionEnd = nowTime + 0.25
        runtime.readyTransitionFrom = fromRatio
        local readyTarget = (runtime.bucketCurrent or 0) / math.max(1, math.floor(runtime.bucketMax or 1000))
        if readyTarget < 0 then
            readyTarget = 0
        elseif readyTarget > 1 then
            readyTarget = 1
        end
        runtime.readyTransitionTarget = readyTarget
    end

    if not canCritNow then
        runtime.readyTransitionActive = false
        runtime.readyTransitionPhase = 0
    end

    local barX = baseX
    local barY = baseY
    local statusY = barY - rowH - 2

    if menuOpen then
        local panelTop = baseY - panelTopOffset
        local panelBottom = panelTop + panelH

        draw.Color(10, 10, 10, 190)
        draw.FilledRect(baseX - 6, panelTop, baseX + panelW, panelBottom)
        draw.Color(235, 235, 235, 170)
        draw.OutlinedRect(baseX - 6, panelTop, baseX + panelW, panelBottom)

        draw.Color(255, 255, 255, 22)
        draw.FilledRect(baseX - 5, panelTop + 1, baseX + panelW - 1, panelTop + 11)
        draw.Color(255, 255, 255, 44)
        draw.FilledRect(baseX - 5, panelTop + 12, baseX + panelW - 1, panelTop + 13)

        draw.Color(255, 255, 255, 160)
        draw.Text(baseX + 205, panelTop + 4, "Drag panel")
        y = panelTop + 4
        statusY = barY - rowH - 2
    else
        barX = baseX
        barY = baseY
        barW = 236
        statusY = barY - rowH - 2
    end

    local barStatusText = "BUILDING"
    local barStatusColor = colors.red
    if runtime.critBanned and not runtime.isCritBoosted then
        barStatusText = "CRIT BANNED"
        barStatusColor = { 150, 30, 30, 255 }
    elseif canCritNow then
        barStatusText = "CRIT READY"
        barStatusColor = colors.green
    end

    draw.Color(barStatusColor[1], barStatusColor[2], barStatusColor[3], barStatusColor[4])
    draw.Text(barX, statusY, barStatusText)

    if menuOpen then
        local headerText = "CRIT MANAGER"
        draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
        draw.Text(baseX + leftPad, y, headerText)

        local critStateText = "CRITS DISABLED"
        local critStateColor = colors.red
        if runtime.isCritBoosted then
            critStateText = "CRIT BOOSTED"
            critStateColor = colors.blue
        elseif runtime.critBanned then
            critStateText = "CRIT BANNED"
            critStateColor = colors.red
        elseif runtime.serverAllowCrit and runtime.svAllowCrit then
            critStateText = "CRITS ENABLED"
            critStateColor = colors.green
        end

        local statusWidth = draw.GetTextSize(critStateText)
        draw.Color(critStateColor[1], critStateColor[2], critStateColor[3], critStateColor[4])
        draw.Text(rightX - statusWidth, y, critStateText)
        y = y + rowH

        local serverText = runtime.serverAllowCrit and "Server Crits: ON" or "Server Crits: OFF"
        local serverColor = runtime.serverAllowCrit and colors.green or colors.red
        draw.Color(serverColor[1], serverColor[2], serverColor[3], serverColor[4])
        draw.Text(baseX + leftPad, y, serverText)

        local capText = string.format("Crit Cap: %.1f%%", runtime.critCapPercent or 0)
        local capWidth = draw.GetTextSize(capText)
        draw.Color(colors.gray[1], colors.gray[2], colors.gray[3], colors.gray[4])
        draw.Text(rightX - capWidth, y, capText)
        y = y + rowH
    end

    if runtime.critBanned and not runtime.isCritBoosted then
        local banMax = math.max(1, math.floor(runtime.critBanDamageGoal or 1))
        local banValue = math.min(math.floor(runtime.critBanDamageCurrent or 0), banMax)
        local banSegmentStep = 50
        local banTotalSegments = math.max(1, math.ceil(banMax / banSegmentStep))
        if banTotalSegments > 48 then
            banSegmentStep = math.max(10, math.ceil(banMax / 48))
            banTotalSegments = math.max(1, math.ceil(banMax / banSegmentStep))
        end
        local banFilledSegments = math.floor(banValue / banSegmentStep)
        y = drawSteppedBar(barX, barY, barW, barH, banFilledSegments, banTotalSegments, { 150, 30, 30, 255 })
    elseif not canCritNow then
        local progressMax = math.max(1, math.floor(runtime.critCostNow or 1))
        local progressValue = math.floor(runtime.bucketCurrent or 0)
        local perShotGain = math.max(1, (runtime.weaponBaseDamage or 1))
        local totalShotsToCrit = math.max(1, math.ceil(progressMax / perShotGain))
        local missingValue = progressMax - progressValue
        if missingValue < 0 then
            missingValue = 0
        end
        local remainingShots = math.max(1, math.ceil(missingValue / perShotGain))
        local currentShotProgress = totalShotsToCrit - remainingShots
        local shotsPerSegment = 1

        if totalShotsToCrit > 48 then
            shotsPerSegment = math.max(1, math.ceil(totalShotsToCrit / 48))
        end

        local totalSegments = math.max(1, math.ceil(totalShotsToCrit / shotsPerSegment))
        local filledSegments = math.floor(currentShotProgress / shotsPerSegment)
        y = drawSteppedBar(barX, barY, barW, barH, filledSegments, totalSegments, colors.red)
    else
        if runtime.readyTransitionActive then
            if runtime.readyTransitionPhase == 1 then
                local duration = runtime.readyTransitionEnd - runtime.readyTransitionStart
                if duration <= 0 then
                    runtime.readyTransitionPhase = 2
                    runtime.readyTransitionStart = nowTime
                    runtime.readyTransitionEnd = nowTime + 0.07
                    runtime.readyTransitionFrom = 1
                else
                    local t = (nowTime - runtime.readyTransitionStart) / duration
                    if t >= 1 then
                        runtime.readyTransitionPhase = 2
                        runtime.readyTransitionStart = nowTime
                        runtime.readyTransitionEnd = nowTime + 0.07
                        runtime.readyTransitionFrom = 1
                    else
                        local fillRatio = runtime.readyTransitionFrom + ((1 - runtime.readyTransitionFrom) * t)
                        y = drawBar(barX, barY, barW, barH, fillRatio, 1, colors.red, 0)
                    end
                end
            end

            if runtime.readyTransitionActive and runtime.readyTransitionPhase == 2 then
                local duration = runtime.readyTransitionEnd - runtime.readyTransitionStart
                if duration <= 0 then
                    runtime.readyTransitionActive = false
                    runtime.readyTransitionPhase = 0
                else
                    local t = (nowTime - runtime.readyTransitionStart) / duration
                    if t >= 1 then
                        runtime.readyTransitionActive = false
                        runtime.readyTransitionPhase = 0
                    else
                        local fillRatio = runtime.readyTransitionFrom +
                            ((runtime.readyTransitionTarget - runtime.readyTransitionFrom) * t)
                        local settleValue = fillRatio * math.max(1, math.floor(runtime.bucketMax or 1000))
                        local cyanAlpha = math.floor(255 * t)
                        y = drawForcePreviewBar(
                            barX,
                            barY,
                            barW,
                            barH,
                            settleValue,
                            runtime.critCostNow or 0,
                            math.max(1, math.floor(runtime.bucketMax or 1000)),
                            cyanAlpha
                        )
                    end
                end
            end
        end

        if (not runtime.readyTransitionActive) and runtime.readyTransitionPhase == 0 then
            y = drawForcePreviewBar(
                barX,
                barY,
                barW,
                barH,
                runtime.bucketCurrent or 0,
                runtime.critCostNow or 0,
                math.max(1, math.floor(runtime.bucketMax or 1000))
            )

            drawStoredCritHints(
                barX,
                barY,
                barW,
                barH,
                runtime.bucketCurrent or 0,
                runtime.critCostNow or 0,
                math.max(1, math.floor(runtime.bucketMax or 1000)),
                runtime.storedCrits or 0
            )
        elseif runtime.readyTransitionPhase == 0 then
            -- No-op; drawn in transition branch above.
        end
    end

    runtime.prevCanCritNow = canCritNow
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
    ensureDisplayPosition(236, 33)
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
