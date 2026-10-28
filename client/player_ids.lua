local settings = Config.PlayerIds or {}
local enabled = settings.Enabled ~= false
local maxDistance = math.max(1.0, tonumber(settings.Distance) or 25.0)
local headOffset = tonumber(settings.HeadOffset) or 0.28
local requireLineOfSight = settings.RequireLineOfSight ~= false
local idsHeld = false
local inGame = LocalPlayer ~= nil and LocalPlayer.state ~= nil
    and LocalPlayer.state.mono_core_session == 'IN_GAME'

AddEventHandler('mono_core:sessionStateChanged', function(state)
    inGame = state == 'IN_GAME'
end)

RegisterCommand('+mono_player_ids', function()
    idsHeld = true
end, false)

RegisterCommand('-mono_player_ids', function()
    idsHeld = false
end, false)

RegisterKeyMapping(
    '+mono_player_ids',
    'Pokaż ID pobliskich graczy',
    'keyboard',
    settings.Key or 'Z'
)

local function DrawPlayerId(ped, serverId, distance)
    local head = GetPedBoneCoords(ped, 0x796E, 0.0, 0.0, headOffset)
    local onScreen, screenX, screenY = World3dToScreen2d(head.x, head.y, head.z)

    if not onScreen then
        return
    end

    local label = ('ID %d'):format(serverId)
    local scale = math.max(0.24, math.min(0.34, 0.34 - distance * 0.002))
    local width = 0.034 + (#label * scale * 0.00048)

    DrawRect(screenX, screenY + 0.012, width, 0.027, 8, 9, 12, 185)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextColour(241, 209, 138, 245)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayText(screenX, screenY)
end

CreateThread(function()
    while true do
        if not enabled or not idsHeld or not inGame or IsPauseMenuActive() then
            Wait(150)
        else
            local myPed = PlayerPedId()

            if myPed == 0 or not DoesEntityExist(myPed) then
                Wait(100)
            else
                local myCoords = GetEntityCoords(myPed)

                for _, player in ipairs(GetActivePlayers()) do
                    if player ~= PlayerId() and NetworkIsPlayerActive(player) then
                        local ped = GetPlayerPed(player)

                        if ped ~= 0 and DoesEntityExist(ped) and IsEntityVisible(ped) then
                            local distance = #(myCoords - GetEntityCoords(ped))

                            if distance <= maxDistance
                                and (not requireLineOfSight or HasEntityClearLosToEntity(myPed, ped, 17)) then
                                local serverId = GetPlayerServerId(player)

                                if serverId and serverId > 0 then
                                    DrawPlayerId(ped, serverId, distance)
                                end
                            end
                        end
                    end
                end

                Wait(0)
            end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        idsHeld = false
    end
end)
