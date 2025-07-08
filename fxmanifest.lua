fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'tss-fakesql'
author 'TinySpriteScripts'
version '1.0.0'

shared_scripts {
    'shared/config.lua',
    '@jim_bridge/starter.lua',
    'database/*.lua',
}

client_script {
    'client/main.lua'
}

server_script {
    'server/main.lua'
}

dependency 'jim_bridge'