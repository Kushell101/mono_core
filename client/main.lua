local NUI_READY_TIMEOUT_MS = 3000
local INIT_DELAY_MS = 700
local CHARACTERS_DELAY_MS = 400
local FAILURE_MESSAGE_MS = 1500
local APPEARANCE_TIMEOUT_MS = 10000

local STATE = {}

for _, name in ipairs({
    'CONNECTING',
    'LOADING_PLAYER',
    'LOADING_CHARACTERS',
    'CHARACTER_SELECT',
    'CHARACTER_CREATION',
    'CHARACTER_LOADING',
    'APPEARANCE_LOADING',
    'SPAWNING',
    'IN_GAME',
    'ERROR'
}) do
    STATE[name] = name
end

local Session = {
    state = STATE.CONNECTING,
    nuiReady = false,
    characters = {},
    character = nil,
    appearance = nil
}

local function Log(color, message)
    print(('^%s[MONO_CORE]^7 %s'):format(color, message))
end

local function SetSessionState(state)
    Session.state = state
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('mono_core_session', state, false)
    end
    TriggerEvent('mono_core:sessionStateChanged', state)
    Log('3', ('Session state: %s'):format(state))
end

local function SetNuiFocusState(enabled)
    SetNuiFocus(enabled, enabled)
end

local function SendNui(action, data)
    data = data or {}
    data.action = action

    SendNUIMessage(data)
end

local function SetLoadingText(text)
    SendNui('showLoading', { text = text })
end

local function ShowCharacterSelector(characters)
    Session.characters = characters or {}

    SendNui('showCharacters', { characters = Session.characters })
    SetNuiFocusState(true)
end

local function HideNui()
    SendNui('hide')
    SetNuiFocusState(false)
end

-- Przejscie do stanu ERROR: komunikat na ekranie + (opcjonalnie) log.
local function FailSession(text, reason)
    SetSessionState(STATE.ERROR)
    SetLoadingText(text)
    SetNuiFocusState(true)

    if reason then
        Log('1', reason)
    end
end

local POSITION_INTERVAL_MS = 10000
local POSITION_MIN_MOVE = 1.0

local trackingPosition = false

local function StartPositionTracking()
    if trackingPosition then
        return
    end

    trackingPosition = true

    CreateThread(function()
        local last

        while Session.state == STATE.IN_GAME do
            local ped = PlayerPedId()

            if DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)

                if not last or #(coords - last) >= POSITION_MIN_MOVE then
                    last = coords

                    TriggerServerEvent(
                        'mono_core:updatePosition',
                        coords.x,
                        coords.y,
                        coords.z,
                        GetEntityHeading(ped)
                    )
                end
            end

            Wait(POSITION_INTERVAL_MS)
        end

        trackingPosition = false
    end)
end

local function StartSession()
    if Session.state ~= STATE.CONNECTING then
        return
    end

    SetSessionState(STATE.LOADING_PLAYER)
    SetLoadingText('Ładowanie profilu gracza...')

    TriggerServerEvent('mono_core:requestCharacterData')
end

CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(100)
    end

    Log('2', 'Sieć GTA została uruchomiona.')

    SetSessionState(STATE.CONNECTING)
    SetNuiFocusState(true)

    local deadline = GetGameTimer() + NUI_READY_TIMEOUT_MS

    while not Session.nuiReady and GetGameTimer() < deadline do
        Wait(50)
    end

    if Session.nuiReady then
        Log('2', 'NUI zgłosiło gotowość.')
    else
        Log('3', 'NUI nie odpowiedziało w wymaganym czasie. Kontynuowanie przez timeout.')
    end

    SetLoadingText('Inicjalizowanie sesji...')

    Wait(INIT_DELAY_MS)

    StartSession()
end)

RegisterNetEvent('mono_core:characterData', function(characters)
    if Session.state ~= STATE.LOADING_PLAYER then
        return Log('3', ('Odrzucono dane postaci. Aktualny stan: %s'):format(Session.state))
    end

    SetSessionState(STATE.LOADING_CHARACTERS)
    SetLoadingText('Wczytywanie postaci...')

    Wait(CHARACTERS_DELAY_MS)

    SetSessionState(STATE.CHARACTER_SELECT)
    ShowCharacterSelector(characters)
end)

RegisterNetEvent('mono_core:characterSelected', function(character)
    if Session.state ~= STATE.CHARACTER_LOADING or type(character) ~= 'table' then
        return
    end

    Session.character = character
    Session.appearance = nil

    Log('2', ('Aktywna postać: %s %s | ID: %s | Slot: %s'):format(
        character.first_name,
        character.last_name,
        character.id,
        character.slot
    ))

    SetSessionState(STATE.APPEARANCE_LOADING)
    SetLoadingText('Przygotowywanie świata...')

    CreateThread(function()
        local deadline = GetGameTimer() + APPEARANCE_TIMEOUT_MS

        while Session.state == STATE.APPEARANCE_LOADING and GetGameTimer() < deadline do
            Wait(100)
        end

        if Session.state == STATE.APPEARANCE_LOADING then
            FailSession(
                'Nie udało się wczytać wyglądu postaci.',
                'Timeout ladowania appearance (czy mono_appearance jest uruchomione?).'
            )
        end
    end)
end)

