ESX = exports['es_extended']:getSharedObject()
local oxmysql = exports.oxmysql

local playerData = {}
local moneywashers = {}
local dailyLimits = {}

local function DebugPrint(printable)
    if Config.debug then
        print("[DEBUG] " .. tostring(printable))
    end
end

local function GetPlayerData(identifier)
    if playerData[identifier] then
        return playerData[identifier]
    end

    local result = oxmysql:executeSync(
        "SELECT * FROM moneywash_playerdata WHERE identifier = ?",
        { identifier }
    )

    if result[1] then
        playerData[identifier] = {
            totalWashed = result[1].totalWashed,
            totalTransactions = result[1].totalTransactions,
            successfulTransactions = result[1].successfulTransactions,
            failedTransactions = result[1].failedTransactions,
            reputation = result[1].reputation,
            history = json.decode(result[1].history or "[]"),
            lastWash = result[1].lastWash
        }
    else
        playerData[identifier] = {
            totalWashed = 0,
            totalTransactions = 0,
            successfulTransactions = 0,
            failedTransactions = 0,
            reputation = 0,
            history = {},
            lastWash = 0
        }

        oxmysql:execute(
            "INSERT INTO moneywash_playerdata (identifier, history) VALUES (?, ?)",
            { identifier, "[]" }
        )
    end

    return playerData[identifier]
end

local function GetDailyLimit(identifier)
    local today = os.date("%Y-%m-%d")

    if dailyLimits[identifier] then
        if dailyLimits[identifier].date ~= today then
            dailyLimits[identifier].date = today
            dailyLimits[identifier].amount = 0

            oxmysql:execute(
                "UPDATE moneywash_daily SET date = ?, amount = 0 WHERE identifier = ?",
                { today, identifier }
            )
        end
        return dailyLimits[identifier]
    end

    local result = oxmysql:querySync(
        "SELECT * FROM moneywash_daily WHERE identifier = ?",
        { identifier }
    )

    if result[1] then
        dailyLimits[identifier] = {
            date = result[1].date,
            amount = result[1].amount
        }

        if result[1].date ~= today then
            dailyLimits[identifier].date = today
            dailyLimits[identifier].amount = 0
            oxmysql:execute(
                "UPDATE moneywash_daily SET date = ?, amount = 0 WHERE identifier = ?",
                { today, identifier }
            )
        end
    else
        dailyLimits[identifier] = { date = today, amount = 0 }
        oxmysql:execute(
            "INSERT INTO moneywash_daily (identifier, date, amount) VALUES (?, ?, 0)",
            { identifier, today }
        )
    end

    return dailyLimits[identifier]
end

local function CanWash(identifier, amount)
    local data = GetPlayerData(identifier)
    local now = os.time()

    if Config.limits.cooldownTime > 0 then
        local timeSinceLastWash = now - data.lastWash
        if timeSinceLastWash < Config.limits.cooldownTime then
            local remaining = Config.limits.cooldownTime - timeSinceLastWash
            return false, string.format("Debes esperar %d segundos", remaining)
        end
    end

    if Config.limits.dailyLimit > 0 then
        local dailyData = GetDailyLimit(identifier)
        if dailyData.amount + amount > Config.limits.dailyLimit then
            return false, string.format("Límite diario alcanzado ($%s/$%s)",
                dailyData.amount, Config.limits.dailyLimit)
        end
    end

    if not Config.IsValidAmount(amount) then
        return false, string.format("La cantidad debe estar entre $%s y $%s",
            Config.limits.minWashAmount, Config.limits.maxWashAmount)
    end

    return true
end

local function CalculateCommission(amount, method)
    local basePercentage = Config.GetCommissionPercentage()

    if Config.economy.volumeDiscount > 0 then
        local volumeBonus = math.floor(amount / 100000) * Config.economy.volumeDiscount
        volumeBonus = math.min(volumeBonus, Config.economy.maxVolumeDiscount)
        basePercentage = basePercentage - volumeBonus
    end

    return math.max(10, math.min(40, basePercentage))
end

local function CalculateSuccessChance(identifier, method)
    local data = GetPlayerData(identifier)
    local baseChance = 95

    local methodConfig = Config.washMethods[method]
    if methodConfig then
        baseChance = baseChance + methodConfig.successBonus
    end

    if Config.reputation.enabled then
        baseChance = baseChance + (data.reputation * Config.reputation.successBonusPerLevel / 10)
    end

    return math.max(0, math.min(100, baseChance))
