local function removeGtaMoneyUi()
    RemoveMultiplayerHudCash()
    RemoveMultiplayerWalletCash()
    RemoveMultiplayerBankCash()
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    removeGtaMoneyUi()
    SetTimeout(500, removeGtaMoneyUi)
end)

AddEventHandler('playerSpawned', function()
    removeGtaMoneyUi()
    SetTimeout(500, removeGtaMoneyUi)
end)

AddEventHandler('mono_core:characterSelected', function()
    SetTimeout(1500, removeGtaMoneyUi)
end)

CreateThread(function()
    local wasPauseMenuActive = false
    local lastEnforceAt = 0

    while true do
        HideHudComponentThisFrame(3)
        HideHudComponentThisFrame(4)

        local pauseMenuActive = IsPauseMenuActive()
        local now = GetGameTimer()

        if (pauseMenuActive and not wasPauseMenuActive) or now - lastEnforceAt >= 5000 then
            removeGtaMoneyUi()
            lastEnforceAt = now
        end

        wasPauseMenuActive = pauseMenuActive
        Wait(0)
    end
end)

