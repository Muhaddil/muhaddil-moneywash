ESX = exports['es_extended']:getSharedObject()
lib.locale()

local function DebugPrint(printable)
    if Config.debug then
        print("[DEBUG] " .. tostring(printable))
    end
end

DebugPrint("Money Wash System Loaded - Client")

local alreadymarker = false
local menuopended = false
local playerJob = nil
local moneywashers = {}

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
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(playerData)
    DebugPrint("Player loaded: " .. json.encode(playerData))
    playerJob = playerData.job.name
    DebugPrint("Player job set to: " .. tostring(playerJob))
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
    DebugPrint("Job updated: " .. json.encode(job))
    playerJob = job.name
    DebugPrint("Player job changed to: " .. tostring(playerJob))
end)

local function showProgress(data)
    DebugPrint("showProgress called with type: " .. Config.progressType)
    if Config.progressType == "bar" then
        return lib.progressBar(data)
    elseif Config.progressType == "circle" then
        return lib.progressCircle(data)
    else
        Wait(data.duration or 1000)
        return true
    end
end

RegisterNetEvent('muhaddil-moneywash:startProcess', function (percetageinput, originalinput, time)
    if showProgress({
        duration = time * 1000,
        position = 'bottom',
        label = locale('washing'),
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, combat = true, move = true, mouse = false },
        anim = { dict = 'anim@heists@ornate_bank@grab_cash', clip = 'grab' },
    }) then
        TriggerServerEvent('muhaddil-moneywash:washMoney', percetageinput, originalinput)
        if Config.showNotification then
            lib.notify({
                title = locale('moneywash_title'),
                description = locale('success', percetageinput),
                type = 'success'
            })
        end
        showProgress({
            duration = 1000,
            position = 'bottom',
            label = locale('finishing'),
            useWhileDead = false,
            canCancel = false,
            disable = { car = true, combat = true, move = true, mouse = false },
            anim = { dict = 'amb@prop_human_atm@female@enter', clip = 'enter' },
        })
        TriggerServerEvent('muhaddil-moneywash:addCard')
    else
        if Config.showNotification then
            lib.notify({
                title = locale('moneywash_title'),
                description = locale('cancelled'),
                type = 'error'
            })
        end
        TriggerServerEvent('muhaddil-moneywash:addCard')
    end
end)

local function getInput()
    local input = lib.inputDialog(locale('moneywash_title'), {{type = 'number', label = locale('input_label')}})
    if not input then
        lib.notify({
            title = locale('moneywash_title'),
            description = locale('cancelled'),
            type = 'error'
        })
        TriggerServerEvent('muhaddil-moneywash:addCard')
        return
    end
    local originalinput = math.floor(input[1])
    local percetageinput = math.floor(originalinput - (originalinput * Config.percentage / 100))
    local time = math.max(1, math.floor(originalinput * 0.002))
    local alert = lib.alertDialog({
        header = locale('moneywash_title'),
        content = string.format(locale('time_alert'), tostring(time)),
        centered = true,
        cancel = true
    })
    if alert == 'confirm' then
        TriggerServerEvent('muhaddil-moneywash:checkBlackMoney', percetageinput, originalinput, time, function() end)
        TriggerServerEvent('muhaddil-moneywash:sendDistress')
    else
        lib.notify({
            title = locale('moneywash_title'),
            description = locale('cancelled'),
            type = 'error'
        })
        TriggerServerEvent('muhaddil-moneywash:addCard')
    end
end

RegisterNetEvent('muhaddil-moneywash:getInput', function ()
    if showProgress({
        duration = 2000,
        position = 'bottom',
        label = locale('card-inserting'),
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, combat = true, move = true, mouse = false },
        anim = { dict = 'amb@prop_human_atm@female@enter', clip = 'enter' },
    }) then
        getInput()
    else
        TriggerServerEvent('muhaddil-moneywash:addCard')
        lib.notify({
            title = locale('moneywash_title'),
            description = locale('cancelled'),
            type = 'error'
        })
    end
end)

local function openMenu(v)
    local jobRestricted = v.job ~= nil and v.job ~= ''
    local canAccess = true
    if jobRestricted then
        canAccess = (playerJob == v.job)
    end

    if not canAccess then
        lib.notify({
            title = locale('moneywash_title'),
            description = locale("not-required-job"),
            type = 'error'
        })
        return
    end

    lib.registerContext({
        id = 'moneywash',
        title = locale('moneywash_title'),
        options = {
            {
                title = locale('insert_card'),
                description = locale('insert_card_desc'),
                icon = 'id-card',
                onSelect = function()
                    TriggerServerEvent('muhaddil-moneywash:checkId')
                    SetEntityHeading(PlayerPedId(), v.heading)
                end
            }
        }
    })
    lib.showContext('moneywash')
