ESX = exports['es_extended']:getSharedObject()
lib.locale()

local function DebugPrint(printable)
    if Config.debug then
        print("[DEBUG] " .. tostring(printable))
    end
end

DebugPrint("Money Wash System Loaded - Client Enhanced with Full Config")

local alreadymarker = false
local uiOpened = false
local playerJob = nil
local moneywashers = {}
local playerStats = {
    totalWashed = 0,
    totalTransactions = 0,
    successRate = 100,
    reputation = 0,
    reputationLevel = "Novato"
}
local transactionHistory = {}
local washMethods = {}
local activeBlips = {}

Citizen.CreateThread(function()
    while ESX == nil do
        Citizen.Wait(100)
    end
    local playerData = ESX.GetPlayerData()
    if playerData and playerData.job then
        playerJob = playerData.job.name
        DebugPrint("Job cargado al iniciar el script: " .. playerJob)
    else
        DebugPrint("No se pudo cargar el job al iniciar")
    end

    TriggerServerEvent('muhaddil-moneywash:requestStats')

    ESX.TriggerServerCallback('muhaddil-moneywash:getWashMethods', function(methods)
        washMethods = methods
        DebugPrint("Métodos de lavado cargados: " .. json.encode(methods))
    end)
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(playerData)
    DebugPrint("Player loaded: " .. json.encode(playerData))
    playerJob = playerData.job.name
    DebugPrint("Player job set to: " .. tostring(playerJob))
    TriggerServerEvent('muhaddil-moneywash:requestStats')
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
    DebugPrint("Job updated: " .. json.encode(job))
    playerJob = job.name
    DebugPrint("Player job changed to: " .. tostring(playerJob))
end)

local function SendUI(action, data)
    SendNUIMessage({
        action = action,
        data = data or {}
    })
end

local function OpenUI()
    if uiOpened then return end
    uiOpened = true
    SetNuiFocus(true, true)
    SendUI('openUI', {})
    SendUI('updateStats', playerStats)
    SendUI('updateHistory', transactionHistory)
    SendUI('updateLocations', moneywashers)
    SendUI('updateConfig', {
        limits = Config.limits,
        economy = Config.economy,
        reputation = Config.reputation
    })
    ESX.TriggerServerCallback('muhaddil-moneywash:isAdmin', function(isAdmin)
        SendUI('setAdminStatus', { isAdmin = isAdmin })
    end)
end


local function CloseUI()
    if not uiOpened then return end
    uiOpened = false
    SetNuiFocus(false, false)
end

RegisterNUICallback('closeUI', function(data, cb)
    CloseUI()
    cb('ok')
end)

RegisterNUICallback('teleportTo', function(data, cb)
    ESX.TriggerServerCallback('muhaddil-moneywash:isAdmin', function(isAdmin)
        if isAdmin then
            local location = moneywashers[data.index + 1]
            if location then
                local playerPed = PlayerPedId()
                SetEntityCoords(playerPed, location.coords[1], location.coords[2], location.coords[3] + 1.0, false, false,
                    false, true)
                SendUI('showNotification', {
                    message = 'Teletransportado exitosamente',
                    type = 'success'
                })
            end
        else
            SendUI('showNotification', {
                message = 'No tienes permisos',
                type = 'error'
            })
        end
    end)
    cb('ok')
end)

RegisterNUICallback('updateLocation', function(data, cb)
    ESX.TriggerServerCallback('muhaddil-moneywash:isAdmin', function(isAdmin)
        if isAdmin then
            local coords = GetEntityCoords(PlayerPedId())
            local heading = GetEntityHeading(PlayerPedId())
            TriggerServerEvent('muhaddil-moneywash:updateLocation', data.index + 1, coords, heading)
            SendUI('showNotification', {
                message = 'Ubicación actualizada',
                type = 'success'
            })
        else
            SendUI('showNotification', {
                message = 'No tienes permisos',
                type = 'error'
            })
        end
    end)
    cb('ok')
end)

RegisterNUICallback('deleteLocation', function(data, cb)
    ESX.TriggerServerCallback('muhaddil-moneywash:isAdmin', function(isAdmin)
        if isAdmin then
            TriggerServerEvent('muhaddil-moneywash:deleteMoneywasher', data.index + 1)
            SendUI('showNotification', {
                message = 'Ubicación eliminada',
                type = 'success'
            })
        else
            SendUI('showNotification', {
                message = 'No tienes permisos',
                type = 'error'
            })
        end
    end)
    cb('ok')
end)

