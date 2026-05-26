local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local SaveService = {}

local STORE_NAME = "IWAKAN_HOTEL_MVP_V1"
local store = nil
local storeResolved = false

local function defaultPayload()
    return {coins = 0, currentRoom = 1, upgrades = {}}
end

-- Resolve the DataStore lazily. In an unpublished Studio place (or with
-- "Studio Access to API Services" disabled) GetDataStore throws, so we swallow
-- the error and run the game without saving instead of crashing the server.
local function getStore()
    if storeResolved then
        return store
    end
    storeResolved = true
    local ok, result = pcall(function()
        return DataStoreService:GetDataStore(STORE_NAME)
    end)
    if ok then
        store = result
    else
        store = nil
        warn("[SaveService] DataStore unavailable, progress will not be saved: " .. tostring(result))
    end
    return store
end

function SaveService:Load(player)
    local ds = getStore()
    if not ds then
        return defaultPayload()
    end
    local ok, data = pcall(function()
        return ds:GetAsync("p_" .. player.UserId)
    end)
    if ok and type(data) == "table" then
        return data
    end
    if not ok and RunService:IsStudio() then
        warn("[SaveService] Load failed in Studio: " .. tostring(data))
    end
    return defaultPayload()
end

function SaveService:Save(player, payload)
    local ds = getStore()
    if not ds then
        return false
    end
    local maxAttempts = 3
    for attempt = 1, maxAttempts do
        local ok, err = pcall(function()
            ds:SetAsync("p_" .. player.UserId, payload)
        end)
        if ok then
            return true
        end
        if RunService:IsStudio() then
            warn(string.format("[SaveService] Save failed in Studio (attempt %d/%d): %s", attempt, maxAttempts, tostring(err)))
        end
        task.wait(0.5 * attempt)
    end
    return false
end

function SaveService:GetDefaultPayload()
    return defaultPayload()
end

return SaveService
