Spawn = {}

local PREFIX = '[MONO_CORE]'

local MALE_MODEL = 'mp_m_freemode_01'
local FEMALE_MODEL = 'mp_f_freemode_01'

local MALE_HASH = joaat(MALE_MODEL)
local FEMALE_HASH = joaat(FEMALE_MODEL)

local FEMALE_HEAD_PARENT = 21
local HEAD_BLEND_TIMEOUT_MS = 5000

local FADE_TIMEOUT_MS = 3000
local FALL_WATCHDOG_MS = 8000
local FALL_DISTANCE = 40.0

local function Log(message)
    print(('%s %s'):format(PREFIX, message))
end

local function WaitFor(condition, timeout)
    local deadline = GetGameTimer() + timeout

    while not condition() do
        if GetGameTimer() >= deadline then
            return false
        end

        Wait(50)
    end

    return true
end

local function FadeOut(ms)
    DoScreenFadeOut(ms)

    if not WaitFor(IsScreenFadedOut, FADE_TIMEOUT_MS) then
        Log('Timeout przyciemniania ekranu - kontynuuje.')
    end
end

local function FadeIn(ms)
    DoScreenFadeIn(ms)

    if not WaitFor(IsScreenFadedIn, FADE_TIMEOUT_MS + ms) then
        Log('Timeout rozjasniania ekranu - kontynuuje.')
    end
end