RegisterNUICallback('startWash', function(data, cb)
    local amount = data.amount
    local method = data.method or 'standard'

    if not amount or amount <= 0 then
        SendUI('showNotification', {
            message = 'Cantidad inválida',
            type = 'error'
        })
        cb('error')
        return
    end

    ESX.TriggerServerCallback('muhaddil-moneywash:checkBlackMoney', function(hasEnough)
        if not hasEnough then
            SendUI('showNotification', {
                message = 'No tienes suficiente dinero negro',
                type = 'error'
            })
            cb('error')
            return
        end

        TriggerServerEvent('muhaddil-moneywash:startWash', amount, method)
        cb('ok')
    end, amount)
end)

RegisterNUICallback('openAdminView', function(data, cb)
    ESX.TriggerServerCallback('muhaddil-moneywash:isAdmin', function(isAdmin)
        if isAdmin then
            showView('admin')
        else
            SendUI('showNotification', {
                message = 'No tienes permisos de administrador',
                type = 'error'
            })
            CloseUI()
        end
    end)
    cb('ok')
end)

RegisterNUICallback('checkAdmin', function(data, cb)
    ESX.TriggerServerCallback('muhaddil-moneywash:isAdmin', function(isAdmin)
        cb({ isAdmin = isAdmin })
    end)
end)

RegisterNetEvent('muhaddil-moneywash:setMoneywashers', function(zones)
    DebugPrint("Received moneywash zones: " .. json.encode(zones))
    moneywashers = zones or {}
    if uiOpened then
        SendUI('updateLocations', moneywashers)
    end
end)

RegisterNetEvent('muhaddil-moneywash:showNotification')
AddEventHandler('muhaddil-moneywash:showNotification', function(message, type)
    if uiOpened then
        SendUI('showNotification', {
            message = message,
            type = type or 'info'
        })
    else
        lib.notify({
            title = locale('moneywash_title'),
            description = message,
            type = type or 'info'
        })
    end
end)

RegisterNetEvent('muhaddil-moneywash:policeAlert')
AddEventHandler('muhaddil-moneywash:policeAlert', function(data)
    if not Config.police.enabled then return end

    lib.notify({
        title = '🚨 Alerta Policial',
        description = string.format('Lavado de dinero detectado\\nSospechoso: %s\\nCantidad: $%s',
            data.name, data.amount),
        type = 'error',
        duration = 10000
    })

    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, data.blipConfig.sprite)
    SetBlipColour(blip, data.blipConfig.color)
    SetBlipScale(blip, data.blipConfig.scale)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(data.blipConfig.label)
    EndTextCommandSetBlipName(blip)

    table.insert(activeBlips, blip)

    Citizen.SetTimeout(data.blipDuration, function()
        RemoveBlip(blip)
        for i, b in ipairs(activeBlips) do
            if b == blip then
                table.remove(activeBlips, i)
                break
            end
        end
    end)
end)

RegisterNetEvent('muhaddil-moneywash:startWashProgress')
AddEventHandler('muhaddil-moneywash:startWashProgress', function(duration)
    if uiOpened then
        SendUI('startProgress', {
            duration = duration
        })
    end
end)

RegisterNetEvent('muhaddil-moneywash:updateStats')
AddEventHandler('muhaddil-moneywash:updateStats', function(stats)
    playerStats = stats
    if uiOpened then
        SendUI('updateStats', stats)
    end
end)

RegisterNetEvent('muhaddil-moneywash:updateHistory')
AddEventHandler('muhaddil-moneywash:updateHistory', function(history)
    transactionHistory = history
    if uiOpened then
        SendUI('updateHistory', history)
    end
end)

Citizen.CreateThread(function()
    DebugPrint("Requesting moneywash zones from server")
    TriggerServerEvent('muhaddil-moneywash:requestMoneywashers')
end)

