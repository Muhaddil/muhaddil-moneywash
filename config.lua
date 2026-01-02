Config = {}

Config.percentageMin = 20
Config.percentageMax = 30

Config.itemname = 'moneywash_card'

Config.progressType = "bar"

Config.showNotification = true

Config.returnCard = true

Config.AutoVersionChecker = true

Config.debug = false

Config.washMethods = {
    standard = {
        name = "Estándar",
        speedMultiplier = 1.0, -- Velocidad normal
        successBonus = 0,      -- Sin bonus de éxito
        minAmount = 1000,      -- Mínimo $1000
        maxAmount = 1000000    -- Máximo $1M
    },
    fast = {
        name = "Rápido",
        speedMultiplier = 0.5, -- 50% más rápido
        successBonus = -10,    -- -10% de éxito
        minAmount = 5000,
        maxAmount = 500000
    },
    secure = {
        name = "Seguro",
        speedMultiplier = 1.5, -- 50% más lento
        successBonus = 5,      -- +5% de éxito
        minAmount = 10000,
        maxAmount = 2000000
    }
}

Config.reputation = {
    enabled = true,

    gainPerSuccess = { min = 1, max = 3 },

    lossPerFail = { min = 1, max = 2 },

    successBonusPerLevel = 0.5,

    levels = {
        { name = "Novato",       min = 0,  max = 19 },
        { name = "Principiante", min = 20, max = 39 },
        { name = "Profesional",  min = 40, max = 59 },
        { name = "Experto",      min = 60, max = 79 },
        { name = "Legendario",   min = 80, max = 100 }
    }
}

Config.police = {
    enabled = true,

    jobs = { 'police', 'sheriff' },

    alertChanceSuccess = 5,

    alertChanceFail = 30,

    blipDuration = 60000,

    blip = {
        sprite = 431,
        color = 1,
        scale = 1.0,
        label = "Lavado de Dinero Detectado"
    }
}

Config.effects = {
    particles = true,

    sounds = true,

    animations = {
        insert = {
            dict = 'amb@prop_human_atm@female@enter',
            anim = 'enter',
            duration = 2000
        },
        washing = {
            dict = 'anim@heists@ornate_bank@grab_cash',
            anim = 'grab',
            loop = true
        },
        finish = {
            dict = 'amb@prop_human_atm@female@enter',
            anim = 'enter',
            duration = 2000
        }
    },

    camera = {
        shake = true,
        shakeIntensity = 0.2,
        shakeDuration = 1000
    }
}

Config.markers = {
    -- (https://docs.fivem.net/docs/game-references/markers/)
    type = 20,

    size = { x = 0.3, y = 0.3, z = 0.3 },

    color = { r = 16, g = 233, b = 179, a = 200 },

    drawDistance = 15.0,

    interactDistance = 2.0,

    pulse = true,
    pulseSpeed = 500
}

Config.limits = {
    minWashAmount = 1000,

    maxWashAmount = 5000000,

    dailyLimit = 0,

    cooldownTime = 0
}

Config.discord = {
    enabled = true,

    webhookURL = "YOUR WEBHOOK URL HERE",

    logSuccess = true,

    logFails = true,
    logPoliceAlerts = true,

    embeds = {
        success = {
            title = "💸 Lavado de Dinero Exitoso",
            color = 65280 -- Verde
        },
        fail = {
            title = "⚠️ Lavado de Dinero Fallido",
            color = 16711680 -- Rojo
        },
        police = {
            title = "🚨 Alerta Policial",
            color = 255 -- Azul
        }
    }
}

Config.economy = {
    timeBasedPricing = false,

    peakHours = { 2, 3, 4, 5 }, -- 2AM - 5AM
    peakBonus = 5,              -- 5% menos de comisión

    volumeDiscount = 0.1,
    maxVolumeDiscount = 10 -- Máximo 10% de descuento
}

Config.ui = {
    maxHistoryEntries = 50
}

Config.commands = {
    adminMenu = "moneywashadmin",
    addLocation = "addmoneywash",
    deleteMenu = "delmoneywashmenu",
    stats = "moneywashinfo"
}

Config.permissions = {
    adminGroups = { 'admin', 'superadmin' },

    allowPlayerStats = true,
    allowMoneyWashersWithoutJobs = true -- Permite crear puntos de lavado de dinero sin necesidad de un trabajo
}

function Config.GetCommissionPercentage()
    local basePercentage = math.random(Config.percentageMin, Config.percentageMax)

    if Config.economy.timeBasedPricing then
        local hour = tonumber(os.date("%H"))
        for _, peakHour in ipairs(Config.economy.peakHours) do
            if hour == peakHour then
                basePercentage = basePercentage - Config.economy.peakBonus
                break
            end
        end
    end

    return math.max(10, math.min(40, basePercentage))
end

function Config.GetWashTime(amount)
    return math.max(1, math.floor(amount * 0.002))
end

function Config.IsValidAmount(amount)
    return amount >= Config.limits.minWashAmount and amount <= Config.limits.maxWashAmount
end
