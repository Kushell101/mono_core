local hornHeld = false
local HORN_CONTROL = 86

RegisterCommand('+mono_core_horn', function()
    hornHeld = true
end, false)

RegisterCommand('-mono_core_horn', function()
    hornHeld = false
end, false)

RegisterKeyMapping('+mono_core_horn', 'Klakson pojazdu', 'keyboard', 'K')

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 then
            DisableControlAction(0, HORN_CONTROL, true)

            if hornHeld and GetPedInVehicleSeat(vehicle, -1) == ped and not IsPauseMenuActive() then
                SetControlNormal(0, HORN_CONTROL, 1.0)
            end

            Wait(0)
        else
            Wait(150)
        end
    end
end)