Citizen.CreateThread(function()
    while playerJob == nil do
        Wait(100)
    end

    local TextUIShown = false

    while true do
        local inmarker = false
        local sleep = 1000
        local ped = PlayerPedId()
        local pedcoord = GetEntityCoords(ped)

        for k, v in pairs(moneywashers) do
            local jobRestricted = v.job ~= nil and v.job ~= ''
            local canAccess = true

            if jobRestricted then
                canAccess = (string.lower(playerJob or "") == string.lower(v.job or ""))
            end

            if canAccess then
                local zonecoords = #(vector3(v.coords[1], v.coords[2], v.coords[3]) - pedcoord)
                if zonecoords < Config.markers.drawDistance then
                    sleep = 0

                    if zonecoords < Config.markers.interactDistance then
                        inmarker = true

                        if not uiOpened and IsControlJustPressed(0, 38) then
                            OpenUI()
                        end
                    end

                    DrawMarker(
                        Config.markers.type,
                        v.coords[1], v.coords[2], v.coords[3],
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        Config.markers.size.x, Config.markers.size.y, Config.markers.size.z,
                        Config.markers.color.r, Config.markers.color.g, Config.markers.color.b, Config.markers.color.a,
                        false, true, 2, false, nil, nil, false
                    )

                    if Config.markers.pulse then
                        local pulse = math.abs(math.sin(GetGameTimer() / Config.markers.pulseSpeed)) * 0.2 +
                        Config.markers.size.x
                        DrawMarker(
                            Config.markers.type,
                            v.coords[1], v.coords[2], v.coords[3],
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            pulse, pulse, pulse,
                            Config.markers.color.r, Config.markers.color.g, Config.markers.color.b, 100,
                            false, true, 2, false, nil, nil, false
                        )
                    end
                end
            end
        end

        if inmarker and not alreadymarker then
            alreadymarker = true
            TextUIShown = true
            lib.showTextUI(locale('access_text'))
        end

        if not inmarker and alreadymarker then
            alreadymarker = false
            if TextUIShown then
                lib.hideTextUI()
                TextUIShown = false
            end
        end

        Wait(sleep)
    end
end)

RegisterCommand(Config.commands.adminMenu or 'moneywashadmin', function()
    ESX.TriggerServerCallback('muhaddil-moneywash:isAdmin', function(isAdmin)
        if isAdmin then
            OpenUI()
            Wait(100)
            SendUI('openAdminView', {})
        else
            lib.notify({
                title = locale('moneywash_title'),
                description = 'No tienes permisos',
                type = 'error'
            })
        end
    end)
end, false)

RegisterCommand(Config.commands.addLocation or 'addmoneywash', function(source, args)
    ESX.TriggerServerCallback('muhaddil-moneywash:isAdmin', function(isAdmin)
        if isAdmin then

            local job = args[1] or nil

            if not Config.permissions.allowMoneyWashersWithoutJobs and not job then
                lib.notify({
                    title = locale('moneywash_title'),
                    description = 'Debes indicar un trabajo para este punto de lavado.',
                    type = 'error'
                })
                return
            end

            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local heading = GetEntityHeading(ped)

            TriggerServerEvent('muhaddil-moneywash:addMoneywasher', coords, heading, job)

            lib.notify({
                title = locale('moneywash_title'),
                description = 'Ubicación añadida exitosamente' .. (job and (' para el trabajo: ' .. job) or ''),
                type = 'success'
            })
        else
            lib.notify({
                title = locale('moneywash_title'),
                description = 'No tienes permisos',
                type = 'error'
            })
        end
    end)
end, false)

local function PlayMoneyEffect(coords)
    if not Config.effects.particles then return end

    RequestNamedPtfxAsset("core")
    while not HasNamedPtfxAssetLoaded("core") do
        Wait(1)
    end
    UseParticleFxAssetNextCall("core")
    StartParticleFxNonLoopedAtCoord("ent_dst_banknotes", coords.x, coords.y, coords.z + 1.0, 0.0, 0.0, 0.0, 1.0, false,
        false, false)
end

RegisterNetEvent('muhaddil-moneywash:playEffect')
AddEventHandler('muhaddil-moneywash:playEffect', function()
    local coords = GetEntityCoords(PlayerPedId())
    PlayMoneyEffect(coords)
end)

local function PlaySound(soundName)
    if not Config.effects.sounds then return end
    PlaySoundFrontend(-1, soundName, "HUD_FRONTEND_DEFAULT_SOUNDSET", 1)
end

RegisterNetEvent('muhaddil-moneywash:playSound')
AddEventHandler('muhaddil-moneywash:playSound', function(sound)
    PlaySound(sound)
end)

DebugPrint("Money Wash Client Enhanced with Full Config - Loaded Successfully")
