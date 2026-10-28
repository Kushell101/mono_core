local PREFIX = '[MONO_CORE]'
local LINE = ('='):rep(40)

local MIN_SLOT = Config.MinCharacterSlot or 1
local MAX_SLOT = Config.MaxCharacterSlots or 3

local SLOT_RANGE_MESSAGE = (
    'Slot musi znajdowac sie w zakresie %d-%d.'
):format(
    MIN_SLOT,
    MAX_SLOT
)

local CHAT_FEEDBACK = true
local NET_COOLDOWN_MS = 500

local DAYS_IN_MONTH = {
    31, 28, 31, 30, 31, 30,
    31, 31, 30, 31, 30, 31
}

local ERRORS = {
    slot_occupied = 'Slot %s jest juz zajety.',
    invalid_gender = 'Plec musi byc: male albo female.',
    invalid_date = 'Nieprawidlowa data urodzenia.',
    missing_data = 'Brakuje danych postaci.',
    invalid_arguments = 'Nieprawidlowe argumenty.',
    invalid_slot = SLOT_RANGE_MESSAGE,

    player_not_found = 'Nie znaleziono gracza.',
    character_not_found = 'Nie znaleziono postaci w slocie %s.',

    database_error = 'Wystapil blad bazy danych.'
}

local lastCall = {} -- [src] = { [nazwaEventu] = czas }


local function Log(message)
    print(
        ('%s %s'):format(
            PREFIX,
            message
        )
    )
end


local function SendChat(src, message)
    if not CHAT_FEEDBACK or not src or src <= 0 then
        return
    end

    TriggerClientEvent(
        'chat:addMessage',
        src,
        {
            color = { 255, 170, 0 },
            multiline = true,
            args = {
                'MONO',
                message
            }
        }
    )
end


-- Krotki komunikat: konsola serwera + czat gracza.
local function Notify(src, message)
    Log(message)
    SendChat(src, message)
end


local function PrintBlock(title, lines, src)
    local header = (
        '%s %s'
    ):format(
        PREFIX,
        title
    )

    local body = table.concat(
        lines,
        '\n'
    )

    print(
        table.concat(
            {
                LINE,
                header,
                LINE,
                body,
                LINE
            },
            '\n'
        )
    )

    SendChat(
        src,
        header .. '\n' .. body
    )
end


local function NotifyError(src, errorCode, slot, fallback)
    local template = ERRORS[errorCode]

    if template then
        Notify(
            src,
            template:format(slot)
        )

        return
    end

    Notify(
        src,
        ('%s Blad: %s'):format(
            fallback,
            errorCode or 'unknown'
        )
    )
end


-- "1.5", "abc", nil -> nil
-- "2", "2.0", 2 -> 2
local function ToInteger(value)
    local number = tonumber(value)

    return number and math.tointeger(number)
end


local function IsValidSlot(slot)
    return type(slot) == 'number'
        and slot >= MIN_SLOT
        and slot <= MAX_SLOT
end


local function IsValidDate(date)
    local year, month, day = tostring(date):match(
        '^(%d%d%d%d)%-(%d%d)%-(%d%d)$'
    )

    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)

    if not (year and month and day) then
        return false
    end

    if month < 1 or month > 12 then
        return false
    end

    local isLeapFebruary =
        month == 2
        and year % 4 == 0
        and (
            year % 100 ~= 0
            or year % 400 == 0
        )

    local maxDay = DAYS_IN_MONTH[month]

    if isLeapFebruary then
        maxDay = maxDay + 1
    end

    return day >= 1 and day <= maxDay
end


local function CharacterLines(character)
    return {
        ('Character ID: %s'):format(
            character.id
        ),

        ('Player DB ID: %s'):format(
            character.player_id
        ),

        ('Slot: %s'):format(
            character.slot
        ),

        ('Imie: %s'):format(
            character.first_name
        ),

        ('Nazwisko: %s'):format(
            character.last_name
        ),

        ('Data urodzenia: %s'):format(
            character.date_of_birth
        ),

        ('Plec: %s'):format(
            character.gender
        )
    }
end


local function PlayerName(src)
    local player = GetMonoPlayer(src)

    return player
        and player.name
        or GetPlayerName(src)
        or 'unknown'
end