end

local function GetReputationLevel(reputation)
    if not Config.reputation.enabled then return "N/A" end

    for _, level in ipairs(Config.reputation.levels) do
        if reputation >= level.min and reputation <= level.max then
            return level.name
        end
    end
    return "Desconocido"
end

local function UpdatePlayerStats(identifier, amount, success, method)
    local data = GetPlayerData(identifier)

    if success then
        data.totalWashed = data.totalWashed + amount
        data.successfulTransactions = data.successfulTransactions + 1

        if Config.reputation.enabled then
            local gain = math.random(Config.reputation.gainPerSuccess.min, Config.reputation.gainPerSuccess.max)
            data.reputation = math.min(100, data.reputation + gain)
        end

        if Config.limits.dailyLimit > 0 then
            local dailyData = GetDailyLimit(identifier)
            dailyData.amount = dailyData.amount + amount
        end
    else
        data.failedTransactions = data.failedTransactions + 1

        if Config.reputation.enabled then
            local loss = math.random(Config.reputation.lossPerFail.min, Config.reputation.lossPerFail.max)
            data.reputation = math.max(0, data.reputation - loss)
        end
    end

    data.totalTransactions = data.totalTransactions + 1
    data.lastWash = os.time()

    local successRate = 0
    if data.totalTransactions > 0 then
        successRate = math.floor((data.successfulTransactions / data.totalTransactions) * 100)
    end

    table.insert(data.history, 1, {
        amount = amount,
        cleanAmount = success and math.floor(amount * 0.75) or 0,
        success = success,
        method = method,
        time = os.date("%H:%M"),
        timestamp = os.time()
    })

    if #data.history > (Config.ui.maxHistoryEntries or 50) then
        table.remove(data.history)
    end

    oxmysql:execute(
        [[UPDATE moneywash_playerdata
    SET totalWashed = ?, totalTransactions = ?, successfulTransactions = ?,
        failedTransactions = ?, reputation = ?, lastWash = ?, history = ?
    WHERE identifier = ?]],
        {
            data.totalWashed,
            data.totalTransactions,
            data.successfulTransactions,
            data.failedTransactions,
            data.reputation,
            data.lastWash,
            json.encode(data.history),
            identifier
        }
    )

    return {
        totalWashed = data.totalWashed,
        totalTransactions = data.totalTransactions,
        successRate = successRate,
        reputation = data.reputation,
        reputationLevel = GetReputationLevel(data.reputation)
    }
end

local function SendDiscordLog(title, color, fields)
    if not Config.discord.enabled then return end
    if not Config.discord.webhookURL or Config.discord.webhookURL == "YOUR WEBHOOK URL HERE" then return end

    local embed = { {
        ["title"] = title,
        ["color"] = color,
        ["fields"] = fields,
        ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        ["footer"] = {
            ["text"] = "Money Wash System v2.0"
        }
    } }

    PerformHttpRequest(Config.discord.webhookURL, function(err, text, headers) end, 'POST',
        json.encode({ embeds = embed }),
        { ['Content-Type'] = 'application/json' })
end

local function NotifyPolice(playerId, amount, coords)
    if not Config.police.enabled then return end

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local xPlayers = ESX.GetPlayers()

    for i = 1, #xPlayers do
        local xTarget = ESX.GetPlayerFromId(xPlayers[i])
        if xTarget and xTarget.job then
            for _, job in ipairs(Config.police.jobs) do
                if xTarget.job.name == job then
                    TriggerClientEvent('muhaddil-moneywash:policeAlert', xPlayers[i], {
                        name = xPlayer.getName(),
                        amount = amount,
                        coords = coords,
                        blipDuration = Config.police.blipDuration,
                        blipConfig = Config.police.blip
                    })
                end
            end
        end
    end

    if Config.discord.enabled and Config.discord.logPoliceAlerts then
        SendDiscordLog(
            Config.discord.embeds.police.title,
            Config.discord.embeds.police.color,
            {
                {
                    ["name"] = "Jugador",
                    ["value"] = xPlayer.getName() .. " (ID: " .. playerId .. ")",
                    ["inline"] = true
                },
                {
                    ["name"] = "Cantidad",
                    ["value"] = "$" .. amount,
                    ["inline"] = true
                },
                {
                    ["name"] = "Ubicación",
                    ["value"] = string.format("%.2f, %.2f, %.2f", coords.x, coords.y, coords.z),
                    ["inline"] = false
                }
            }
        )
    end
