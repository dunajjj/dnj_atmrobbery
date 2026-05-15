local ESX = exports['es_extended']:getSharedObject()
local hacking = false
local taking = false
local fontid = RegisterFontId('Lexend')

local cached = {}
local acpoints = {}

local function loaddict(dict)
    if HasAnimDictLoaded(dict) then return end
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(10) end
end

local function getatmid(entity)
    local coords = GetEntityCoords(entity)
    return string.format("%.2f_%.2f_%.2f", coords.x, coords.y, coords.z)
end

local function drawtext(coords, text)
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    
    SetTextScale(0.35, 0.35)
    SetTextFont(fontid)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(1)
    AddTextComponentString(text)
    
    local factor = (string.len(text) / 370) * 1.5
    DrawRect(_x, _y + 0.0125, 0.02 + factor, 0.035, 0, 0, 0, 150)
    DrawText(_x, _y)
end

local function policealert()
    --[[
    local data = exports.dnj_dispatch:GetPlayerInfo()
    TriggerServerEvent('dnj_dispatch:server:AddNotification', {
        jobs = {'police', 'sheriff'}, 
        coords = data.coords,
        code = '10-90',
        title = 'Vykrádení ATM',
        info = 'Vykrádení ATM.',
        priority = 2, 
        isPanic = false,
        blip = {
            sprite = 521, 
            scale = 0.9, 
            colour = 44,
            text = '911 - Vykrádení ATM',
            time = 4 
        }
    })]]
end



local function starthacking(entity)
    if hacking then return end
    local atmid = getatmid(entity)
    
    local canstart = lib.callback.await('dnj_atmrobbery:canstart', false, atmid)
    if not canstart then return end
    
    local canrob, timeleft = lib.callback.await('dnj_atmrobbery:canrob', false, atmid)
    if not canrob then
        local minutes = math.floor(timeleft / 60)
        lib.notify({ description = 'Už tady někdo byl! Zkus to za ' .. minutes .. ' minút', type = 'error' })
        return
    end
    
    hacking = true
    loaddict('anim@heists@ornate_bank@hack')
    TaskPlayAnim(PlayerPedId(), 'anim@heists@ornate_bank@hack', 'hack_loop', 8.0, 8.0, -1, 1, 0, false, false, false)
    
    TriggerEvent("mhacking:show")
    TriggerEvent("mhacking:start", 7, 35, function(success)
        TriggerEvent('mhacking:hide')
        ClearPedTasks(PlayerPedId())
        
        if success then
            policealert()
            TriggerServerEvent('dnj_atmrobbery:hacksuccess', atmid)
            if cached[atmid] then cached[atmid].isopened = true end
        else
            policealert()
            lib.notify({ description = 'Sakra! Pokazil jsi to!', type = 'error' })
        end
        hacking = false
    end)
end

local function takecash(entity)
    if taking then return end
    local atmid = getatmid(entity)
    
    local token = lib.callback.await('dnj_atmrobbery:rqtake', false, atmid)
    if not token then
        lib.notify({ description = 'Něco se pokazilo.', type = 'error' })
        return
    end
    
    taking = true
    loaddict('anim@scripted@heist@ig1_table_grab@cash@male@')
    TaskPlayAnim(PlayerPedId(), 'anim@scripted@heist@ig1_table_grab@cash@male@', 'grab', 8.0, 8.0, -1, 1, 0, false, false, false)
    
    CreateThread(function()
        while taking do
            Wait(dnj.takingspeed) 
            if not taking then ClearPedTasks(PlayerPedId()) break end
            
            local remaining = lib.callback.await('dnj_atmrobbery:getremmoney', false, atmid)
            if cached[atmid] then cached[atmid].remaining = remaining end
            
            if remaining <= 0 then
                taking = false
                ClearPedTasks(PlayerPedId())
                lib.notify({ description = 'Vzal jsi všechny peníze z ATM.' })
                TriggerServerEvent('dnj_atmrobbery:finishrob', atmid, token)
                if cached[atmid] then cached[atmid].isopened = false end
                break
            end
            
            local amttake = math.random(dnj.minamt, dnj.maxamt)
            amttake = math.min(amttake, remaining)
            
            local success = lib.callback.await('dnj_atmrobbery:takecash', false, atmid, amttake, token)
            if not success then
                taking = false
                ClearPedTasks(PlayerPedId())
                lib.notify({ description = 'Něco se pokazilo.', type = 'error' })
                break
            end
            lib.notify({ description = 'Vzal jsi $' .. amttake, type = 'success' })
        end
    end)
end

RegisterCommand('stopatmrob', function()
    if taking then
        taking = false
        ClearPedTasks(PlayerPedId())
        lib.notify({ description = 'Přestal si brát peníze z ATM.', type = 'warning' })
    end
end)
RegisterKeyMapping('stopatmrob', 'Zastaviť ATM robbery', 'keyboard', 'G') -- 33


exports.ox_target:addModel(dnj.atmprops, {
    {
        name = 'hack_atm',
        icon = 'fas fa-laptop',
        label = 'Hacknout ATM',
        onSelect = function(data) starthacking(data.entity) end,
        canInteract = function(entity)
            if hacking or taking then return false end
            local atmid = getatmid(entity)

            if cached[atmid] and cached[atmid].isopened then return false end
            return true
        end
    },
    {
        name = 'take_money_atm',
        icon = 'fas fa-money-bill',
        label = 'Vzít peníze',
        onSelect = function(data) takecash(data.entity) end,
        canInteract = function(entity)
            if hacking or taking then return false end
            local atmid = getatmid(entity)
            if cached[atmid] and cached[atmid].isopened then return true end
            return false
        end
    }
})


CreateThread(function()
    while true do
        Wait(1500) 
        
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        
        for _, model in ipairs(dnj.atmprops) do
            local hash = GetHashKey(model)
            local object = GetClosestObjectOfType(coords, 10.0, hash, false, false, false)
            
            if object ~= 0 then
                local atmid = getatmid(object)
                
                if not acpoints[atmid] then
                    local obj = GetEntityCoords(object)
                    
                    local point = lib.points.new({
                        coords = obj,
                        distance = 4.0, 
                        atmid = atmid
                    })

                    function point:onEnter()
                        local data = lib.callback.await('dnj_atmrobbery:atmdata', false, self.atmid)
                        if data then
                            cached[self.atmid] = {
                                isopened = data.isopened,
                                remaining = data.totalmoney - data.takecash
                            }
                        end
                    end

                    function point:nearby()
                        local data = cached[self.atmid]
                        if data and data.isopened and data.remaining > 0 then
                            drawtext(vec3(self.coords.x, self.coords.y, self.coords.z + 1.2), string.format('~$~%d$', data.remaining)) -- ukazuje count v atm
                        end
                    end

                    acpoints[atmid] = point
                end
            end
        end
    end
end)