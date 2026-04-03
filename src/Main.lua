--[[ Crit Manager ]]
-- Modular entry for crit storage and crit chance control.

local MenuUI = require("Menu")
local Config = require("utils.Config")
local DefaultConfig = require("utils.DefaultConfig")

local SCRIPT_CONFIG_NAME = "Crit_manager"

local IN_ATTACK_CONST = IN_ATTACK or 1
local IN_ATTACK2_CONST = IN_ATTACK2 or 2
local TF2_SPY_CLASS = TF2_Spy or 8
local KEY_C_CONST = KEY_C or 67
local WEAPON_RANDOM_RANGE = 10000
local SEED_ATTEMPTS = 4096
local PROJECTILE_SEED_ATTEMPTS = 1024

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
local fontId = draw.CreateFont("Smallest Pixel", 11, 400, FONTFLAG_OUTLINE)
local barGradientMask = nil

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
    minStorageMode = 1,
    minStorageValue = 0,
    usableCrits = 0,
    bucketCurrent = 0,
    bucketMax = 0,
    shotsUntilFull = 0,
    baseCritChance = 0,
    modifiedCritChance = 0,
    useChancePercent = 0,
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
    critBoundaryValues = {},
    critBoundaryCount = 0,
    wasAttackDown = false,
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

local function ensureBarGradientMask()
    if barGradientMask ~= nil then
        return
    end

    local texW = 256
    local texH = 16
    local chars = {}

    for y = 0, texH - 1 do
        for x = 0, texW - 1 do
            local g1 = (math.sin((x / texW) * 12.5663706 + (y * 0.35)) + 1.0) * 0.5
            local g2 = (math.sin((x / texW) * 43.9822971 + (y * 0.9)) + 1.0) * 0.5
            local alpha = math.floor(14 + (g1 * 70) + (g2 * 34) + (y * 2))
            if alpha > 255 then
                alpha = 255
            end

            local p = #chars
            chars[p + 1] = 255
            chars[p + 2] = 255
            chars[p + 3] = 255
            chars[p + 4] = alpha
        end
    end

    barGradientMask = draw.CreateTextureRGBA(string.char(table.unpack(chars)), texW, texH)
end

local function drawFillGradient(x, y, right, h)
    if barGradientMask == nil then
        return
    end

    local safeX = math.floor(x)
    local safeY = math.floor(y)
    local safeRight = math.floor(right)
    local safeH = math.floor(h)

    if safeRight <= safeX then
        return
    end

    -- Pure white shine on top -- no color tint so it never shifts fills below it.
    draw.Color(255, 255, 255, 60)
    draw.TexturedRect(barGradientMask, safeX, safeY, safeRight, safeY + safeH)
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

    local safeX = math.floor(x)
    local safeY = math.floor(y)
    local safeW = math.floor(w)
    local safeH = math.floor(h)

    local fill = math.floor((clampedValue / safeMax) * safeW)
    draw.Color(40, 40, 40, 200)
    draw.FilledRect(safeX, safeY, safeX + safeW, safeY + safeH)
    draw.Color(color[1], color[2], color[3], color[4])
    draw.FilledRect(safeX, safeY, safeX + fill, safeY + safeH)
    drawFillGradient(safeX, safeY, safeX + fill, safeH)
    drawSegmentTicks(safeX, safeY, safeW, safeH, safeMax, segmentValue or 0)
    draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    draw.OutlinedRect(safeX, safeY, safeX + safeW, safeY + safeH)
    return safeY + safeH + 5
end

local function drawForcePreviewBar(x, y, w, h, currentValue, costValue, maxValue, overlayAlpha)
    local safeX = math.floor(x)
    local safeY = math.floor(y)
    local safeW = math.floor(w)
    local safeH = math.floor(h)
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

    local currentFill = math.floor((currentClamped / safeMax) * safeW)
    local greenStartValue = currentClamped - costClamped
    if greenStartValue < 0 then
        greenStartValue = 0
    end
    local greenStart = safeX + math.floor((greenStartValue / safeMax) * safeW)
    local greenEnd = safeX + math.floor((currentClamped / safeMax) * safeW)

    draw.Color(40, 40, 40, 200)
    draw.FilledRect(safeX, safeY, safeX + safeW, safeY + safeH)

    -- Red fills only the non-crit region. Crit cost region stays dark.
    -- No texture here -- texture is applied once at end of drawStoredCritHints.
    draw.Color(colors.red[1], colors.red[2], colors.red[3], colors.red[4])
    draw.FilledRect(safeX, safeY, greenStart, safeY + safeH)

    draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    draw.OutlinedRect(safeX, safeY, safeX + safeW, safeY + safeH)
    return safeY + safeH + 5