end

ESX.RegisterServerCallback('muhaddil-moneywash:hasCard', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    local count = xPlayer.getInventoryItem(Config.itemname).count
    cb(count > 0)
end)

ESX.RegisterServerCallback('muhaddil-moneywash:checkBlackMoney', function(source, cb, amount)
    local xPlayer = ESX.GetPlayerFromId(source)
    local blackmoney = xPlayer.getAccount('black_money')
    cb(blackmoney.money >= amount)
end)

ESX.RegisterServerCallback('muhaddil-moneywash:isAdmin', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    local isAdmin = false
    for _, group in ipairs(Config.permissions.adminGroups) do
        if xPlayer.getGroup() == group then
            isAdmin = true
            break
        end
    end
    cb(isAdmin)
end)

ESX.RegisterServerCallback('muhaddil-moneywash:getWashMethods', function(source, cb)
    cb(Config.washMethods)
end)

ESX.RegisterServerCallback('muhaddil-moneywash:calculateWash', function(source, cb, amount, method)
    local xPlayer = ESX.GetPlayerFromId(source)
    local commission = CalculateCommission(amount, method)
    local cleanAmount = math.floor(amount * (100 - commission) / 100)
    local time = Config.GetWashTime(amount)
    local methodConfig = Config.washMethods[method] or Config.washMethods.standard

    time = math.floor(time * methodConfig.speedMultiplier)

    cb({
        cleanAmount = cleanAmount,
        commission = commission,
        time = time,
        methodName = methodConfig.name
    })
end)

RegisterNetEvent('muhaddil-moneywash:removeCard')
AddEventHandler('muhaddil-moneywash:removeCard', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    xPlayer.removeInventoryItem(Config.itemname, 1)
end)

RegisterNetEvent('muhaddil-moneywash:returnCard')
AddEventHandler('muhaddil-moneywash:returnCard', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    if Config.returnCard then
        xPlayer.addInventoryItem(Config.itemname, 1)
    end
end)

