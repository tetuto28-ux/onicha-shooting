local CoinService = {}

local DEFAULT_COINS = 0

function CoinService:InitPlayer(player, savedCoins)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local coins = Instance.new("IntValue")
    coins.Name = "Coins"
    coins.Value = math.max(0, tonumber(savedCoins) or DEFAULT_COINS)
    coins.Parent = leaderstats
end

function CoinService:GetCoins(player)
    local stats = player:FindFirstChild("leaderstats")
    local coins = stats and stats:FindFirstChild("Coins")
    return coins and coins.Value or 0
end

function CoinService:AddCoins(player, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return 0 end
    local stats = player:FindFirstChild("leaderstats")
    local coins = stats and stats:FindFirstChild("Coins")
    if not coins then return 0 end
    coins.Value += amount
    return coins.Value
end

function CoinService:SpendCoins(player, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local stats = player:FindFirstChild("leaderstats")
    local coins = stats and stats:FindFirstChild("Coins")
    if not coins or coins.Value < amount then
        return false
    end
    coins.Value -= amount
    return true
end

return CoinService
