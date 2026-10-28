if not (Config.StockPolice and Config.StockPolice.Remove) then
    return
end

local cfg = Config.StockPolice

local function Hash(list)
    local out = {}

    for _, name in ipairs(list) do
        out[#out + 1] = joaat(name)
    end

    return out
end

local POLICE_VEHICLES = Hash(cfg.Vehicles)
local POLICE_PEDS = Hash(cfg.Peds)

local POLICE_VEHICLE_SET = {}

for _, hash in ipairs(POLICE_VEHICLES) do
    POLICE_VEHICLE_SET[hash] = true
end

-- Typy pedow GTA: 6 = COP, 27 = SWAT.
local POLICE_PED_TYPES = { [6] = true, [27] = true }

local function IsAmbient(entity)
    local population = GetEntityPopulationType(entity)

    return population >= 1 and population <= 5
end

local function VehicleHasPlayer(vehicle)
    for seat = -1, GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2 do
        local occupant = GetPedInVehicleSeat(vehicle, seat)

        if occupant ~= 0 and IsPedAPlayer(occupant) then
            return true
        end
    end

    return false
end

local function RemoveEntity(entity, isVehicle)
    SetEntityAsMissionEntity(entity, true, true)

    if isVehicle then
        DeleteVehicle(entity)
    else
        DeletePed(entity)
    end
end

local function ApplySettings()
    local playerId = PlayerId()

    SetMaxWantedLevel(0)
    SetWantedLevelMultiplier(0.0)

    if GetPlayerWantedLevel(playerId) > 0 then
        ClearPlayerWantedLevel(playerId)
        SetPlayerWantedLevel(playerId, 0, false)
        SetPlayerWantedLevelNow(playerId, false)
    end

    SetPoliceIgnorePlayer(playerId, true)
    SetDispatchCopsForPlayer(playerId, false)

    SetCreateRandomCops(false)
    SetCreateRandomCopsNotOnScenarios(false)
    SetCreateRandomCopsOnScenarios(false)

    for _, service in ipairs(cfg.DispatchServices) do
        EnableDispatchService(service, false)
    end

    for _, hash in ipairs(POLICE_VEHICLES) do
        SetVehicleModelIsSuppressed(hash, true)
    end

    for _, hash in ipairs(POLICE_PEDS) do
        SetPedModelIsSuppressed(hash, true)
    end

    for _, scenario in ipairs(cfg.Scenarios) do
        SetScenarioTypeEnabled(scenario, false)
    end

    CancelCurrentPoliceReport()
    DistantCopCarSirens(false)
    SetAudioFlag('PoliceScannerDisabled', true)
end

CreateThread(function()
    while true do
        ApplySettings()

        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped)
                and POLICE_PED_TYPES[GetPedType(ped)]
                and IsAmbient(ped)
            then
                local vehicle = GetVehiclePedIsIn(ped, false)

                if vehicle ~= 0 and not VehicleHasPlayer(vehicle) then
                    RemoveEntity(vehicle, true)
                end

                RemoveEntity(ped, false)
            end
        end

        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if POLICE_VEHICLE_SET[GetEntityModel(vehicle)]
                and IsAmbient(vehicle)
                and not VehicleHasPlayer(vehicle)
            then
                RemoveEntity(vehicle, true)
            end
        end

        Wait(cfg.CleanupInterval or 1500)
    end
end)
