local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local SaveService = {}
local store = DataStoreService:GetDataStore("IWAKAN_HOTEL_MVP_V1")

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
    return {coins = 0, currentRoom = 1, upgrades = {}}
end

function SaveService:Save(player, payload)
    local ok, err = pcall(function()
        store:SetAsync("p_" .. player.UserId, payload)
    end)
    if not ok and RunService:IsStudio() then
        warn("[SaveService] Save failed in Studio: " .. tostring(err))
    end
    return ok
end

return SaveService
