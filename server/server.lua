ESX = exports['es_extended']:getSharedObject()

local webhookURL = "YOUR WEBHOOK URL HERE" -- Replace with your actual webhook URL

RegisterNetEvent('muhaddil-moneywash:checkId', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    local count = xPlayer.getInventoryItem(Config.itemname).count
    if count > 0 then
        xPlayer.removeInventoryItem(Config.itemname, 1)
        TriggerClientEvent('muhaddil-moneywash:getInput', source)
    else
        TriggerClientEvent('muhaddil-moneywash:notification', source, "Money Wash", "No tienes tarjeta de lavado",
            'error')
    end
end)

RegisterNetEvent('muhaddil-moneywash:washMoney')
AddEventHandler('muhaddil-moneywash:washMoney', function(percetageinput, originalinput)
    local xPlayer = ESX.GetPlayerFromId(source)
    local blackmoney = xPlayer.getAccount('black_money')
    if blackmoney.money >= originalinput then
        xPlayer.removeAccountMoney('black_money', originalinput)
        xPlayer.addAccountMoney('money', percetageinput)

        local embed = {
            {
                ["title"] = "💸 Lavado de Dinero", -- Title of the embed
                ["description"] = "Se ha registrado una operación de lavado de dinero.", -- Description of the embed
                ["color"] = 16711680, -- Color of the embed (red in this case)
                ["fields"] = { -- Fields of the embed
                    {
                        ["name"] = "ID del Jugador",
                        ["value"] = tostring(xPlayer.source),
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Nombre del Jugador",
                        ["value"] = xPlayer.getName() .. " (ID: " .. xPlayer.source .. ")",
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Dinero Negro Lavado",
                        ["value"] = "$" .. originalinput,
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Dinero Limpio Recibido",
                        ["value"] = "$" .. percetageinput,
                        ["inline"] = true
                    }
                },
                ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ"), 
            }
        }
                
        PerformHttpRequest(webhookURL, function(err, text, headers) end, 'POST', json.encode({ embeds = embed }), { ['Content-Type'] = 'application/json' })
    else
        xPlayer.addInventoryItem(Config.itemname, 1)
        return
    end
end)

RegisterNetEvent('muhaddil-moneywash:addCard', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    if Config.returnCard then
        xPlayer.addInventoryItem(Config.itemname, 1)
    end
end)

RegisterNetEvent('muhaddil-moneywash:checkBlackMoney', function(percetageinput, originalinput, time)
    local xPlayer = ESX.GetPlayerFromId(source)
    local blackmoney = xPlayer.getAccount('black_money')
    if blackmoney.money >= originalinput then
        TriggerClientEvent('muhaddil-moneywash:startProcess', source, percetageinput, originalinput, time)
    else
        TriggerClientEvent('muhaddil-moneywash:notification', source, "Money Wash", "No tienes suficiente dinero negro",
            'error')
    end
end)

local moneywashers = {}

local function loadMoneywashers()
    local file = LoadResourceFile(GetCurrentResourceName(), "moneywashers.json")
    if file then
        moneywashers = json.decode(file) or {}
        -- Ensure it's a table even if the file is empty or corrupt
        -- Ensure moneywashers is a table if the file doesn't exist or is empty
        if type(moneywashers) ~= 'table' then
            moneywashers = {}
        end
    else
        moneywashers = {}
    end
end

local function saveMoneywashers()
    SaveResourceFile(GetCurrentResourceName(), "moneywashers.json", json.encode(moneywashers, { indent = true }), -1)
end

local function sendMoneywashers(src)
    TriggerClientEvent('muhaddil-moneywash:setMoneywashers', src, moneywashers)
end

local function sendMoneywashersAll()
    for _, playerId in ipairs(GetPlayers()) do
        sendMoneywashers(tonumber(playerId))
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        loadMoneywashers()
        sendMoneywashersAll()
    end
end)

-- Add a callback to get the player's job
ESX.RegisterServerCallback('muhaddil-moneywash:getPlayerJob', function(src, cb)
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer then
        cb(xPlayer.job.name)
    else
        cb(nil)
    end
end)

-- Modify the addmoneywash command to accept an optional job
RegisterCommand('addmoneywash', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer and xPlayer.getGroup() == 'admin' then
        local ped = GetPlayerPed(source)
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        local job = args[1] -- optional job argument

        local newLocation = {
            coords = { coords.x, coords.y, coords.z },
            heading = heading
        }

        if job and job ~= '' then
            newLocation.job = job
        end

        table.insert(moneywashers, newLocation)
        saveMoneywashers()
        sendMoneywashersAll()
        TriggerClientEvent('ox_lib:notify', source,
            { description = 'Ubicación de lavado añadida' .. (job and job ~= '' and ' para el trabajo: ' .. job or ''), type =
            'success' })
    else
        TriggerClientEvent('ox_lib:notify', source,
            { description = 'No tienes permisos para usar este comando.', type = 'error' })
    end
end, false)

RegisterNetEvent('muhaddil-moneywash:requestMoneywashers', function()
    sendMoneywashers(source)
end)

RegisterNetEvent('muhaddil-moneywash:deleteMoneywasher', function(index)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer and xPlayer.getGroup() == 'admin' then
        if moneywashers[index] then
            table.remove(moneywashers, index)
            saveMoneywashers()
            sendMoneywashersAll()
        else
            -- Maybe you want to handle this case differently
        end
    end
end)

ESX.RegisterServerCallback('muhaddil-moneywash:isAdmin', function(src, cb, param1, param2)
    local xPlayer = ESX.GetPlayerFromId(src)
    cb(xPlayer.getGroup() == 'admin')
end)

RegisterNetEvent('muhaddil-moneywash:updateJob', function(index, newJob)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer.getGroup() == 'admin' and moneywashers[index] then
        moneywashers[index].job = newJob ~= '' and newJob or nil
        saveMoneywashers()
        sendMoneywashersAll()
    end
end)

RegisterNetEvent('muhaddil-moneywash:updateLocation', function(index, coords, heading)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer.getGroup() == 'admin' and moneywashers[index] then
        moneywashers[index].coords = { coords.x, coords.y, coords.z }
        moneywashers[index].heading = heading
        saveMoneywashers()
        sendMoneywashersAll()
    end
end)