RegisterNetEvent('muhaddil-moneywash:startWash')
AddEventHandler('muhaddil-moneywash:startWash', function(amount, method)
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)

    if not xPlayer then return end

    local identifier = xPlayer.identifier
    local blackmoney = xPlayer.getAccount('black_money')

    local canWash, errorMsg = CanWash(identifier, amount)
    if not canWash then
        TriggerClientEvent('muhaddil-moneywash:showNotification', _source, errorMsg, 'error')
        return
    end

    if blackmoney.money < amount then
        TriggerClientEvent('muhaddil-moneywash:showNotification', _source, 'No tienes suficiente dinero negro', 'error')
        return
    end

    if Config.itemname and Config.itemname ~= '' then
        local card = xPlayer.getInventoryItem(Config.itemname)
        if not card or card.count <= 0 then
            TriggerClientEvent('muhaddil-moneywash:showNotification', _source, 'Necesitas una tarjeta de lavado', 'error')
            return
        end

        xPlayer.removeInventoryItem(Config.itemname, 1)
    end

    local commission = CalculateCommission(amount, method)
    local cleanAmount = math.floor(amount * (100 - commission) / 100)
    local washTime = Config.GetWashTime(amount)
    local methodConfig = Config.washMethods[method] or Config.washMethods.standard

    washTime = math.floor(washTime * methodConfig.speedMultiplier)

    TriggerClientEvent('muhaddil-moneywash:startWashProgress', _source, washTime)

    TriggerClientEvent('muhaddil-moneywash:showNotification', _source,
        string.format('Lavando $%s... Espera %ds', amount, washTime), 'info')

    SetTimeout(washTime * 1000, function()
        local xPlayerCheck = ESX.GetPlayerFromId(_source)
        if not xPlayerCheck then return end

        local blackmoneyCheck = xPlayerCheck.getAccount('black_money')

        if blackmoneyCheck.money < amount then
            TriggerClientEvent('muhaddil-moneywash:showNotification', _source,
                'No tienes suficiente dinero negro', 'error')
            return
        end

        local successChance = CalculateSuccessChance(identifier, method)
        local success = math.random(100) <= successChance

        xPlayerCheck.removeAccountMoney('black_money', amount)

        if success then
            xPlayerCheck.addAccountMoney('money', cleanAmount)

            local stats = UpdatePlayerStats(identifier, cleanAmount, true, method)
            TriggerClientEvent('muhaddil-moneywash:updateStats', _source, stats)
            TriggerClientEvent('muhaddil-moneywash:updateHistory', _source, GetPlayerData(identifier).history)

            TriggerClientEvent('muhaddil-moneywash:showNotification', _source,
                string.format('¡Lavado exitoso! Recibiste $%s', cleanAmount), 'success')

            if Config.effects.particles then
                TriggerClientEvent('muhaddil-moneywash:playEffect', _source)
            end

            if Config.effects.sounds then
                TriggerClientEvent('muhaddil-moneywash:playSound', _source, 'PICK_UP')
            end

            if Config.discord.enabled and Config.discord.logSuccess then
                SendDiscordLog(
                    Config.discord.embeds.success.title,
                    Config.discord.embeds.success.color,
                    {
                        {
                            ["name"] = "Jugador",
                            ["value"] = xPlayerCheck.getName() .. " (ID: " .. _source .. ")",
                            ["inline"] = true
                        },
                        {
                            ["name"] = "Método",
                            ["value"] = methodConfig.name,
                            ["inline"] = true
                        },
                        {
                            ["name"] = "Dinero Negro",
                            ["value"] = "$" .. amount,
                            ["inline"] = true
                        },
                        {
                            ["name"] = "Dinero Limpio",
                            ["value"] = "$" .. cleanAmount,
                            ["inline"] = true
                        },
                        {
                            ["name"] = "Comisión",
                            ["value"] = commission .. "%",
                            ["inline"] = true
                        },
                        {
                            ["name"] = "Reputación",
                            ["value"] = stats.reputation .. "/100 (" .. stats.reputationLevel .. ")",
                            ["inline"] = true
                        }
                    }
                )
            end

            if math.random(100) <= Config.police.alertChanceSuccess then
                local coords = GetEntityCoords(GetPlayerPed(_source))
                NotifyPolice(_source, amount, coords)
            end

            if Config.returnCard and Config.itemname and Config.itemname ~= '' then
                xPlayerCheck.addInventoryItem(Config.itemname, 1)
            end
        else
            local stats = UpdatePlayerStats(identifier, 0, false, method)
            TriggerClientEvent('muhaddil-moneywash:updateStats', _source, stats)
            TriggerClientEvent('muhaddil-moneywash:updateHistory', _source, GetPlayerData(identifier).history)

            TriggerClientEvent('muhaddil-moneywash:showNotification', _source,
                string.format('¡Operación fallida! Perdiste $%s', amount), 'error')

            if Config.effects.sounds then
                TriggerClientEvent('muhaddil-moneywash:playSound', _source, 'CHECKPOINT_MISSED')
            end

            if Config.discord.enabled and Config.discord.logFails then
                SendDiscordLog(
                    Config.discord.embeds.fail.title,
                    Config.discord.embeds.fail.color,
                    {
                        {
                            ["name"] = "Jugador",
                            ["value"] = xPlayerCheck.getName() .. " (ID: " .. _source .. ")",
                            ["inline"] = true
                        },
                        {
                            ["name"] = "Método",
                            ["value"] = methodConfig.name,
                            ["inline"] = true
                        },
                        {
                            ["name"] = "Dinero Perdido",
                            ["value"] = "$" .. amount,
                            ["inline"] = true
                        },
                        {
                            ["name"] = "Reputación",
                            ["value"] = stats.reputation .. "/100 (" .. stats.reputationLevel .. ")",
                            ["inline"] = true
                        }
                    }
                )
            end

            if math.random(100) <= Config.police.alertChanceFail then
                local coords = GetEntityCoords(GetPlayerPed(_source))
                NotifyPolice(_source, amount, coords)
            end

            if Config.returnCard and Config.itemname and Config.itemname ~= '' then
                xPlayerCheck.addInventoryItem(Config.itemname, 1)
            end
        end
    end)
end)

