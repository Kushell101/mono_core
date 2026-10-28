fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Monoskrypt'
description 'Core framework for Monoskrypt RP'
version '1.0.0'

dependency 'oxmysql'

shared_script 'shared/config.lua'

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

client_scripts {
    'client/vehicle_controls.lua',
    'client/spawn.lua',
    'client/native_cash.lua',
    'client/police.lua',
    'client/zancudo.lua',
    'client/player_ids.lua',
    'client/main.lua'
}

server_script '@oxmysql/lib/MySQL.lua'

server_scripts {
    'server/migrations.lua',
    'server/players.lua',
    'server/characters.lua',
    'server/position.lua',
    'server/permissions.lua',
    'server/main.lua'
}
