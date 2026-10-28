if not (Config.Zancudo and Config.Zancudo.Remove) then
    return
end

local cfg = Config.Zancudo
local area = cfg.Area

local function Hash(list)
    local out = {}

    for _, name in ipairs(list) do
        out[#out + 1] = joaat(name)
    end

    return out
end

local MILITARY_VEHICLES = Hash(cfg.Vehicles)
local MILITARY_PEDS = Hash(cfg.Peds)

local MILITARY_VEHICLE_SET = {}

for _, hash in ipairs(MILITARY_VEHICLES) do
    MILITARY_VEHICLE_SET[hash] = true
end

local PED_TYPE_ARMY = 29

local function InArea(coords)
    return coords.x >= area.minX and coords.x <= area.maxX
        and coords.y >= area.minY and coords.y <= area.maxY
end

local function IsWorldEntity(entity)
    local population = GetEntityPopulationType(entity)

    return population >= 1 and population <= 6
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
    if NetworkGetEntityIsNetworked(entity) and not NetworkHasControlOfEntity(entity) then
        NetworkRequestControlOfEntity(entity)

        return false
    end

    SetEntityAsMissionEntity(entity, true, true)

    if isVehicle then
        DeleteVehicle(entity)
    else
        DeletePed(entity)
    end

    return true
end

local function ApplySuppression()
    for _, hash in ipairs(MILITARY_VEHICLES) do
        SetVehicleModelIsSuppressed(hash, true)
    end

    for _, hash in ipairs(MILITARY_PEDS) do
        SetPedModelIsSuppressed(hash, true)
    end

    for _, scenario in ipairs(cfg.Scenarios) do
        SetScenarioTypeEnabled(scenario, false)
    end

    for _, group in ipairs(cfg.ScenarioGroups) do
        SetScenarioGroupEnabled(group, false)
    end

    -- Generatory pojazdow (samoloty / helikoptery / czolgi stojace w bazie).
    RemoveVehiclesFromGeneratorsInArea(area.minX, area.minY, -100.0, area.maxX, area.maxY, 600.0, 0)
end

CreateThread(function()
    while true do
        ApplySuppression()

        Wait(5000)
    end
end)

CreateThread(function()
    while true do
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) and IsWorldEntity(ped) then
                if GetPedType(ped) == PED_TYPE_ARMY or InArea(GetEntityCoords(ped)) then
                    local vehicle = GetVehiclePedIsIn(ped, false)

                    if vehicle ~= 0 and IsWorldEntity(vehicle) and not VehicleHasPlayer(vehicle) then
                        RemoveEntity(vehicle, true)
                    end

                    RemoveEntity(ped, false)
                end
            end
        end

        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if IsWorldEntity(vehicle)
                and not VehicleHasPlayer(vehicle)
                and (MILITARY_VEHICLE_SET[GetEntityModel(vehicle)] or InArea(GetEntityCoords(vehicle)))
            then
                RemoveEntity(vehicle, true)
            end
        end

        Wait(cfg.CleanupInterval or 1500)
    end
end)

if Config.Debug then
    local drawing = false

    RegisterCommand('mono_zancudo', function()
        drawing = not drawing

        if not drawing then
            return
        end

        local origin = GetEntityCoords(PlayerPedId())

        print(('[MONO_CORE] Zancudo debug | pozycja: %.1f, %.1f | w obszarze: %s'):format(
            origin.x, origin.y, tostring(InArea(origin))
        ))

        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if #(GetEntityCoords(vehicle) - origin) < 150.0 then
                print(('  pojazd model=%s populacja=%s'):format(
                    GetEntityModel(vehicle), GetEntityPopulationType(vehicle)
                ))
            end
        end
    end, false)

    CreateThread(function()
        while true do
            if drawing then
                local z = GetEntityCoords(PlayerPedId()).z
                local c = {
                    { area.minX, area.minY }, { area.maxX, area.minY },
                    { area.maxX, area.maxY }, { area.minX, area.maxY }
                }

                for i = 1, 4 do
                    local a, b = c[i], c[i % 4 + 1]

                    DrawLine(a[1] + 0.0, a[2] + 0.0, z, b[1] + 0.0, b[2] + 0.0, z, 0, 255, 0, 255)
                    DrawLine(a[1] + 0.0, a[2] + 0.0, z, a[1] + 0.0, a[2] + 0.0, z + 200.0, 0, 255, 0, 255)
                end

                Wait(0)
            else
                Wait(500)
            end
        end
    end)
end
