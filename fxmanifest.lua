fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Muhaddil'
description 'Simple Money Wash System'
version 'v1.0.3'

shared_script 'config.lua'

client_script {
    'client/*'
}

server_script {
    'server/*'
}

shared_script '@ox_lib/init.lua'

files {
    'locales/*.json'
}