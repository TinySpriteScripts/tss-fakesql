fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'tss-fakesql'
author 'TinySpriteScripts'
version '1.1.0'

shared_scripts {
    'shared/*.lua',
    '@jim_bridge/starter.lua',
}

client_script {
    'client/*.lua'
}

server_script {
    'database/*.lua',
    'server/*.lua',
}

dependency 'jim_bridge'
