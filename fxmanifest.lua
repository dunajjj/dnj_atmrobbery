fx_version 'cerulean'
game 'gta5'

author 'dnj'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts {
   -- '@dnj_sydo/protect.lua',
    'client/*.lua',
}

server_scripts {
   -- '@dnj_sydo/protect.lua',
    'server/*.lua',
}

dependencies {
    'mhacking', -- https://docs.fivem.net/docs/scripting-reference/resource-manifest/
}

lua54 'on'