RegisterNetEvent('muhaddil-moneywash:completeLavado')
AddEventHandler('muhaddil-moneywash:completeLavado', function(amount, cleanAmount, method)
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    local blackmoney = xPlayer.getAccount('black_money')

    if not xPlayer then return end

    local identifier = xPlayer.identifier
    local canWash, errorMsg = CanWash(identifier, amount)

    if not canWash then
        TriggerClientEvent('muhaddil-moneywash:showNotification', _source, errorMsg, 'error')
        TriggerServerEvent('muhaddil-moneywash:returnCard')
        return
    end

    if blackmoney.money < amount then
        TriggerClientEvent('muhaddil-moneywash:showNotification', _source, 'No tienes suficiente dinero negro', 'error')
        TriggerServerEvent('muhaddil-moneywash:returnCard')
        return
    end

    local successChance = CalculateSuccessChance(identifier, method)
    local success = math.random(100) <= successChance

    if success then
        xPlayer.removeAccountMoney('black_money', amount)
        xPlayer.addAccountMoney('money', cleanAmount)

        local stats = UpdatePlayerStats(identifier, cleanAmount, true, method)
        TriggerClientEvent('muhaddil-moneywash:updateStats', _source, stats)
        TriggerClientEvent('muhaddil-moneywash:updateHistory', _source, GetPlayerData(identifier).history)

        if Config.effects.particles then
            TriggerClientEvent('muhaddil-moneywash:playEffect', _source)
        end

        if Config.effects.sounds then
            TriggerClientEvent('muhaddil-moneywash:playSound', _source, 'PICK_UP')
        end

        if Config.discord.enabled and Config.discord.logSuccess then
            SendDiscordLog(
                Config.discord.embeds.success.title,
                Config.discord.embeds.success.color,
                {
                    {
                        ["name"] = "Jugador",
                        ["value"] = xPlayer.getName() .. " (ID: " .. _source .. ")",
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Método",
                        ["value"] = Config.washMethods[method].name,
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Dinero Negro",
                        ["value"] = "$" .. amount,
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Dinero Limpio",
                        ["value"] = "$" .. cleanAmount,
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Reputación",
                        ["value"] = stats.reputation .. "/100 (" .. stats.reputationLevel .. ")",
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Total Lavado",
                        ["value"] = "$" .. stats.totalWashed,
                        ["inline"] = true
                    }
                }
            )
        end

        if math.random(100) <= Config.police.alertChanceSuccess then
            local coords = GetEntityCoords(GetPlayerPed(_source))
            NotifyPolice(_source, amount, coords)
        end
    else
        xPlayer.removeAccountMoney('black_money', amount)

        local stats = UpdatePlayerStats(identifier, 0, false, method)
        TriggerClientEvent('muhaddil-moneywash:updateStats', _source, stats)
        TriggerClientEvent('muhaddil-moneywash:updateHistory', _source, GetPlayerData(identifier).history)
        TriggerClientEvent('muhaddil-moneywash:showNotification', _source, '¡Operación fallida! Perdiste el dinero negro',
            'error')

        if Config.effects.sounds then
            TriggerClientEvent('muhaddil-moneywash:playSound', _source, 'CHECKPOINT_MISSED')
        end

        TriggerClientEvent('muhaddil-moneywash:washResult', _source, {
            success = false,
            cleanAmount = cleanAmount,
            method = method
        })

        if Config.discord.enabled and Config.discord.logFails then
            SendDiscordLog(
                Config.discord.embeds.fail.title,
                Config.discord.embeds.fail.color,
                {
                    {
                        ["name"] = "Jugador",
                        ["value"] = xPlayer.getName() .. " (ID: " .. _source .. ")",
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Dinero Perdido",
                        ["value"] = "$" .. amount,
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Reputación",
                        ["value"] = stats.reputation .. "/100 (" .. stats.reputationLevel .. ")",
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Método",
                        ["value"] = Config.washMethods[method].name,
                        ["inline"] = true
                    }
                }
            )
        end

        if math.random(100) <= Config.police.alertChanceFail then
            local coords = GetEntityCoords(GetPlayerPed(_source))
            NotifyPolice(_source, amount, coords)
        end
    end
end)

RegisterNetEvent('muhaddil-moneywash:requestStats')
AddEventHandler('muhaddil-moneywash:requestStats', function()
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer then return end

    local data = GetPlayerData(xPlayer.identifier)

    local successRate = 0
    if data.totalTransactions > 0 then
        successRate = math.floor((data.successfulTransactions / data.totalTransactions) * 100)
    end

    TriggerClientEvent('muhaddil-moneywash:updateStats', _source, {
        totalWashed = data.totalWashed,
        totalTransactions = data.totalTransactions,
        successRate = successRate,
        reputation = data.reputation,
        reputationLevel = GetReputationLevel(data.reputation)
    })

    TriggerClientEvent('muhaddil-moneywash:updateHistory', _source, data.history)
end)