end

local function drawSteppedBar(x, y, w, h, filledSegments, totalSegments, fillColor)
    local segments = math.max(1, math.floor(totalSegments or 1))
    local filled = math.floor(filledSegments or 0)
    if filled < 0 then
        filled = 0
    elseif filled > segments then
        filled = segments
    end

    local safeX = math.floor(x)
    local safeY = math.floor(y)
    local safeW = math.floor(w)
    local safeH = math.floor(h)

    draw.Color(40, 40, 40, 200)
    draw.FilledRect(safeX, safeY, safeX + safeW, safeY + safeH)

    local left = safeX
    local baseWidth = math.floor(safeW / segments)
    local remainder = safeW - (baseWidth * segments)
    local filledRight = safeX

    for i = 1, segments do
        local segWidth = baseWidth
        if i <= remainder then
            segWidth = segWidth + 1
        end

        local right = left + segWidth
        if i <= filled then
            draw.Color(fillColor[1], fillColor[2], fillColor[3], fillColor[4])
            draw.FilledRect(left, safeY, right, safeY + safeH)
            filledRight = right
        end

        if i < segments then
            local alpha = 40
            if (i % 5) == 0 then
                alpha = 85
            end
            draw.Color(255, 255, 255, alpha)
            draw.FilledRect(right - 1, safeY + 1, right, safeY + safeH - 1)
        end

        left = right
    end

    drawFillGradient(safeX, safeY, filledRight, safeH)

    draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
    draw.OutlinedRect(safeX, safeY, safeX + safeW, safeY + safeH)
    return safeY + safeH + 5
end

