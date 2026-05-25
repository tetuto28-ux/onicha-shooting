local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnomalyData = require(ReplicatedStorage.SharedModules.AnomalyData)

local AnomalyService = {}

function AnomalyService:GetReward(anomalyName)
    local data = AnomalyData[anomalyName]
    if not data then return 10, false end
    return data.reward or 10, data.isRare == true
end

function AnomalyService:PickGeneratedAnomaly(candidates, existingSet)
    local pool = {}
    for _, name in ipairs(candidates) do
        if not existingSet[name] then
            table.insert(pool, name)
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

return AnomalyService