local function PlacePed(ped, spawn)
    SetEntityCoordsNoOffset(ped, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(ped, spawn.heading or 0.0)
end

local function ResetSpawnPresentation()
    RenderScriptCams(false, false, 0, true, false)
    DestroyAllCams(true)
    ClearFocus()
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    SetNuiFocus(false, false)
end

local function Recover(playerId)
    local ped = PlayerPedId()

    if ped ~= 0 and DoesEntityExist(ped) then
        FreezeEntityPosition(ped, false)
    end

    SetPlayerControl(playerId, true, 0)

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    ResetSpawnPresentation()
    DoScreenFadeIn(500)
end

local function ResolveModel(character, appearance)
    if appearance and type(appearance.model) == 'string' and appearance.model ~= '' then
        return appearance.model
    end

    if character and character.gender == 'female' then
        return FEMALE_MODEL
    end

    return MALE_MODEL
end

local function LoadPlayerModel(model)
    local modelHash = type(model) == 'number' and model or joaat(model)

    if not IsModelInCdimage(modelHash) or not IsModelValid(modelHash) then
        Log(('Nieprawidlowy model gracza: %s'):format(tostring(model)))
        return false
    end

    Log(('Ladowanie modelu: %s'):format(tostring(model)))

    RequestModel(modelHash)

    local loaded = WaitFor(function()
        return HasModelLoaded(modelHash)
    end, Config.Spawn.ModelTimeout or 10000)

    if not loaded then
        Log(('Timeout ladowania modelu: %s'):format(tostring(model)))
        return false
    end

    SetPlayerModel(PlayerId(), modelHash)
    SetModelAsNoLongerNeeded(modelHash)

    Wait(100)

    local ped = PlayerPedId()

    Log(('Model zaladowany. Ped: %s | Model hash: %s'):format(
        tostring(ped),
        tostring(GetEntityModel(ped))
    ))

    return true
end

local function SetupFreemodePed(ped, appearance)
    local model = GetEntityModel(ped)

    if model ~= MALE_HASH and model ~= FEMALE_HASH then
        return
    end

    local parent = model == FEMALE_HASH and FEMALE_HEAD_PARENT or 0

    SetPedDefaultComponentVariation(ped)
    SetPedHeadBlendData(ped, parent, parent, 0, parent, parent, 0, 0.0, 0.0, 0.0, false)

    local finished = WaitFor(function()
        return HasPedHeadBlendFinished(ped)
    end, HEAD_BLEND_TIMEOUT_MS)

    if not finished then
        Log('Timeout head blend dla peda freemode.')
    end

    -- Wyglad postaci z mono_appearance (musi byc PO SetPlayerModel i domyslnym head blend).
    if appearance and type(appearance.appearance) == 'table' then
        local ok, result = pcall(function()
            return exports.mono_appearance:ApplyToPed(ped, appearance.appearance)
        end)

        if not ok or not result then
            Log(('Nie udalo sie nalozyc appearance: %s'):format(tostring(result)))
        end
    end
end

local function LoadCollision(x, y, z)
    local loaded = WaitFor(function()
        RequestCollisionAtCoord(x, y, z)

        return HasCollisionLoadedAroundEntity(PlayerPedId())
    end, Config.Spawn.CollisionTimeout or 10000)

    if not loaded then
        Log('Timeout ladowania collision.')
    end

    return loaded
end

local function ResolveSpawn(character)
    local config = Config.Spawn

    if config.RestoreLastPosition and type(character) == 'table' then
        local x = tonumber(character.last_x)
        local y = tonumber(character.last_y)
        local z = tonumber(character.last_z)

        if x and y and z and z > -200.0 and z < 2500.0 then
            return {
                x = x,
                y = y,
                z = z,
                heading = tonumber(character.last_heading) or 0.0
            }, true
        end
    end

    return config.Default, false
end

local function StartFallWatchdog(spawn)
    CreateThread(function()
        local deadline = GetGameTimer() + FALL_WATCHDOG_MS

        while GetGameTimer() < deadline do
            Wait(250)

            local ped = PlayerPedId()

            if GetEntityCoords(ped).z < spawn.z - FALL_DISTANCE then
                local fallback = Config.Spawn.Default

                Log('Wykryto upadek pod mape po spawnie - przenosze do punktu domyslnego.')

                RequestCollisionAtCoord(fallback.x, fallback.y, fallback.z)
                SetEntityVelocity(ped, 0.0, 0.0, 0.0)
                SetEntityCoordsNoOffset(ped, fallback.x, fallback.y, fallback.z, false, false, false)
                SetEntityHeading(ped, fallback.heading or 0.0)

                return
            end
        end
    end)
end

local function Run(character, appearance)
    local config = Config.Spawn
    local spawn, restored = ResolveSpawn(character)

    if not spawn then
        Log('Brak domyslnej konfiguracji spawnu.')
        return false
    end

    local playerId = PlayerId()
    local heading = spawn.heading or 0.0
    local spawnModel = ResolveModel(character, appearance)

    Log(('Wybrany model dla postaci %s: %s'):format(
        character and ('%s %s'):format(character.first_name, character.last_name) or 'unknown',
        spawnModel
    ))

    Log(restored and 'Spawn w ostatniej zapisanej pozycji.' or 'Spawn domyslny (lotnisko).')
    Log(('Punkt spawnu: X %.3f | Y %.3f | Z %.3f | Heading %.1f'):format(
        spawn.x,
        spawn.y,
        spawn.z,
        heading
    ))
    Log('Rozpoczynam przygotowanie spawnu.')

    ResetSpawnPresentation()

    FadeOut(config.FadeOutTime or 500)

    SetPlayerControl(playerId, false, 0)

    Log('Laduje model gracza.')

    if not LoadPlayerModel(spawnModel) then
        Log('Nie udalo sie zaladowac modelu gracza.')

        Recover(playerId)

        return false
    end

    local ped = PlayerPedId()

    PlacePed(ped, spawn)

    NetworkResurrectLocalPlayer(spawn.x, spawn.y, spawn.z, heading, true, false)

    Wait(100)

    ped = PlayerPedId()

    Log(('Ped po NetworkResurrectLocalPlayer: %s'):format(tostring(ped)))

    SetupFreemodePed(ped, appearance)

    ClearPedTasksImmediately(ped)
    RemoveAllPedWeapons(ped, true)
    PlacePed(ped, spawn)

    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    SetEntityCollision(ped, true, true)

    FreezeEntityPosition(ped, true)

    Log('Laduje collision.')

    local collisionLoaded = LoadCollision(spawn.x, spawn.y, spawn.z)
    local usedFallback = false

    if restored and not collisionLoaded then
        Log('Kolizja w zapisanej pozycji sie nie zaladowala - spawn awaryjny w punkcie domyslnym.')

        spawn = config.Default
        heading = spawn.heading or 0.0
        usedFallback = true

        PlacePed(ped, spawn)
        LoadCollision(spawn.x, spawn.y, spawn.z)
    end

    FreezeEntityPosition(ped, false)
    SetPlayerControl(playerId, true, 0)

    Log(('Ped gotowy. Visible: %s | Alpha: %s | Collision: %s'):format(
        tostring(IsEntityVisible(ped)),
        tostring(GetEntityAlpha(ped)),
        tostring(GetEntityCollisionDisabled(ped) == false)
    ))

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    ResetSpawnPresentation()

    FadeIn(config.FadeInTime or 1000)

    if restored and not usedFallback then
        StartFallWatchdog(spawn)
    end

    Log('Spawn gracza zakonczony.')

    return true
end

function Spawn.Initialize(character, appearance)
    local ok, result = pcall(Run, character, appearance)

    if not ok then
        Log(('^1BLAD spawnu:^7 %s'):format(tostring(result)))

        Recover(PlayerId())

        return false
    end

    return result == true
end