local function drawStoredCritHints(x, y, w, h, currentValue, maxValue, boundaryValues, boundaryCount)
    local safeMax       = math.max(1, math.floor(maxValue or 1))
    local safeCurrent   = math.max(0, math.floor(currentValue or 0))
    local count         = math.max(0, math.floor(boundaryCount or 0))

    local safeX         = math.floor(x)
    local safeY         = math.floor(y)
    local safeW         = math.floor(w)
    local safeH         = math.floor(h)

    local seg1Left      = safeX + math.floor((math.max(0, math.floor(boundaryValues[1] or 0)) / safeMax) * safeW)
    local seg1Right     = safeX + math.floor((safeCurrent / safeMax) * safeW)
    local fullFillRight = seg1Right

    -- Seg1: solid green on dark bg (drawForcePreviewBar left it dark)
    if count >= 1 and seg1Right > seg1Left then
        draw.Color(colors.green[1], colors.green[2], colors.green[3], 255)
        draw.FilledRect(seg1Left, safeY, seg1Right, safeY + safeH)
    end

    -- Segs 2..5: logarithmic alpha decay (~65% each step) so each step is clearly distinct
    -- Draws on dark bg so green fades cleanly to dark without color mixing with red
    if count >= 2 then
        local logAlphas = { 70, 40, 22, 10 }
        local maxSegments = math.min(count, 5)
        local prevValue = math.max(0, math.floor(boundaryValues[1] or 0))

        for i = 2, maxSegments do
            local nextValue = boundaryValues[i] or 0
            if nextValue < 0 then
                nextValue = 0
            elseif nextValue > safeMax then
                nextValue = safeMax
            end

            local rightX = safeX + math.floor((prevValue / safeMax) * safeW)
            local leftX  = safeX + math.floor((nextValue / safeMax) * safeW)

            if leftX >= rightX then break end

            local alpha = logAlphas[i - 1] or 20
            draw.Color(colors.green[1], colors.green[2], colors.green[3], alpha)
            draw.FilledRect(leftX, safeY, rightX, safeY + safeH)

            prevValue = nextValue
        end
    end

    -- Single texture shine pass over entire filled area (red + all green)
    -- Texture is white-only so it never tints fills underneath
    if fullFillRight > safeX then
        drawFillGradient(safeX, safeY, fullFillRight, safeH)
    end

    -- White dividers painted on top of texture
    if count >= 1 and seg1Right > seg1Left then
        draw.Color(255, 255, 255, 90)
        draw.FilledRect(seg1Left, safeY + 1, seg1Left + 1, safeY + safeH - 1)
    end
    if count >= 2 then
        local maxSegments = math.min(count, 5)
        local prevValue = math.max(0, math.floor(boundaryValues[1] or 0))
        for i = 2, maxSegments do
            local nextValue = boundaryValues[i] or 0
            if nextValue < 0 then
                nextValue = 0
            elseif nextValue > safeMax then
                nextValue = safeMax
            end

            local rightX = safeX + math.floor((prevValue / safeMax) * safeW)
            local leftX  = safeX + math.floor((nextValue / safeMax) * safeW)

            if leftX >= rightX then break end

            draw.Color(255, 255, 255, 90)
            draw.FilledRect(leftX, safeY + 1, leftX + 1, safeY + safeH - 1)

            prevValue = nextValue
        end
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
        menuSettings.CritHack.Keybind = { key = KEY_C_CONST, mode = 2 }
    end
    if menuSettings.CritHack.Keybind.key == nil or menuSettings.CritHack.Keybind.key == 0 then
        menuSettings.CritHack.Keybind.key = KEY_C_CONST
    end
    if menuSettings.CritHack.Keybind.mode == nil then
        menuSettings.CritHack.Keybind.mode = 2
    end

    if type(menuSettings.Slots) ~= "table" then
        menuSettings.Slots = {}
    end
    if type(menuSettings.Slots.Primary) ~= "table" then
        menuSettings.Slots.Primary = { StorageMode = 1, MinStorageValue = 0, UseProbabilityModifier = false, ChanceModifierPercent = 100 }
    end
    if type(menuSettings.Slots.Secondary) ~= "table" then
        menuSettings.Slots.Secondary = { StorageMode = 1, MinStorageValue = 0, UseProbabilityModifier = false, ChanceModifierPercent = 100 }
    end
    if type(menuSettings.Slots.Melee) ~= "table" then
        menuSettings.Slots.Melee = { StorageMode = 1, MinStorageValue = 0, UseProbabilityModifier = false, ChanceModifierPercent = 100 }
    end

    local slotNames = { "Primary", "Secondary", "Melee" }
    for i = 1, #slotNames do
        local slotName = slotNames[i]
        local slotCfg = menuSettings.Slots[slotName]
        if slotCfg.StorageMode == nil then
            slotCfg.StorageMode = 1
        end
        if slotCfg.MinStorageValue == nil then
            slotCfg.MinStorageValue = slotCfg.MinStoredShots or 0
        end
        if slotCfg.UseProbabilityModifier == nil then
            slotCfg.UseProbabilityModifier = false
        end
        if slotCfg.ChanceModifierPercent == nil then
            slotCfg.ChanceModifierPercent = 100
        end
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
    local mouseDown = input.IsButtonDown(MOUSE_LEFT or 107)

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
        slotCfg = { StorageMode = 1, MinStorageValue = 0, UseProbabilityModifier = false, ChanceModifierPercent = 100 }
        slots[slotName] = slotCfg
    end
    return slotCfg
end

local function isKeybindActive(bind, pCmd)
    if type(bind) ~= "table" then
        return false
    end

    local key = bind.key or 0
    local mode = bind.mode or 2

    if mode == 1 then
        return true
    end

    if key == 0 then
        return input.IsButtonDown(KEY_C_CONST)
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

local function getCmdNumber(pCmd)
    local okMethod, methodValue = pcall(function()
        return pCmd:GetCommandNumber()
    end)
    if okMethod and type(methodValue) == "number" then
        return methodValue
    end

    local okField, fieldValue = pcall(function()
        return pCmd.command_number
    end)
    if okField and type(fieldValue) == "number" then
        return fieldValue
    end

    return nil
end

local function setCmdNumber(pCmd, value)
    local safeValue = math.floor(value)

    local okMethod = pcall(function()
        pCmd:SetCommandNumber(safeValue)
    end)
    if okMethod then
        return true
    end

    local okField = pcall(function()
        pCmd.command_number = safeValue
    end)
    if okField then
        return true
    end

    return false
end

local function setCmdRandomSeed(pCmd, value)
    local safeValue = math.floor(value)

    local okMethod = pcall(function()
        pCmd:SetRandomSeed(safeValue)
    end)
    if okMethod then
        return true
    end

    local okField = pcall(function()
        pCmd.random_seed = safeValue
    end)
    if okField then
        return true
    end

    return false
end

