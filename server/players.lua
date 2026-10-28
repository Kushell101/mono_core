MonoPlayers = {}

local PREFIX = '[MONO_CORE]'

local pending = {}

local function Log(message)
    print(('%s %s'):format(PREFIX, message))
end

function GetMonoPlayer(source)
    return MonoPlayers[tonumber(source)]
end

function GetPlayerLicense(source)
    return GetPlayerIdentifierByType(source, 'license')
end

local function UpsertPlayer(name, license)
    local ok, result = pcall(function()
        return MySQL.insert.await(
            [[
                INSERT INTO players (license, name)
                VALUES (?, ?)
                ON DUPLICATE KEY UPDATE
                    id = LAST_INSERT_ID(id),
                    name = VALUES(name),
                    last_seen = CURRENT_TIMESTAMP
            ]],
            { license, name }
        )
    end)

    if not ok then
        Log(('Blad SQL podczas rejestracji gracza: %s'):format(tostring(result)))
        return nil
    end

    local playerId = tonumber(result)

    if not playerId or playerId < 1 then
        return nil
    end

    return playerId
end

local function CreatePlayer(source)
    local name = GetPlayerName(source)

    if not name then
        return nil, 'player_not_found'
    end

    local license = GetPlayerLicense(source)

    if not license then
        Log(('Nie znaleziono license dla gracza %s.'):format(name))
        return nil, 'license_not_found'
    end

    if not WaitForMigrations() then
        Log(('Baza danych nie jest gotowa - nie zarejestrowano gracza %s.'):format(name))
        return nil, 'database_error'
    end

    local playerId = UpsertPlayer(name, license)

    if not playerId then
        return nil, 'database_error'
    end

    if GetPlayerName(source) ~= name or GetPlayerLicense(source) ~= license then
        Log(('Gracz %s [%s] opuscil serwer podczas rejestracji.'):format(name, source))
        return nil, 'player_left'
    end

    local player = {
        id = playerId,
        source = source,
        name = name,
        license = license
    }

    MonoPlayers[source] = player

    Log(('Gracz zarejestrowany: %s [%s] | DB ID: %s'):format(name, source, playerId))

    return player
end

function RegisterMonoPlayer(source)
    source = tonumber(source)

    if not source then
        return nil, 'invalid_source'
    end

    local existing = MonoPlayers[source]

    if existing then
        if existing.license == GetPlayerLicense(source) then
            return existing
        end

        MonoPlayers[source] = nil
    end

    if pending[source] then
        local result = Citizen.Await(pending[source])

        return result.player, result.errorCode
    end

    local registration = promise.new()

    pending[source] = registration

    local ok, player, errorCode = pcall(CreatePlayer, source)

    if not ok then
        Log(('Nieoczekiwany blad rejestracji gracza %s: %s'):format(source, tostring(player)))
        player, errorCode = nil, 'database_error'
    end

    pending[source] = nil
    registration:resolve({ player = player, errorCode = errorCode })

    return player, errorCode
end

function UnregisterMonoPlayer(source)
    source = tonumber(source)

    if not source then
        return
    end

    local player = MonoPlayers[source]

    if not player then
        return
    end

    local ok, result = pcall(function()
        return MySQL.update.await(
            'UPDATE players SET last_seen = CURRENT_TIMESTAMP WHERE id = ?',
            { player.id }
        )
    end)

    if not ok then
        Log(('Blad aktualizacji last_seen dla gracza %s [%s]: %s'):format(
            player.name,
            source,
            tostring(result)
        ))
    end

    Log(('Gracz opuscil serwer: %s [%s]'):format(player.name, source))

    MonoPlayers[source] = nil
end