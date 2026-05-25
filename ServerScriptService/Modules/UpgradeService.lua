local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UpgradeData = require(ReplicatedStorage.SharedModules.UpgradeData)

local UpgradeService = {}
UpgradeService.Purchased = {}

function UpgradeService:InitPlayer(player, saved)
    self.Purchased[player] = saved or {}
end

function UpgradeService:IsPurchased(player, upgradeId)
    return self.Purchased[player] and self.Purchased[player][upgradeId] == true
end

function UpgradeService:Purchase(player, upgradeId, coinService)
    local info = UpgradeData[upgradeId]
    if not info then return false, "invalid" end
    if self:IsPurchased(player, upgradeId) then return false, "owned" end
    if not coinService:SpendCoins(player, info.cost) then return false, "coins" end
    self.Purchased[player][upgradeId] = true
    return true, info
end

return UpgradeService