local function md5PseudoRandom(commandNumber)
    local md5Fn = rawget(_G, "MD5_PseudoRandom")
    if type(md5Fn) == "function" then
        local okGlobal, globalValue = pcall(function()
            return md5Fn(commandNumber)
        end)
        if okGlobal and type(globalValue) == "number" then
            return globalValue
        end
    end

    local clientTable = rawget(_G, "client")
    if type(clientTable) == "table" then
        local clientMd5Fn = clientTable["MD5_PseudoRandom"]
        if type(clientMd5Fn) == "function" then
            local okClient, clientValue = pcall(function()
                return clientMd5Fn(commandNumber)
            end)
            if okClient and type(clientValue) == "number" then
                return clientValue
            end
        end
    end

    return nil
end

local function randomIntSeeded(seed, low, high)
    local clientTable = rawget(_G, "client")
    if type(clientTable) == "table" then
        local seededRandFn = clientTable["RandomIntSeeded"]
        if type(seededRandFn) == "function" then
            local okEngine, engineValue = pcall(function()
                return seededRandFn(seed, low, high)
            end)
            if okEngine and type(engineValue) == "number" then
                return engineValue
            end
        end
    end

    -- Fallback only when explicit engine seeded RNG is unavailable.
    local okLua = pcall(function()
        math.randomseed(seed)
    end)
    if not okLua then
        return nil
    end

    local okRoll, rollValue = pcall(function()
        return math.random(low, high)
    end)
    if okRoll and type(rollValue) == "number" then
        return rollValue
    end

    return nil
end

local function commandToSeed(commandNumber)
    local pseudo = md5PseudoRandom(commandNumber)
    if type(pseudo) ~= "number" then
        return nil
    end

    return pseudo & 0x7fffffff
end

local function isCritCommand(commandNumber, weapon, localPlayer, wantCrit, critChance)
    local seed = commandToSeed(commandNumber)
    if type(seed) ~= "number" then
        return false
    end

    local randomRoll = randomIntSeeded(seed, 0, WEAPON_RANDOM_RANGE - 1)
    if type(randomRoll) ~= "number" then
        return false
    end

    local chance = critChance
    if chance < 0 then
        chance = 0
    elseif chance > 1 then
        chance = 1
    end
    local range = math.floor(chance * WEAPON_RANDOM_RANGE)
    local isCrit = randomRoll < range
    if wantCrit then
        return isCrit
    end
    return not isCrit
end

local function findCritCommand(weapon, localPlayer, commandNumber, wantCrit, critChance, maxAttempts)
    if type(commandNumber) ~= "number" then
        return nil
    end

    local attempts = maxAttempts or SEED_ATTEMPTS
    if attempts < 1 then
        attempts = 1
    end

    local startCommand = math.floor(commandNumber)
    for i = startCommand, startCommand + attempts do
        if isCritCommand(i, weapon, localPlayer, wantCrit, critChance) then
            return i
        end
    end

    return nil
end

local function isProjectileLauncherClass(className)
    return className == "CTFRocketLauncher"
        or className == "CTFRocketLauncher_DirectHit"
        or className == "CTFGrenadeLauncher"
        or className == "CTFPipebombLauncher"
        or className == "CTFCannon"
end

local function shouldRewriteCmdForWeapon(weapon)
    local className = weapon:GetClass()
    return className ~= nil
end