local function IsRateLimited(src, key)
    local calls = lastCall[src] or {}
    local now = GetGameTimer()

    lastCall[src] = calls

    if calls[key]
        and (now - calls[key]) < NET_COOLDOWN_MS
    then
        return true
    end

    calls[key] = now

    return false
end


local function RegisterMonoCommand(
    name,
    needsPlayer,
    handler
)
    RegisterCommand(
        name,
        function(rawSource, args)
            local src = tonumber(rawSource)

            if not src or src == 0 then
                return Log(
                    'Tej komendy nalezy uzywac w grze.'
                )
            end

            if not HasPermission(
                src,
                'command.' .. name
            ) then
                return Notify(
                    src,
                    'Brak uprawnien.'
                )
            end

            local player

            if needsPlayer then
                player = GetMonoPlayer(src)

                if not player then
                    return Notify(
                        src,
                        (
                            'Nie znaleziono gracza o source %s.'
                        ):format(src)
                    )
                end
            end

            handler(
                src,
                player,
                args
            )
        end,
        true
    )
end


AddEventHandler(
    'playerJoining',
    function()
        RegisterMonoPlayer(source)
    end
)


AddEventHandler(
    'playerDropped',
    function()
        local src = source

        SaveMonoPositionNow(src)

        UnregisterMonoPlayer(src)

        lastCall[src] = nil
    end
)


AddEventHandler(
    'onResourceStart',
    function(resourceName)
        if resourceName ~= GetCurrentResourceName() then
            return
        end

        Log(LINE)
        Log('Monoskrypt Core uruchomiony!')
        Log(LINE)

        local players = GetPlayers()

        Log(
            ('Wykryto %s aktywnych graczy.'):format(
                #players
            )
        )

        for _, playerSource in ipairs(players) do
            RegisterMonoPlayer(
                tonumber(playerSource)
            )
        end
    end
)


local function FailSelection(src, errorCode)
    TriggerClientEvent(
        'mono_core:characterSelectionFailed',
        src,
        errorCode
    )
end


RegisterNetEvent(
    'mono_core:requestCharacterData',
    function()
        local src = source

        if IsRateLimited(
            src,
            'requestCharacterData'
        ) then
            return
        end

        local player =
            GetMonoPlayer(src)
            or RegisterMonoPlayer(src)

        if not player then
            Log(
                (
                    'Nie mozna zaladowac profilu gracza %s.'
                ):format(src)
            )

            return FailSelection(
                src,
                'player_not_found'
            )
        end

        local characters, errorCode =
            GetMonoCharacters(player.id)

        if not characters then
            Log(
                (
                    'Nie mozna zaladowac postaci gracza %s [%s]. Blad: %s'
                ):format(
                    player.name,
                    src,
                    tostring(errorCode)
                )
            )

            return FailSelection(
                src,
                errorCode or 'database_error'
            )
        end

        TriggerClientEvent(
            'mono_core:characterData',
            src,
            characters
        )
    end
)


RegisterNetEvent(
    'mono_core:selectCharacter',
    function(slot)
        local src = source

        if IsRateLimited(
            src,
            'selectCharacter'
        ) then
            return
        end

        -- Walidacje slotu i gracza
        -- wykonuje SelectMonoCharacter().
        local character, errorCode =
            SelectMonoCharacter(
                src,
                slot
            )

        local name = PlayerName(src)

        if not character then
            Log(
                (
                    'Nie udalo sie wybrac postaci dla %s [%s]. Blad: %s'
                ):format(
                    name,
                    src,
                    tostring(errorCode)
                )
            )

            return FailSelection(
                src,
                errorCode
            )
        end

        Log(
            (
                'Gracz %s [%s] wybral postac: %s %s [ID: %s]'
            ):format(
                name,
                src,
                character.first_name,
                character.last_name,
                character.id
            )
        )

        TriggerClientEvent(
            'mono_core:characterSelected',
            src,
            character
        )
    end
)


RegisterMonoCommand(
    'monoinfo',
    true,
    function(src, player)
        local character = player.activeCharacter

        local lines = {
            ('Name: %s'):format(
                player.name
            ),

            ('Source: %s'):format(
                player.source
            ),

            character
                and (
                    'Active Character: %s %s [ID: %s]'
                ):format(
                    character.first_name,
                    character.last_name,
                    character.id
                )
                or 'Active Character: brak',

            'Identifiers:'
        }

        for _, identifier in ipairs(
            player.identifiers or {}
        ) do
            lines[#lines + 1] = (
                '  - %s'
            ):format(
                identifier
            )
        end

        PrintBlock(
            'INFORMACJE O GRACZU',
            lines,
            src
        )
    end
)


