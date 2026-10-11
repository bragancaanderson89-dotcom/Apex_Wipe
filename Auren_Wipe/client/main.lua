local opened, opening, epoch = false, false, 0
local viewData, viewToken
local pending, sequence = {}, math.max(1, GetGameTimer() % 900000000)

local function notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName('Auren_Wipe: ' .. tostring(message))
    EndTextCommandThefeedPostTicker(false, true)
end

local function rpc(action, data)
    sequence = sequence % 999999999 + 1
    local id = sequence
    local response = promise.new()
    pending[id] = response
    TriggerServerEvent('apex_wipe:request', id, action, data or {})
    SetTimeout(action == 'execute' and 240000 or 30000, function()
        if pending[id] then
            pending[id] = nil
            response:resolve({ ok = false, error = action == 'execute'
                and 'Resultado ainda não confirmado. Confira o histórico e o console antes de repetir.'
                or 'O servidor não respondeu a tempo.' })
        end
    end)
    return Citizen.Await(response)
end

RegisterNetEvent('apex_wipe:response', function(id, result)
    if source ~= 65535 then return end
    if type(result) ~= 'table' or not pending[id] then return end
    local response = pending[id]; pending[id] = nil
    response:resolve(result)
end)
RegisterNetEvent('apex_wipe:notify', function(message)
    if source ~= 65535 then return end
    notify(message)
end)
RegisterNetEvent('apex_wipe:maintenance', function()
    if source ~= 65535 then return end
    notify('Manutenção administrativa iniciada. Aguarde antes de reconectar.')
    FreezeEntityPosition(PlayerPedId(), true)
end)

local function close()
    epoch = epoch + 1
    opening = false
    opened = false
    viewData, viewToken = nil, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ channel = 'Auren_Wipe', action = 'close' })
end

RegisterNetEvent('apex_wipe:open', function()
    if source ~= 65535 or opened or opening then return end
    opening = true
    local generation = epoch
    local ok, result = pcall(rpc, 'bootstrap')
    if epoch ~= generation then return end
    opening = false
    if not ok or not result or not result.ok then
        notify(result and result.error or 'Não foi possível abrir Auren_Wipe.')
        return
    end
    opened = true
    viewData = result.data
    viewToken = ('%s:%s:%s'):format(GetCurrentResourceName(), generation, GetGameTimer())
    SendNUIMessage({ channel = 'Auren_Wipe', action = 'open', data = viewData, token = viewToken })
end)

RegisterNUICallback('uiShown', function(data, cb)
    if opened and viewToken and type(data) == 'table' and data.token == viewToken then
        SetNuiFocus(true, true)
        cb({ ok = true, data = {} })
    else
        SetNuiFocus(false, false)
        SendNUIMessage({ channel = 'Auren_Wipe', action = 'close' })
        cb({ ok = false, error = 'Abertura não autorizada.' })
    end
end)

RegisterNUICallback('uiReady', function(_, cb)
    if opened and viewData and viewToken then
        SendNUIMessage({ channel = 'Auren_Wipe', action = 'open', data = viewData, token = viewToken })
    else
        SetNuiFocus(false, false)
        SendNUIMessage({ channel = 'Auren_Wipe', action = 'close' })
    end
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb) close(); cb({ ok = true }) end)
for _, name in ipairs({ 'bootstrap', 'search', 'preview', 'execute' }) do
    local action = name
    RegisterNUICallback(action, function(data, cb)
        if not opened then cb({ ok = false, error = 'Interface fechada.' }); return end
        local ok, result = pcall(rpc, action, data)
        cb(ok and result or { ok = false, error = 'Falha de comunicação com o servidor.' })
    end)
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    close()
end)
local function shutdown(resource)
    if resource ~= GetCurrentResourceName() then return end
    close()
    FreezeEntityPosition(PlayerPedId(), false)
end
AddEventHandler('onResourceStop', shutdown)
AddEventHandler('onClientResourceStop', shutdown)

-- Limpa foco imediatamente; o HTML mantém a tela vazia até o handshake.
close()