local function loadMoneywashers()
    local file = LoadResourceFile(GetCurrentResourceName(), "moneywashers.json")
    if file then
        moneywashers = json.decode(file) or {}
        if type(moneywashers) ~= 'table' then
            moneywashers = {}
        end
    else
        moneywashers = {}
    end
    DebugPrint("Loaded " .. #moneywashers .. " moneywasher locations")
end

local function saveMoneywashers()
    SaveResourceFile(GetCurrentResourceName(), "moneywashers.json", json.encode(moneywashers, { indent = true }), -1)
    DebugPrint("Saved " .. #moneywashers .. " moneywasher locations")
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
        Wait(1000)
        sendMoneywashersAll()
        DebugPrint("Money Wash System Started")
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        saveMoneywashers()
        DebugPrint("Money Wash System Stopped - Data Saved")
    end
end)

RegisterNetEvent('muhaddil-moneywash:requestMoneywashers')
AddEventHandler('muhaddil-moneywash:requestMoneywashers', function()
    sendMoneywashers(source)
end)

RegisterNetEvent('muhaddil-moneywash:addMoneywasher')
AddEventHandler('muhaddil-moneywash:addMoneywasher', function(coords, heading, job)
    local xPlayer = ESX.GetPlayerFromId(source)
    local isAdmin = false
    for _, group in ipairs(Config.permissions.adminGroups) do
        if xPlayer and xPlayer.getGroup() == group then
            isAdmin = true
            break
        end
    end

    if isAdmin then
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
        DebugPrint("Added new moneywasher location")
    end
end)

RegisterNetEvent('muhaddil-moneywash:deleteMoneywasher')
AddEventHandler('muhaddil-moneywash:deleteMoneywasher', function(index)
    local xPlayer = ESX.GetPlayerFromId(source)
    local isAdmin = false
    for _, group in ipairs(Config.permissions.adminGroups) do
        if xPlayer and xPlayer.getGroup() == group then
            isAdmin = true
            break
        end
    end

    if isAdmin and moneywashers[index] then
        table.remove(moneywashers, index)
        saveMoneywashers()
        sendMoneywashersAll()
        DebugPrint("Deleted moneywasher location #" .. index)
    end
end)

RegisterNetEvent('muhaddil-moneywash:updateLocation')
AddEventHandler('muhaddil-moneywash:updateLocation', function(index, coords, heading)
    local xPlayer = ESX.GetPlayerFromId(source)
    local isAdmin = false
    for _, group in ipairs(Config.permissions.adminGroups) do
        if xPlayer and xPlayer.getGroup() == group then
            isAdmin = true
            break
        end
    end

    if isAdmin and moneywashers[index] then
        moneywashers[index].coords = { coords.x, coords.y, coords.z }
        moneywashers[index].heading = heading
        saveMoneywashers()
        sendMoneywashersAll()
        DebugPrint("Updated location #" .. index)
    end
end)

RegisterCommand(Config.commands.stats or 'moneywashinfo', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    if not Config.permissions.allowPlayerStats then
        local isAdmin = false
        for _, group in ipairs(Config.permissions.adminGroups) do
            if xPlayer.getGroup() == group then
                isAdmin = true
                break
            end
        end
        if not isAdmin then return end
    end

    local data = GetPlayerData(xPlayer.identifier)
    local successRate = 0
    if data.totalTransactions > 0 then
        successRate = math.floor((data.successfulTransactions / data.totalTransactions) * 100)
    end

    TriggerClientEvent('chat:addMessage', source, {
        color = { Config.markers.color.r, Config.markers.color.g, Config.markers.color.b },
        multiline = true,
        args = { "Money Wash", string.format(
            "^2Total Lavado: ^0$%s\n^2Transacciones: ^0%d\n^2Tasa de Éxito: ^0%d%%\n^2Reputación: ^0%d/100 (%s)",
            data.totalWashed,
            data.totalTransactions,
            successRate,
            data.reputation,
            GetReputationLevel(data.reputation)
        ) }
    })
end, false)

DebugPrint("Money Wash Server Enhanced with Full Config - Loaded Successfully")