RegisterMonoCommand(
    'monochars',
    true,
    function(src, player)
        local characters, errorCode =
            GetMonoCharacters(player.id)

        if not characters then
            return NotifyError(
                src,
                errorCode or 'database_error',
                nil,
                'Nie udalo sie pobrac postaci.'
            )
        end

        local lines = {
            ('Player DB ID: %s'):format(
                player.id
            ),

            ('Liczba postaci: %s'):format(
                #characters
            )
        }

        for _, character in ipairs(
            characters
        ) do
            lines[#lines + 1] = (
                'Slot %s | ID %s | %s %s | %s | %s'
            ):format(
                character.slot,
                character.id,
                character.first_name,
                character.last_name,
                character.date_of_birth,
                character.gender
            )
        end

        PrintBlock(
            'POSTACIE GRACZA',
            lines,
            src
        )
    end
)


RegisterMonoCommand(
    'monocreate',
    true,
    function(src, player, args)
        local slot = ToInteger(args[1])

        local firstName = args[2]
        local lastName = args[3]
        local dateOfBirth = args[4]
        local gender = args[5]

        if not (
            slot
            and firstName
            and lastName
            and dateOfBirth
            and gender
        ) then
            Notify(
                src,
                'Uzycie: /monocreate [slot] [imie] [nazwisko] [data] [plec]'
            )

            return Notify(
                src,
                'Przyklad: /monocreate 1 Jan Kowalski 1995-05-20 male'
            )
        end

        if not IsValidSlot(slot) then
            return Notify(
                src,
                SLOT_RANGE_MESSAGE
            )
        end

        if not IsValidDate(dateOfBirth) then
            return Notify(
                src,
                'Podano nieprawidlowa date. Uzyj formatu RRRR-MM-DD, np. 1995-05-20.'
            )
        end

        gender = gender:lower()

        local characterId, errorCode =
            CreateMonoCharacter(
                player.id,
                slot,
                firstName,
                lastName,
                dateOfBirth,
                gender
            )

        if not characterId then
            return NotifyError(
                src,
                errorCode,
                slot,
                'Nie udalo sie utworzyc postaci.'
            )
        end

        PrintBlock(
            'UTWORZONO POSTAC',
            CharacterLines({
                id = characterId,
                player_id = player.id,
                slot = slot,
                first_name = firstName,
                last_name = lastName,
                date_of_birth = dateOfBirth,
                gender = gender
            }),
            src
        )
    end
)


RegisterMonoCommand(
    'monoselect',
    false,
    function(src, _, args)
        local slot = ToInteger(args[1])

        if not slot then
            return Notify(
                src,
                'Uzycie: /monoselect [slot]'
            )
        end

        if not IsValidSlot(slot) then
            return Notify(
                src,
                SLOT_RANGE_MESSAGE
            )
        end

        local character, errorCode =
            SelectMonoCharacter(
                src,
                slot
            )

        if not character then
            return NotifyError(
                src,
                errorCode,
                slot,
                'Nie udalo sie wybrac postaci.'
            )
        end

        PrintBlock(
            'AKTYWNA POSTAC',
            CharacterLines(character),
            src
        )
    end
)

exports('GetActiveCharacter', function(source)
    local player = GetMonoPlayer(source)

    if not player then
        return nil
    end

    return player.activeCharacter
end)

exports('CreateCharacter', function(source, slot, firstName, lastName, dateOfBirth, gender)
    local player = GetMonoPlayer(source)

    if not player then
        return { error = 'player_not_found' }
    end

    local characterId, errorCode = CreateMonoCharacter(
        player.id,
        slot,
        firstName,
        lastName,
        dateOfBirth,
        gender
    )

    if not characterId then
        return { error = errorCode or 'database_error' }
    end

    return { id = characterId }
end)

exports('GetCharacters', function(source)
    local player = GetMonoPlayer(source)

    if not player then
        return nil
    end

    local characters = GetMonoCharacters(player.id)

    return characters
end)

exports('DeleteCharacter', function(source, characterId)
    local player = GetMonoPlayer(source)

    if not player then
        return false
    end

    return DeleteMonoCharacter(player.id, characterId)
end)