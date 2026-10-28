local PREFIX = '[MONO_CORE][DB]'
local DEFAULT_WAIT_TIMEOUT_MS = 30000

local TABLE_OPTIONS = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'

local state = 'pending' -- 'pending' | 'ready' | 'failed'

-- ---------------------------------------------------------------------
-- Funkcje pomocnicze
-- ---------------------------------------------------------------------

local function Log(message)
    print(('%s %s'):format(PREFIX, message))
end

local function Exec(kind, sql, params)
    local ok, result = pcall(function()
        return MySQL[kind].await(sql, params or {})
    end)

    if not ok then
        Log(('Blad SQL: %s'):format(tostring(result)))
        return false, nil
    end

    return true, result
end

local function QuoteList(columns)
    return '`' .. table.concat(columns, '`, `') .. '`'
end

-- Dodaje kolumne, jesli jej brakuje.
local function EnsureColumn(tableName, column, definition)
    return function()
        local ok, count = Exec(
            'scalar',
            [[
                SELECT COUNT(*)
                FROM information_schema.columns
                WHERE table_schema = DATABASE()
                  AND table_name = ?
                  AND column_name = ?
            ]],
            { tableName, column }
        )

        if not ok then
            return false
        end

        if (tonumber(count) or 0) > 0 then
            return true
        end

        Log(('Dodaje kolumne %s.%s'):format(tableName, column))

        return (Exec('update', ('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, column, definition)))
    end
end

local function EnsureUniqueIndex(tableName, indexName, columns)
    return function()
        local ok, rows = Exec(
            'query',
            [[
                SELECT index_name AS name, column_name AS col, seq_in_index AS seq
                FROM information_schema.statistics
                WHERE table_schema = DATABASE()
                  AND table_name = ?
                  AND non_unique = 0
                ORDER BY index_name, seq_in_index
            ]],
            { tableName }
        )

        if not ok then
            return false
        end

        local indexes = {}

        for _, row in ipairs(rows or {}) do
            indexes[row.name] = indexes[row.name] or {}
            table.insert(indexes[row.name], row.col)
        end

        local wanted = table.concat(columns, ',')

        for _, indexColumns in pairs(indexes) do
            if table.concat(indexColumns, ',') == wanted then
                return true
            end
        end

        local list = QuoteList(columns)

        local duplicatesOk, duplicate = Exec(
            'single',
            ('SELECT %s, COUNT(*) AS c FROM `%s` GROUP BY %s HAVING c > 1 LIMIT 1'):format(list, tableName, list)
        )

        if not duplicatesOk then
            return false
        end

        if duplicate then
            Log(('Nie mozna dodac UNIQUE na %s (%s): w tabeli sa duplikaty. '
                .. 'Usun je recznie i zrestartuj mono_core.'):format(tableName, wanted))

            return false
        end

        Log(('Dodaje indeks UNIQUE %s na %s (%s)'):format(indexName, tableName, wanted))

        return (Exec('update', ('ALTER TABLE `%s` ADD UNIQUE KEY `%s` (%s)'):format(tableName, indexName, list)))
    end
end

local MIGRATIONS = {
    {
        version = 1,
        name = 'baseline_tables',
        steps = {
            ([[
                CREATE TABLE IF NOT EXISTS players (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    license VARCHAR(64) NOT NULL,
                    name VARCHAR(100) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    last_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_players_license (license)
                ) %s
            ]]):format(TABLE_OPTIONS),

            ([[
                CREATE TABLE IF NOT EXISTS characters (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    player_id INT UNSIGNED NOT NULL,
                    slot TINYINT UNSIGNED NOT NULL,
                    first_name VARCHAR(50) NOT NULL,
                    last_name VARCHAR(50) NOT NULL,
                    date_of_birth DATE NOT NULL,
                    gender VARCHAR(10) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    last_played TIMESTAMP NULL DEFAULT NULL,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_characters_player_slot (player_id, slot),
                    CONSTRAINT fk_characters_player
                        FOREIGN KEY (player_id) REFERENCES players (id) ON DELETE CASCADE
                ) %s
            ]]):format(TABLE_OPTIONS),

            ([[
                CREATE TABLE IF NOT EXISTS character_appearance (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    character_id INT UNSIGNED NOT NULL,
                    model VARCHAR(64) NOT NULL,
                    appearance LONGTEXT NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_character_appearance_character (character_id),
                    CONSTRAINT fk_character_appearance_character
                        FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
                ) %s
            ]]):format(TABLE_OPTIONS)
        }
    },

    {
        version = 2,
        name = 'ensure_columns',
        steps = {
            EnsureColumn('players', 'created_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP'),
            EnsureColumn('players', 'last_seen', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP'),

            EnsureColumn('characters', 'created_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP'),
            EnsureColumn('characters', 'last_played', 'TIMESTAMP NULL DEFAULT NULL'),

            EnsureColumn('character_appearance', 'created_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP'),
            EnsureColumn(
                'character_appearance',
                'updated_at',
                'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
            )
        }
    },

    {
        version = 3,
        name = 'unique_keys',
        steps = {
            EnsureUniqueIndex('players', 'uq_players_license', { 'license' }),
            EnsureUniqueIndex('characters', 'uq_characters_player_slot', { 'player_id', 'slot' }),
            EnsureUniqueIndex('character_appearance', 'uq_character_appearance_character', { 'character_id' })
        }
    },

    {
        version = 4,
        name = 'character_last_position',
        steps = {
            EnsureColumn('characters', 'last_x', 'DOUBLE NULL DEFAULT NULL'),
            EnsureColumn('characters', 'last_y', 'DOUBLE NULL DEFAULT NULL'),
            EnsureColumn('characters', 'last_z', 'DOUBLE NULL DEFAULT NULL'),
            EnsureColumn('characters', 'last_heading', 'DOUBLE NULL DEFAULT NULL')
        }
    }
}

-- ---------------------------------------------------------------------
-- Runner
-- ---------------------------------------------------------------------

local function RunMigrations()
    local created = Exec(
        'update',
        ([[
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INT UNSIGNED NOT NULL,
                name VARCHAR(100) NOT NULL,
                applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (version)
            ) %s
        ]]):format(TABLE_OPTIONS)
    )

    if not created then
        return false
    end

    local ok, rows = Exec('query', 'SELECT version FROM schema_migrations')

    if not ok then
        return false
    end

    local applied = {}

    for _, row in ipairs(rows or {}) do
        applied[tonumber(row.version)] = true
    end

    table.sort(MIGRATIONS, function(a, b)
        return a.version < b.version
    end)

    local appliedNow = 0

    for _, migration in ipairs(MIGRATIONS) do
        if not applied[migration.version] then
            Log(('Migracja %03d: %s'):format(migration.version, migration.name))

            for index, step in ipairs(migration.steps) do
                local stepOk

                if type(step) == 'function' then
                    stepOk = step()
                else
                    stepOk = (Exec('update', step))
                end

                if not stepOk then
                    Log(('Migracja %03d (%s) nie powiodla sie na kroku %d. Zatrzymano.'):format(
                        migration.version,
                        migration.name,
                        index
                    ))

                    return false
                end
            end

            local recorded = Exec(
                'update',
                'INSERT INTO schema_migrations (version, name) VALUES (?, ?)',
                { migration.version, migration.name }
            )

            if not recorded then
                return false
            end

            appliedNow = appliedNow + 1
        end
    end

    Log(('Schemat bazy jest aktualny (wykonane migracje: %d).'):format(appliedNow))

    return true
end

function WaitForMigrations(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or DEFAULT_WAIT_TIMEOUT_MS)

    while state == 'pending' and GetGameTimer() < deadline do
        Wait(50)
    end

    return state == 'ready'
end

function AreMigrationsReady()
    return state == 'ready'
end

CreateThread(function()
    MySQL.ready(function()
        local ok, result = pcall(RunMigrations)

        if not ok then
            Log(('Nieoczekiwany blad migracji: %s'):format(tostring(result)))
        end

        state = (ok and result) and 'ready' or 'failed'

        if state == 'failed' then
            Log('MIGRACJE NIE POWIODLY SIE - rejestracja graczy jest zablokowana do czasu naprawy.')
        end
    end)
end)