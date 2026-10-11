fx_version 'cerulean'
game 'gta5'
name 'Apex_WIPE'
author 'Apex'
description 'Wipe seletivo para MRI QBOX com plano, backup transacional e proteção de configurações'
version '1.0.6'

client_script 'client/main.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.server.lua',
    'server/planner.lua',
    'server/integrations.lua',
    'server/housing.lua',
    'server/automation.lua',
    'server/database.lua',
    'server/entities.lua',
    'server/maintenance.lua',
    'server/main.lua'
}
ui_page 'web/index.html'
files { 'web/index.html', 'web/styles.css', 'web/visibility.js', 'web/app.js' }
dependency 'oxmysql'
-- qbx_core não é dependência rígida: ele deve estar parado durante o wipe.
