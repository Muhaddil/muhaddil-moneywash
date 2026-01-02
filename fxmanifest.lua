fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Muhaddil'
description 'Money Wash System'
version 'v2.0.2'

shared_script 'config.lua'

client_scripts {
    'client/*'
}

server_scripts {
    'server/*',
}

shared_script '@ox_lib/init.lua'

ui_page 'html/index.html'

files {
    'locales/*.json',
    'html/*'
}

dependencies {
    'es_extended',
    'ox_lib'
}
