local UPDATE_MIN_INTERVAL_MS = 4000
local FLUSH_INTERVAL_MS = 60000
local MAX_SERVER_DRIFT = 150.0

local cache = {}

local function IsFinite(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function IsValidPosition(x, y, z, heading)
    if not (IsFinite(x) and IsFinite(y) and IsFinite(z) and IsFinite(heading)) then
        return false
    end

    -- (0, 0) to pozycja "pustego" peda, nie prawdziwe miejsce w swiecie.
    if x == 0.0 and y == 0.0 then
        return false
    end

    return x > -8000.0 and x < 8000.0
        and y > -8000.0 and y < 8000.0
        and z > -300.0 and z < 2500.0
end

local function Flush(src)
    local entry = cache[src]

    if not entry or not entry.dirty then
        return
    end

    entry.dirty = false

    SaveMonoCharacterPosition(
        entry.playerId,
        entry.characterId,
        entry.x,
        entry.y,
        entry.z,
        entry.heading
    )
end

local function ServerPedCoords(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return nil
    end

    return GetEntityCoords(ped), GetEntityHeading(ped)
end

RegisterNetEvent('mono_core:updatePosition', function(x, y, z, heading)
    local src = source
    local player = GetMonoPlayer(src)
    local character = player and player.activeCharacter

    if not character then
        return
    end

    x, y, z, heading = tonumber(x), tonumber(y), tonumber(z), tonumber(heading)

    if not IsValidPosition(x, y, z, heading) then
        return
    end

    local now = GetGameTimer()
    local entry = cache[src]

    if entry and entry.characterId == character.id and (now - entry.updatedAt) < UPDATE_MIN_INTERVAL_MS then
        return
    end

    local serverCoords = ServerPedCoords(src)

    if serverCoords
        and (serverCoords.x ~= 0.0 or serverCoords.y ~= 0.0)
        and #(vector3(x, y, z) - serverCoords) > MAX_SERVER_DRIFT
    then
        return
    end

    cache[src] = {
        characterId = character.id,
        playerId = player.id,
        x = x,
        y = y,
        z = z,
        heading = heading,
        dirty = true,
        updatedAt = now
    }
end)

function SaveMonoPositionNow(src)
    local entry = cache[src]

    if not entry then
        return
    end

    local coords, heading = ServerPedCoords(src)

    if coords and IsValidPosition(coords.x, coords.y, coords.z, heading) then
        entry.x, entry.y, entry.z, entry.heading = coords.x, coords.y, coords.z, heading
        entry.dirty = true
    end

    Flush(src)

    cache[src] = nil
end

CreateThread(function()
    while true do
        Wait(FLUSH_INTERVAL_MS)

        for src in pairs(cache) do
            Flush(src)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    for src in pairs(cache) do
        Flush(src)
    end
end)