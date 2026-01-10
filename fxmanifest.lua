fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Muhaddil'
description 'Money Wash System'
version 'v2.0.3'

shared_script 'config.lua'

client_scripts {
    'client/*'
}

server_scripts {
    'server/*',
}

shared_script '@ox_lib/init.lua'

ui_page 'html/index.html' -- Comment this line if you want to use the modified styling (Uncomment if you want to use the default)
-- ui_page 'html/index-plomolife.html' -- Uncomment if you want to use this styling (comment if you want to use the default)

files {
    'locales/*.json',
    'html/*'
}

dependencies {
    'es_extended',
    'ox_lib'
}