local function getSeedAttemptsForWeapon(weapon)
    local className = weapon:GetClass()
    if isProjectileLauncherClass(className) then
        return PROJECTILE_SEED_ATTEMPTS
    end
    return SEED_ATTEMPTS
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
    if modifierPct < 0 then
        modifierPct = 0
    elseif modifierPct > 100 then
        modifierPct = 100
    end
    local useProbabilityModifier = slotSettings.UseProbabilityModifier == true
    local manualUseChance = 1.0
    if useProbabilityModifier then
        manualUseChance = modifierPct / 100
    end
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

    local storageMode = slotSettings.StorageMode or 1
    local minStorageValue = slotSettings.MinStorageValue
    if minStorageValue == nil then
        minStorageValue = slotSettings.MinStoredShots or 0
    end
    if type(minStorageValue) ~= "number" then
        minStorageValue = 0
    end

    local storedCrits = info.storedCrits or 0
    local minStoredShots = 0
    if storageMode == 2 then
        minStoredShots = math.floor((storedCrits * (minStorageValue / 100)) + 0.5)
    else
        minStoredShots = math.floor(minStorageValue)
    end
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
        manualActive = isKeybindActive(menuSettings.CritHack.Keybind, pCmd)
    end

    local cmdButtons = pCmd:GetButtons()
    local attackPressed = (cmdButtons & IN_ATTACK_CONST) ~= 0
    local attackJustPressed = attackPressed and (not runtime.wasAttackDown)
    local shouldProcessManual = attackJustPressed
    if info.isRapidFire and attackPressed then
        shouldProcessManual = true
    end
    runtime.wasAttackDown = attackPressed

    if manualActive and shouldProcessManual then
        if not serverAllowCrit or not svAllowCrit then
            manualDecision = "blocked (crit banned)"
        elseif critBannedByChance and not isCritBoosted then
            manualDecision = "blocked (crit bucket ban)"
        elseif usableCrits <= 0 then
            manualDecision = "blocked (minimum storage)"
        else
            local shouldAttemptManualCrit = true
            if useProbabilityModifier then
                if math.random() > manualUseChance then
                    shouldAttemptManualCrit = false
                end
            end

            if shouldAttemptManualCrit then
                local canRewriteCmd = shouldRewriteCmdForWeapon(weapon)
                local rewriteApplied = false

                if canRewriteCmd then
                    local originalCmdNumber = getCmdNumber(pCmd)
                    local maxAttempts = getSeedAttemptsForWeapon(weapon)
                    local forcedCmdNumber = findCritCommand(
                        weapon,
                        localPlayer,
                        originalCmdNumber,
                        true,
                        baseChance,
                        maxAttempts
                    )
                    if forcedCmdNumber then
                        local cmdSetOk = setCmdNumber(pCmd, forcedCmdNumber)
                        local pseudo = md5PseudoRandom(forcedCmdNumber)
                        local seedSetOk = false
                        if type(pseudo) == "number" then
                            local maskedSeed = pseudo & 0x7fffffff
                            seedSetOk = setCmdRandomSeed(pCmd, maskedSeed)
                        end

                        if cmdSetOk then
                            rewriteApplied = true
                            if seedSetOk then
                                manualDecision = "allowed (forced cmd+seed)"
                            else
                                manualDecision = "allowed (forced cmd)"
                            end
                        end
                    end
                end

                if not rewriteApplied then
                    manualDecision = "blocked (no crit command found)"
                end
            else
                manualDecision = "blocked (probability modifier)"
            end
        end
    end

    runtime.lastSlotName = slotName
    runtime.svAllowCrit = svAllowCrit
    runtime.isCritBoosted = isCritBoosted
    runtime.storedCrits = storedCrits
    runtime.minStoredShots = minStoredShots
    runtime.minStorageMode = storageMode
    runtime.minStorageValue = minStorageValue
    runtime.usableCrits = usableCrits
    runtime.bucketCurrent = info.bucketCurrent or 0
    runtime.bucketMax = info.bucketMax or 0
    runtime.shotsUntilFull = info.shotsUntilFull or 0
    runtime.baseCritChance = baseChance * 100
    runtime.modifiedCritChance = manualUseChance * 100
    runtime.useChancePercent = manualUseChance * 100
    runtime.observedCritChance = observedChance * 100
    runtime.critBanThreshold = critBanThreshold * 100
    runtime.critBanned = critBannedByChance
    runtime.critBanDamageCurrent = math.max(0, totalDamage)
    runtime.critBanDamageGoal = math.max(0, critBanDamageGoal)
    runtime.requiredDamage = math.max(0, requiredDamage)
    runtime.manualKeyActive = manualActive
    runtime.manualDecision = manualDecision
    if menuSettings.Slots.Primary.UseProbabilityModifier then
        runtime.slotModifierPrimary = (menuSettings.Slots.Primary.ChanceModifierPercent or 100)
    else
        runtime.slotModifierPrimary = 100
    end
    if menuSettings.Slots.Secondary.UseProbabilityModifier then
        runtime.slotModifierSecondary = (menuSettings.Slots.Secondary.ChanceModifierPercent or 100)
    else
        runtime.slotModifierSecondary = 100
    end
    if menuSettings.Slots.Melee.UseProbabilityModifier then
        runtime.slotModifierMelee = (menuSettings.Slots.Melee.ChanceModifierPercent or 100)
    else
        runtime.slotModifierMelee = 100
    end

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

    local oldBoundaryCount = runtime.critBoundaryCount or 0
    local boundaryCount = 0
    local simBucket = info.bucketCurrent or 0
    local simStoredCrits = storedCrits or 0
    local simRequestCount = info.critRequestCount or 0
    local simCheckCount = info.critCheckCount or 0

    if simBucket > 0 and simStoredCrits > 0 then
        for i = 0, simStoredCrits - 1 do
            local okSimCost, simCost = pcall(function()
                return weapon:GetCritCost(simBucket, simRequestCount + i, simCheckCount)
            end)
            if (not okSimCost) or type(simCost) ~= "number" or simCost <= 0 then
                break
            end
            if simBucket < simCost then
                break
            end

            simBucket = simBucket - simCost
            boundaryCount = boundaryCount + 1
            runtime.critBoundaryValues[boundaryCount] = simBucket

            if simBucket <= 0 then
                break
            end
        end
    end

    if oldBoundaryCount > boundaryCount then
        for i = boundaryCount + 1, oldBoundaryCount do
            runtime.critBoundaryValues[i] = nil
        end
    end
    runtime.critBoundaryCount = boundaryCount
