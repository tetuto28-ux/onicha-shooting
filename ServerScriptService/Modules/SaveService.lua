local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local SaveService = {}
local store = DataStoreService:GetDataStore("IWAKAN_HOTEL_MVP_V1")

local function defaultPayload()
    return {coins = 0, currentRoom = 1, upgrades = {}}
end

function SaveService:Load(player)
    local ok, data = pcall(function()
        return store:GetAsync("p_" .. player.UserId)
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
    local maxAttempts = 3
    for attempt = 1, maxAttempts do
        local ok, err = pcall(function()
            store:SetAsync("p_" .. player.UserId, payload)
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