RegisterNetEvent('mono_core:characterSelectionFailed', function(errorCode)
    Log('1', ('Błąd wyboru postaci: %s'):format(tostring(errorCode)))

    if Session.state == STATE.LOADING_PLAYER then
        return FailSession(errorCode == 'database_error'
            and 'Nie udało się połączyć z bazą danych.'
            or 'Nie udało się załadować profilu gracza.')
    end

    if Session.state ~= STATE.CHARACTER_LOADING then
        return
    end

    SetSessionState(STATE.CHARACTER_SELECT)
    SetLoadingText('Nie udało się załadować postaci.')
    SetNuiFocusState(true)

    Wait(FAILURE_MESSAGE_MS)

    if Session.state == STATE.CHARACTER_SELECT then
        ShowCharacterSelector(Session.characters)
    end
end)

AddEventHandler('mono_appearance:appearanceReady', function(data)
    if Session.state ~= STATE.APPEARANCE_LOADING then
        return Log('3', ('Odrzucono appearance. Aktualny stan: %s'):format(Session.state))
    end

    local reason

    if type(data) ~= 'table' then
        reason = 'Otrzymano nieprawidlowe dane appearance.'
    elseif not Session.character then
        reason = 'Brak aktywnej postaci podczas ladowania appearance.'
    elseif tonumber(data.characterId) ~= tonumber(Session.character.id) then
        reason = 'Appearance nie nalezy do aktualnie wybranej postaci.'
    end

    if reason then
        return FailSession('Nie udało się wczytać wyglądu postaci.', reason)
    end

    Session.appearance = data

    Log('2', ('Appearance zaladowane dla character ID: %s | Model: %s'):format(
        tostring(data.characterId),
        tostring(data.model)
    ))

    SetSessionState(STATE.SPAWNING)
    HideNui()

    if not Spawn.Initialize(Session.character, Session.appearance) then
        return FailSession('Nie udało się przygotować świata gry.', 'Spawn Manager zwrocil blad.')
    end

    SetSessionState(STATE.IN_GAME)
    StartPositionTracking()
    Log('2', 'Sesja gracza gotowa.')
end)

AddEventHandler('mono_appearance:appearanceFailed', function(errorCode)
    if Session.state ~= STATE.APPEARANCE_LOADING then
        return
    end

    FailSession(
        'Nie udało się wczytać wyglądu postaci.',
        ('Nie udalo sie zaladowac appearance: %s'):format(tostring(errorCode))
    )
end)

RegisterNUICallback('nuiReady', function(_, cb)
    Session.nuiReady = true

    cb({ success = true })
end)

RegisterNUICallback('selectCharacter', function(data, cb)
    if Session.state ~= STATE.CHARACTER_SELECT then
        return cb({ success = false, error = 'invalid_session_state' })
    end

    local slot = tonumber(data and data.slot)
    slot = slot and math.tointeger(slot)

    if not slot then
        return cb({ success = false, error = 'invalid_slot' })
    end

    SetSessionState(STATE.CHARACTER_LOADING)
    SetLoadingText('Ładowanie postaci...')
    SetNuiFocusState(false)

    TriggerServerEvent('mono_core:selectCharacter', slot)

    cb({ success = true })
end)

-- ---------------------------------------------------------------------
-- Kreator postaci (mono_creator)
-- ---------------------------------------------------------------------

RegisterNUICallback('createCharacter', function(data, cb)
    if Session.state ~= STATE.CHARACTER_SELECT then
        return cb({ success = false, error = 'invalid_session_state' })
    end

    local slot = tonumber(data and data.slot)
    slot = slot and math.tointeger(slot)

    if not slot or slot < (Config.MinCharacterSlot or 1) or slot > (Config.MaxCharacterSlots or 3) then
        return cb({ success = false, error = 'invalid_slot' })
    end

    for _, character in ipairs(Session.characters) do
        if tonumber(character.slot) == slot then
            return cb({ success = false, error = 'slot_occupied' })
        end
    end

    SetSessionState(STATE.CHARACTER_CREATION)
    HideNui()

    TriggerEvent('mono_creator:open', slot)

    cb({ success = true })
end)

AddEventHandler('mono_creator:closed', function(result)
    if Session.state ~= STATE.CHARACTER_CREATION then
        return
    end

    result = type(result) == 'table' and result or {}

    local slot = tonumber(result.slot)
    slot = slot and math.tointeger(slot)

    if result.created and slot and type(result.character) == 'table' then
        -- Nowa postac laduje sie dokladnie jak wybrana z listy.
        Session.characters[#Session.characters + 1] = result.character

        SetSessionState(STATE.CHARACTER_LOADING)
        SetLoadingText('Ładowanie postaci...')
        SetNuiFocusState(false)

        TriggerServerEvent('mono_core:selectCharacter', slot)

        return
    end

    SetSessionState(STATE.CHARACTER_SELECT)
    ShowCharacterSelector(Session.characters)
end)
