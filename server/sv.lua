local ESX = exports['es_extended']:getSharedObject()
local atms = {}
local actokens = {}
local takingcooldowns = {}
--local lore = exports.esx_identity:getlore(source)

local function gntoken(source, atmid)
    local token = string.format('%s_%s_%s', source, atmid, os.time())
    actokens[token] = {
        source = source,
        atmid = atmid,
        timestamp = os.time()
    }
    return token
end

local function gtpccnt()
    if ESX.GetExtendedPlayers then
       local count = 0
       local players = ESX.GetExtendedPlayers('job', {'police', 'sheriff', 'sahp'})
       return #players
    end
    
    local count = 0
    local xpls = ESX.GetExtendedPlayers()
    for _, xpl in pairs(xpls) do
        if xpl.job.name == 'police' or xpl.job.name == 'sheriff' or xpl.job.name == 'sahp' then
            count = count + 1
        end
    end
    return count
end

local function validatetoken(token, source, atmid)
    if not actokens[token] then return false end
    
    local tokendata = actokens[token]
    if tokendata.source ~= source or tokendata.atmid ~= atmid then
        return false
    end
    
    if os.time() - tokendata.timestamp > 300 then
        actokens[token] = nil
        return false
    end
    
    return true
end

local function invalidatetoken(token)
    actokens[token] = nil
end

local function cantake(source)
    local key = tostring(source)
    local time = os.time()
    
    if takingcooldowns[key] then
        local lasttake = time - takingcooldowns[key]
        if lasttake < (dnj.takingspeed / 1000) then
            return false
        end
    end
    
    takingcooldowns[key] = time
    return true
end

lib.callback.register('dnj_atmrobbery:canstart', function(source, atmid)
    local xpl = ESX.GetPlayerFromId(source)
    if not xpl then return false end
    
    local hasitem = exports.ox_inventory:Search(source, 'count', dnj.requireditem)
    if hasitem < 1 then
        TriggerClientEvent('ox_lib:notify', source, {
            description = 'Nemáš potřebný předmět: ' .. dnj.requireditem,
            type = 'error',
        })
        return false
    end

    local pds = gtpccnt()
    if pds < dnj.pdcount then
        TriggerClientEvent('ox_lib:notify', source, {
            description = 'Neni dostatek PDs online!',
            type = 'error'
        })
        return
    end
    
   --[[ local cando, reason = exports['dnj_illegaltablet']:canactivity(source, 'atm')
    if not cando then
        TriggerClientEvent('ox_lib:notify', source, {
            description = reason,
            type = 'error',
            icon = 'fa-ban'
        })
        return false
    end]]
    return true 
end)

lib.callback.register('dnj_atmrobbery:canrob', function(source, atmid)
    if not atms[atmid] then
        atms[atmid] = {
            robbed = 0,
            opened = false,
            totalmoney = 0,
            takemoney = 0,
            robbingplayer = nil
        }
    end
    
    local atm = atms[atmid]
    local time = os.time()
    local cooldown = dnj.globalcldwn * 60
    local tleft = (atm.robbed + cooldown) - time
    
    if tleft > 0 then
        return false, tleft
    end
    
    return true, 0
end)

lib.callback.register('dnj_atmrobbery:isatmopen', function(source, atmid)
    if not atms[atmid] then return false end
    return atms[atmid].opened
end)

lib.callback.register('dnj_atmrobbery:atmdata', function(source, atmid)
    if not atms[atmid] then
        atms[atmid] = {
            robbed = 0,
            opened = false,
            totalmoney = 0,
            takemoney = 0,
            robbingplayer = nil
        }
    end
    
    local atm = atms[atmid]
    local time = os.time()
    local cooldown = dnj.globalcldwn * 60
    local tleft = math.max(0, (atm.robbed + cooldown) - time)
    
    return {
        opened = atm.opened,
        totalmoney = atm.totalmoney,
        takemoney = atm.takemoney,
        tleft = tleft
    }
end)

lib.callback.register('dnj_atmrobbery:getremmoney', function(source, atmid)
    if not atms[atmid] then return 0 end
    local atm = atms[atmid]
    return atm.totalmoney - atm.takemoney
end)

lib.callback.register('dnj_atmrobbery:rqtake', function(source, atmid)
    if not atms[atmid] then return false end
    if not atms[atmid].opened then return false end
    if atms[atmid].takemoney >= atms[atmid].totalmoney then return false end
    
    if atms[atmid].robbingplayer and atms[atmid].robbingplayer ~= source then
        TriggerClientEvent('ox_lib:notify', source, {
            description = 'Nekdo jiny uz bere penize z tohoto ATM!',
            type = 'error'
        })
        return false
    end
    
    atms[atmid].robbingplayer = source
    
    return gntoken(source, atmid)
end)

lib.callback.register('dnj_atmrobbery:takemoney', function(source, atmid, amount, token)
    if not validatetoken(token, source, atmid) then
        return false
    end
    
    if not atms[atmid] then 
        return false 
    end
    local atm = atms[atmid]
    
    if not atm.opened then 
        return false 
    end
    if atm.takemoney >= atm.totalmoney then 
        return false 
    end
    
    if atm.robbingplayer ~= source then
        return false
    end
    
    local xpl = ESX.GetPlayerFromId(source)
    if not xpl then 
        return false 
    end
    
    if amount < 0 or amount > dnj.maxamt then
        return false
    end
    
    local amountactual = math.min(amount, atm.totalmoney - atm.takemoney)
    
    exports.ox_inventory:AddItem(source, 'money', amountactual)
    atm.takemoney = atm.takemoney + amountactual
    
    return true
end)

RegisterNetEvent('dnj_atmrobbery:hacksuccess', function(atmid)
    local source = source
    local xpl = ESX.GetPlayerFromId(source)
    if not xpl then return end
    
    local hasitem = exports.ox_inventory:Search(source, 'count', dnj.requireditem)
    if hasitem < 1 then
        return
    end
    
    exports.ox_inventory:RemoveItem(source, dnj.requireditem, 1)
    
    if not atms[atmid] then
        atms[atmid] = {
            robbed = 0,
            opened = false,
            totalmoney = 0,
            takemoney = 0,
            robbingplayer = nil
        }
    end
    
    local atm = atms[atmid]
    
 --   exports['dnj_illegaltablet']:zvysitlimit(source, 'atm')
    
    atm.opened = true
    atm.robbed = os.time()
    atm.totalmoney = math.random(dnj.minrw, dnj.maxrw)
    atm.takemoney = 0
    atm.robbingplayer = nil
    
    lib.notify(source, {
        description = 'ATM otevřen! Je tam asi $' .. atm.totalmoney,
        type = 'success'
    })
end)

RegisterNetEvent('dnj_atmrobbery:finishrob', function(atmid, token)
    local source = source
    
    if not validatetoken(token, source, atmid) then return end
    
    if atms[atmid] then
        atms[atmid].opened = false
        if atms[atmid].robbingplayer == source then
            atms[atmid].robbingplayer = nil
        end
    end
    invalidatetoken(token)
    
    local key = tostring(source)
    takingcooldowns[key] = nil
end)

AddEventHandler('playerDropped', function()
    local source = source
    local key = tostring(source)
    takingcooldowns[key] = nil
    
    for atmid, data in pairs(atms) do
        if data.robbingplayer == source then
            data.robbingplayer = nil
        end
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        
        local time = os.time()
        for token, data in pairs(actokens) do
            if time - data.timestamp > 300 then
                actokens[token] = nil
            end
        end
    end
end)