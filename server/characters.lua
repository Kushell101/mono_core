MonoCharacters = {}

local PREFIX = '[MONO_CORE]'

local MIN_SLOT = Config.MinCharacterSlot or 1
local MAX_SLOT = Config.MaxCharacterSlots or 3

local VALID_GENDERS = {
    male = true,
    female = true
}

local DAYS_IN_MONTH = {
    31,
    28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31
}

local CHARACTER_COLUMNS = [[
    id,
    player_id,
    slot,
    first_name,
    last_name,
    DATE_FORMAT(date_of_birth, '%Y-%m-%d') AS date_of_birth,
    gender,
    created_at,
    last_played,
    last_x,
    last_y,
    last_z,
    last_heading
]]

local SELECT_CHARACTERS = 'SELECT ' .. CHARACTER_COLUMNS .. ' FROM characters '

local function Query(callback)
    local ok, result = pcall(callback)

    if not ok then
        print(('%s Blad SQL: %s'):format(
            PREFIX,
            tostring(result)
        ))

        return false, nil
    end

    return true, result
end

local function IsDuplicateEntryError(err)
    err = tostring(err)

    return err:find('Duplicate entry', 1, true) ~= nil
        or err:find('ER_DUP_ENTRY', 1, true) ~= nil
end

local function ToInteger(value)
    local number = tonumber(value)

    if not number then
        return nil
    end

    return math.tointeger(number)
end

local function IsValidSlot(slot)
    return type(slot) == 'number'
        and slot >= MIN_SLOT
        and slot <= MAX_SLOT
end

local function CleanString(value)
    if type(value) ~= 'string' then
        return nil
    end

    value = value:match('^%s*(.-)%s*$')

    if value == '' then
        return nil
    end

    return value
end

local function IsValidMonoDate(date)
    if type(date) ~= 'string' then
        return false
    end

    local year, month, day = date:match(
        '^(%d%d%d%d)%-(%d%d)%-(%d%d)$'
    )

    if not year then
        return false
    end

    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)

    if not year or not month or not day then
        return false
    end

    if month < 1 or month > 12 then
        return false
    end

    local maxDay = DAYS_IN_MONTH[month]

    local isLeapYear =
        year % 4 == 0
        and (year % 100 ~= 0 or year % 400 == 0)

    if month == 2 and isLeapYear then
        maxDay = 29
    end

    return day >= 1 and day <= maxDay
end

function GetMonoCharacters(playerId)
    playerId = ToInteger(playerId)

    if not playerId then
        return nil, 'invalid_player_id'
    end

    local ok, characters = Query(function()
        return MySQL.query.await(
            SELECT_CHARACTERS .. 'WHERE player_id = ? ORDER BY slot ASC',
            { playerId }
        )
    end)

    if not ok then
        return nil, 'database_error'
    end

    return characters or {}, nil
end

function GetMonoCharacter(characterId)
    characterId = ToInteger(characterId)

    if not characterId then
        return nil
    end

    local ok, character = Query(function()
        return MySQL.single.await(
            SELECT_CHARACTERS .. 'WHERE id = ? LIMIT 1',
            { characterId }
        )
    end)

    if not ok then
        return nil
    end

    return character
end

function CreateMonoCharacter(
    playerId,
    slot,
    firstName,
    lastName,
    dateOfBirth,
    gender
)
    playerId = ToInteger(playerId)
    slot = ToInteger(slot)

    if not playerId or not slot then
        return nil, 'invalid_arguments'
    end

    if not IsValidSlot(slot) then
        return nil, 'invalid_slot'
    end

    firstName = CleanString(firstName)
    lastName = CleanString(lastName)
    dateOfBirth = CleanString(dateOfBirth)
    gender = CleanString(gender)

    if not firstName
        or not lastName
        or not dateOfBirth
        or not gender
    then
        return nil, 'missing_data'
    end

    gender = gender:lower()

    if not VALID_GENDERS[gender] then
        return nil, 'invalid_gender'
    end

    if not IsValidMonoDate(dateOfBirth) then
        return nil, 'invalid_date'
    end

    local ok, existingCharacter = Query(function()
        return MySQL.single.await(
            [[
                SELECT id
                FROM characters
                WHERE player_id = ? AND slot = ?
                LIMIT 1
            ]],
            {
                playerId,
                slot
            }
        )
    end)

    if not ok then
        return nil, 'database_error'
    end

    if existingCharacter then
        return nil, 'slot_occupied'
    end

    local inserted, characterId = Query(function()
        return MySQL.insert.await(
            [[
                INSERT INTO characters (
                    player_id,
                    slot,
                    first_name,
                    last_name,
                    date_of_birth,
                    gender
                )
                VALUES (?, ?, ?, ?, ?, ?)
            ]],
            {
                playerId,
                slot,
                firstName,
                lastName,
                dateOfBirth,
                gender
            }
        )
    end)

    if not inserted then
        if IsDuplicateEntryError(characterId) then
            return nil, 'slot_occupied'
        end

        return nil, 'database_error'
    end

    if not characterId then
        return nil, 'database_error'
    end

    TriggerEvent('mono_core:characterCreated', characterId, playerId, slot)
    return characterId
end

function SelectMonoCharacter(playerSource, slot)
    playerSource = ToInteger(playerSource)
    slot = ToInteger(slot)

    if not playerSource or not slot then
        return nil, 'invalid_arguments'
    end

    if not IsValidSlot(slot) then
        return nil, 'invalid_slot'
    end

    local player = GetMonoPlayer(playerSource)

    if not player then
        return nil, 'player_not_found'
    end

    local ok, character = Query(function()
        return MySQL.single.await(
            SELECT_CHARACTERS ..
            'WHERE player_id = ? AND slot = ? LIMIT 1',
            {
                player.id,
                slot
            }
        )
    end)

    if not ok then
        return nil, 'database_error'
    end

    if not character then
        return nil, 'character_not_found'
    end

    local updated, affectedRows = Query(function()
        return MySQL.update.await(
            [[
                UPDATE characters
                SET last_played = CURRENT_TIMESTAMP
                WHERE id = ?
            ]],
            {
                character.id
            }
        )
    end)

    if not updated then
        return nil, 'database_error'
    end

    if not affectedRows then
        return nil, 'database_error'
    end

    character.last_played = os.date('%Y-%m-%d %H:%M:%S')

    player.activeCharacter = character

    return character
end

function DeleteMonoCharacter(playerId, characterId)
    playerId = ToInteger(playerId)
    characterId = ToInteger(characterId)

    if not playerId or not characterId then
        return false
    end

    local ok, affectedRows = Query(function()
        return MySQL.update.await(
            'DELETE FROM characters WHERE id = ? AND player_id = ?',
            { characterId, playerId }
        )
    end)

    return ok and (tonumber(affectedRows) or 0) > 0
end

function SaveMonoCharacterPosition(playerId, characterId, x, y, z, heading)
    playerId = ToInteger(playerId)
    characterId = ToInteger(characterId)

    if not playerId or not characterId then
        return false
    end

    local ok, err = pcall(function()
        MySQL.update(
            [[
                UPDATE characters
                SET last_x = ?, last_y = ?, last_z = ?, last_heading = ?
                WHERE id = ? AND player_id = ?
            ]],
            { x, y, z, heading, characterId, playerId }
        )
    end)

    if not ok then
        print(('%s Blad zapisu pozycji: %s'):format(PREFIX, tostring(err)))

        return false
    end

    return true
end
