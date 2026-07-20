local QualityMod = RegisterMod("Quality Indicator", 1)

-- ============================================================
-- Quality Indicator
--
-- by bëwf
-- ============================================================

local config = {
    ShowDuringBlind = false,
    ShowUnseenItems = true,
}

local function loadDefaultsFromFile()
    local ok, loaded
    if include then
        ok, loaded = pcall(include, "config")
    else
        ok, loaded = pcall(require, "config")
    end
    if ok and type(loaded) == "table" then
        if loaded.ShowDuringBlind ~= nil then config.ShowDuringBlind = loaded.ShowDuringBlind end
        if loaded.ShowUnseenItems ~= nil then config.ShowUnseenItems = loaded.ShowUnseenItems end
    end
end
loadDefaultsFromFile()

local function loadConfig()
    if not QualityMod:HasData() then return end
    local ok, raw = pcall(function() return QualityMod:LoadData() end)
    if not ok or not raw or raw == "" then return end
    local blind, unseen = raw:match("^(%d),(%d)$")
    if blind then
        config.ShowDuringBlind = blind == "1"
        config.ShowUnseenItems = unseen == "1"
    end
end

local function saveConfig()
    local raw = (config.ShowDuringBlind and "1" or "0") .. "," .. (config.ShowUnseenItems and "1" or "0")
    pcall(function() QualityMod:SaveData(raw) end)
end

local function loadModuleFile(path)
    if include then
        local ok, result = pcall(include, path)
        if ok then return result end
    end
    local ok2, result2 = pcall(require, (path:gsub("/", ".")))
    if ok2 then return result2 end
    return nil
end

-- Fixed offset from pedestal center
local OFFSET_X = 9
local OFFSET_Y = 5

-- Quality data (static, bundled with the mod)
local QUALITY_BY_ITEM = {}
local qualityData = loadModuleFile("data/qualities")
if type(qualityData) == "table" then
    QUALITY_BY_ITEM = qualityData
else
    Isaac.DebugString("Quality Indicator: failed to load data/qualities.lua - check it exists in the mod folder and returns a table")
end

-- Colors for text fallback
local QUALITY_COLORS = {
    [0] = {0.55, 0.39, 0.16},
    [1] = {0.67, 0.67, 0.67},
    [2] = {0.30, 0.70, 0.89},
    [3] = {0.60, 0.20, 0.80},
    [4] = {1.00, 0.84, 0.00},
}

-- Load sprites for quality badges
local QUALITY_SPRITES = {}
for quality = 0, 4 do
    local sprite = Sprite()
    if sprite:Load("gfx/q" .. quality .. ".anm2", true) then
        sprite:SetFrame(0, 0)
        QUALITY_SPRITES[quality] = sprite
    else
        Isaac.DebugString("Quality Indicator: could not load gfx/q" .. quality .. ".anm2 - make sure it's at resources/gfx/q" .. quality .. ".anm2 in the mod folder")
    end
end

local function hasCurseOfTheBlind()
    local game = Game()
    if not game then return false end
    local level = game:GetLevel()
    if not level then return false end
    -- Repentance+ uses bit 64 for Curse of the Blind
    return level:GetCurses() & 64 ~= 0
end

local function hasSeenItem(subType)
    local game = Game()
    if not game then return false end
    local itemPool = game:GetItemPool()
    if not itemPool then return false end
    local ok, result = pcall(function()
        return itemPool:HasEverCollectedCollectible(subType)
    end)
    if ok and result ~= nil then return result end
    return false
end

local function shouldShowQuality(subType)
    if hasCurseOfTheBlind() and not config.ShowDuringBlind then return false end
    if not hasSeenItem(subType) and not config.ShowUnseenItems then return false end
    return true
end

local DEBUG_LOGGED = {}
local function debugLogPedestal(subType)
    if DEBUG_LOGGED[subType] then return end
    DEBUG_LOGGED[subType] = true
    local quality = QUALITY_BY_ITEM[subType]
    local spriteOk = quality ~= nil and QUALITY_SPRITES[quality] ~= nil
    Isaac.DebugString(string.format(
        "Quality Indicator DEBUG: subType=%d quality=%s spriteLoaded=%s blind=%s everCollected=%s willShow=%s",
        subType,
        tostring(quality),
        tostring(spriteOk),
        tostring(hasCurseOfTheBlind()),
        tostring(hasSeenItem(subType)),
        tostring(quality ~= nil and shouldShowQuality(subType))
    ))
end

-- Render quality badge on pedestals
QualityMod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    local game = Game()
    if not game then return end

    for _, entity in ipairs(Isaac.FindByType(5, 100, -1, false, false)) do
        if entity and entity.SubType > 0 then
            debugLogPedestal(entity.SubType)
            local quality = QUALITY_BY_ITEM[entity.SubType]
            if quality ~= nil and shouldShowQuality(entity.SubType) then
                local worldPos = entity.Position + Vector(OFFSET_X, OFFSET_Y)
                local screenPos = Isaac.WorldToScreen(worldPos)
                local x = screenPos.X
                local y = screenPos.Y

                local sprite = QUALITY_SPRITES[quality]
                if sprite then
                    -- Use sprite if available
                    sprite:Render(screenPos, Vector(0, 0), Vector(0, 0))
                else
                    -- Fallback: text rendering
                    local color = QUALITY_COLORS[quality]
                    if color then
                        Isaac.RenderText("■", x - 1, y - 1, 0, 0, 0, 0.75)
                        Isaac.RenderText("■", x - 2, y - 2, color[1], color[2], color[3], 1)
                        Isaac.RenderText(tostring(quality), x, y - 1, 0, 0, 0, 0.9)
                        Isaac.RenderText(tostring(quality), x - 1, y - 2, 1, 1, 1, 1)
                    end
                end
            end
        end
    end
end)

-- Load saved settings + Mod Config Menu integration
local MCM_REGISTERED = false
QualityMod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    loadConfig()

    if ModConfigMenu == nil then return end
    if MCM_REGISTERED then return end
    MCM_REGISTERED = true

    local ok, err = pcall(function()
        ModConfigMenu.AddText("Quality Indicator", "Info", "Quality Indicator")
        ModConfigMenu.AddSpace("Quality Indicator", "Info")
        ModConfigMenu.AddText("Quality Indicator", "Info", "Version 1.2.0")
        ModConfigMenu.AddSpace("Quality Indicator", "Info")
        ModConfigMenu.AddText("Quality Indicator", "Info", "by bëwf")

        ModConfigMenu.AddSetting("Quality Indicator", "General", {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
                return config.ShowDuringBlind
            end,
            Display = function()
                return "Curse of the Blind: " .. (config.ShowDuringBlind and "Show" or "Hide")
            end,
            OnChange = function(n)
                config.ShowDuringBlind = n
                saveConfig()
            end,
            Info = {"Whether to hide (default) or show quality badges during Curse of the Blind"}
        })

        ModConfigMenu.AddSetting("Quality Indicator", "General", {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
                return config.ShowUnseenItems
            end,
            Display = function()
                return "Unseen Items: " .. (config.ShowUnseenItems and "Show" or "Hide")
            end,
            OnChange = function(n)
                config.ShowUnseenItems = n
                saveConfig()
            end,
            Info = {"Whether to hide quality for unseen items or show (default) for all items."}
        })
    end)

    if not ok then
        Isaac.DebugString("Quality Indicator Config Error: " .. tostring(err))
    end
end)