end

RegisterNetEvent('muhaddil-moneywash:setMoneywashers', function(zones)
    DebugPrint("Received moneywash zones: " .. json.encode(zones))
    moneywashers = zones or {}
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
                if zonecoords < 2 then
                    sleep = 0
                    inmarker = true

                    if menuopended and lib.getOpenContextMenu() == nil then
                        DebugPrint("Context menu cerrado, reseteando menuopended")
                        menuopended = false
                    end

                    if not menuopended and IsControlJustPressed(0, 38) then
                        openMenu(v)
                        menuopended = true
                    end

                    DrawMarker(
                        20,
                        v.coords[1], v.coords[2], v.coords[3],
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        0.3, 0.3, 0.3,
                        0, 0, 0, 255, -- Pure black (red: integer, green: integer, blue: integer, alpha: integer max 255)
                        false, true, 2, false, nil, nil, false
                    )
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
            menuopended = false
            if TextUIShown then
                lib.hideTextUI()
                TextUIShown = false
            end
        end

        Wait(sleep)
    end
end)

-- Menu to delete wash locations
local function OpenSingleMoneywashMenu(index)
    local v = moneywashers[index]
    if not v then
        lib.notify({
            description = locale('location_not_found'),
            type = "error"
        })
        return
    end

    local jobText = v.job and ('🔒 Job: ' .. v.job) or '🔓 Libre'

    local options = {
        {
            title = locale('teleport_here'),
            icon = "location-dot",
            onSelect = function()
                local playerPed = PlayerPedId()
                SetEntityCoords(playerPed, v.coords[1], v.coords[2], v.coords[3] + 1.0, false, false, false, true)
                lib.notify({ description = locale('teleported_to_point'), type = "success" })
            end
        },
        {
            title = locale('delete_location'),
            icon = "trash",
            onSelect = function()
                TriggerServerEvent('muhaddil-moneywash:deleteMoneywasher', index)
                lib.notify({ description = locale('location_deleted'), type = "success" })
                Wait(100)
                OpenMoneywashDeleteMenu()
            end
        },
        {
            title = locale('change_job'),
            description = jobText,
            icon = "briefcase",
            onSelect = function()
                local input = lib.inputDialog(locale('change_job'), {
                    {
                        type = "input",
                        label = locale('change_job_desc'),
                        placeholder = "ej. mafia, police",
                        default = v.job or ''
                    }
                })
                if input then
                    TriggerServerEvent('muhaddil-moneywash:updateJob', index, input[1])
                    Wait(500)
                    OpenSingleMoneywashMenu(index)
                end
            end
        },
        {
            title = locale('change_ubication'),
            icon = "map-marker",
            onSelect = function()
                local coords = GetEntityCoords(PlayerPedId())
                local heading = GetEntityHeading(PlayerPedId())
                TriggerServerEvent('muhaddil-moneywash:updateLocation', index, coords, heading)
                lib.notify({ description = locale('change_ubication_success'), type = "success" })
                Wait(500)
                OpenSingleMoneywashMenu(index)
            end
        }
    }

    lib.registerContext({
        id = 'single_moneywash_menu',
        title = string.format(locale('options_for_location'), index),
        options = options
    })

    lib.showContext('single_moneywash_menu')
end

function OpenMoneywashDeleteMenu()
    DebugPrint("OpenMoneywashDeleteMenu called")

    if #moneywashers == 0 then
        lib.notify({
            description = locale('no_locations_to_delete'),
            type = "error"
        })
        return
    end

    local options = {}

    for i, v in ipairs(moneywashers) do
        table.insert(options, {
            title = string.format(locale('location_title'), i, v.coords[1], v.coords[2], v.coords[3]),
            description = string.format(locale('location_heading_with_job'), v.heading, v.job),
            icon = "trash",
            onSelect = function()
                OpenSingleMoneywashMenu(i)
            end
        })
    end

    lib.registerContext({
        id = 'moneywash_delete_menu',
        title = locale('delete_locations_title'),
        options = options
    })

    lib.showContext('moneywash_delete_menu')
end

RegisterCommand('delmoneywashmenu', function()
    ESX.TriggerServerCallback('muhaddil-moneywash:isAdmin', function(isAdmin)
        if isAdmin then
            OpenMoneywashDeleteMenu()
        end
    end)
end, false)
