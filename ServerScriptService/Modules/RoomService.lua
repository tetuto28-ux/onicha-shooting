local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoomData = require(ReplicatedStorage.SharedModules.RoomData)

local RoomService = {}
RoomService.State = {}

function RoomService:InitPlayer(player, savedRoom)
    self.State[player] = {
        currentRoom = math.max(1, tonumber(savedRoom) or 1),
        foundByRoom = {},
        extraAnomalies = {},
    }
end

function RoomService:GetCurrentRoom(player)
    return self.State[player] and self.State[player].currentRoom or 1
end

function RoomService:GetRoomKeyById(roomId)
    return string.format("Room%03d", roomId)
end

function RoomService:MarkFound(player, roomId, anomalyName)
    local state = self.State[player]
    if not state then return false, 0 end
    state.foundByRoom[roomId] = state.foundByRoom[roomId] or {}
    if state.foundByRoom[roomId][anomalyName] then
        return false, 0
    end
    state.foundByRoom[roomId][anomalyName] = true
    local count = 0
    for _ in pairs(state.foundByRoom[roomId]) do count += 1 end
    return true, count
end

function RoomService:IsCurrentRoom(player, roomId)
    local state = self.State[player]
    if not state then return false end
    return state.currentRoom == roomId
end

function RoomService:IsValidAnomalyForRoom(player, roomId, anomalyName)
    local roomKey = self:GetRoomKeyById(roomId)
    local room = RoomData[roomKey]
    if not room then return false end

    for _, baseName in ipairs(room.anomalies) do
        if baseName == anomalyName then
            return true
        end
    end

    local extras = self.State[player] and self.State[player].extraAnomalies[roomId] or {}
    for _, extraName in ipairs(extras) do
        if extraName == anomalyName then
            return true
        end
    end

    return false
end

function RoomService:IsRoomCleared(player, roomId)
    local roomKey = self:GetRoomKeyById(roomId)
    local base = RoomData[roomKey]
    if not base then return false end
    local total = #base.anomalies + #(self.State[player].extraAnomalies[roomId] or {})
    local found = 0
    local foundMap = self.State[player].foundByRoom[roomId] or {}
    for _ in pairs(foundMap) do found += 1 end
    return found >= total
end

function RoomService:AdvanceRoom(player)
    local state = self.State[player]
    if not state then return 1 end
    state.currentRoom = math.clamp(state.currentRoom + 1, 1, 5)
    return state.currentRoom
end

function RoomService:AddGeneratedAnomaly(player, roomId, anomalyName)
    local state = self.State[player]
    state.extraAnomalies[roomId] = state.extraAnomalies[roomId] or {}
    table.insert(state.extraAnomalies[roomId], anomalyName)
end

function RoomService:CleanupPlayer(player)
    self.State[player] = nil
end

return RoomService