end

local function drawIndicator(localPlayer, weapon)
    ensureBarGradientMask()

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
    local showDetailedText = menuOpen
    local panelW = 340
    local panelH = 62
    local panelTopOffset = 34
    local barH = 20
    local rowH = 11
    local leftPad = 6
    local rightInset = 8
    local barW = 236

    if showDetailedText then
        local infoRows = 0
        if menuSettings.Display.ShowBucket then
            infoRows = infoRows + 1
        end
        if menuSettings.Display.ShowChance then
            infoRows = infoRows + 1
        end

        panelW = 352
        panelH = panelTopOffset + barH + 10 + (infoRows * rowH) + 8
    end

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
        barStatusColor = { 23, 165, 239, 255 }
    elseif (runtime.bucketCurrent or 0) <= 0 then
        barStatusText = "NO CHARGE"
        barStatusColor = colors.red
    else
        barStatusText = "CHARGING"
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
                math.max(1, math.floor(runtime.bucketMax or 1000)),
                runtime.critBoundaryValues,
                runtime.critBoundaryCount or 0
            )
        elseif runtime.readyTransitionPhase == 0 then
            -- No-op; drawn in transition branch above.
        end
    end

    if showDetailedText then
        local infoY = barY + barH + 4
        if menuSettings.Display.ShowBucket then
            local reserveText = "shots"
            if runtime.minStorageMode == 2 then
                reserveText = "%"
            end

            local bucketLine = string.format(
                "Bucket %d/%d  Stored %d  Min %d%s  Usable %d",
                math.floor(runtime.bucketCurrent or 0),
                math.floor(runtime.bucketMax or 0),
                math.floor(runtime.storedCrits or 0),
                math.floor(runtime.minStorageValue or 0),
                reserveText,
                math.floor(runtime.usableCrits or 0)
            )
            draw.Color(colors.white[1], colors.white[2], colors.white[3], colors.white[4])
            draw.Text(baseX, infoY, bucketLine)
            infoY = infoY + rowH
        end

        if menuSettings.Display.ShowChance then
            local chanceLine = string.format(
                "Chance Base %.2f%%  Use %.2f%%  Observed %.2f%%  Slot %s",
                runtime.baseCritChance or 0,
                runtime.useChancePercent or 0,
                runtime.observedCritChance or 0,
                runtime.lastSlotName or "Primary"
            )
            draw.Color(colors.gray[1], colors.gray[2], colors.gray[3], colors.gray[4])
            draw.Text(baseX, infoY, chanceLine)
        end
    end

    runtime.prevCanCritNow = canCritNow
end

local function onCreateMove(pCmd)
    ensureMenuDefaults()

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or not localPlayer:IsAlive() then
        runtime.wasAttackDown = false
        runtime.manualDecision = "idle"
        return
    end

    local weapon = localPlayer:GetPropEntity("m_hActiveWeapon")
    if not weapon or not weapon:IsWeapon() then
        runtime.wasAttackDown = false
        runtime.manualDecision = "idle"
        return
    end

    if not canFireCriticalShot(localPlayer, weapon) then
        runtime.wasAttackDown = false
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
    if barGradientMask ~= nil then
        draw.DeleteTexture(barGradientMask)
        barGradientMask = nil
    end

    Config.CreateCFG(menuSettings, SCRIPT_CONFIG_NAME)
end

callbacks.Unregister("CreateMove", "CritManager_CreateMove")
callbacks.Unregister("Draw", "CritManager_Draw")
callbacks.Unregister("Unload", "CritManager_Unload")

callbacks.Register("CreateMove", "CritManager_CreateMove", onCreateMove)
callbacks.Register("Draw", "CritManager_Draw", onDraw)
callbacks.Register("Unload", "CritManager_Unload", onUnload)

printc(100, 255, 200, 255, "[Crit Manager] Loaded")
