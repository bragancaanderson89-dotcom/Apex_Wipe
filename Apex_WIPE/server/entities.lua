-- Entidades persistentes também precisam sair do mundo após excluir seus registros.
-- Captura somente veículos comprovadamente pertencentes ao plano, sem apagar tráfego.
ApexEntities = {}
local E, P = ApexEntities, ApexPlanner
local function plate(value)
    return type(value) == 'string' and value:match('^%s*(.-)%s*$'):upper() or ''
end

local function identity(entity)
    return { id = Entity(entity).state.vehicleid,
        plate = plate(GetVehicleNumberPlateText(entity)), network = NetworkGetNetworkIdFromEntity(entity) }
end

function E.capture(ops)
    local selected
    for _, op in ipairs(ops) do
        if op.table == 'player_vehicles' and op.mode == 'delete' then selected = op; break end
    end
    if not selected then return {} end
    local rows = MySQL.query.await('SELECT `id`, `plate` FROM ' .. P.identifier(selected.table)
        .. ' WHERE ' .. selected.where, selected.values)
    assert(#rows == selected.measure.count, 'Alcance dos veículos mudou; simule novamente.')
    local ids, plates, result = {}, {}, {}
    for _, row in ipairs(rows) do
        ids[tostring(row.id)] = true
        local normalized = plate(row.plate)
        if normalized ~= '' then plates[normalized] = true end
    end
    for _, entity in ipairs(GetAllVehicles()) do
        if DoesEntityExist(entity) then
            local current = identity(entity)
            -- Um vehicleid explícito prevalece sobre a placa, evitando colisões.
            local matched = current.id ~= nil and ids[tostring(current.id)]
                or (current.id == nil and current.plate ~= '' and plates[current.plate])
            if matched then result[#result + 1] = { entity = entity, identity = current } end
        end
    end
    return result
end

function E.cleanup(captured)
    local warnings = {}
    for _, record in ipairs(captured) do
        local entity, old = record.entity, record.identity
        if DoesEntityExist(entity) then
            local current = identity(entity)
            if current.network ~= old.network or current.plate ~= old.plate
                or tostring(current.id) ~= tostring(old.id) then
                warnings[#warnings + 1] = 'Identidade de veículo mudou durante a operação; revisão manual necessária.'
            else
                DeleteEntity(entity)
                for _ = 1, 10 do
                    if not DoesEntityExist(entity) then break end
                    Wait(100)
                end
                if DoesEntityExist(entity) then
                    warnings[#warnings + 1] = 'Veículo persistente não removido: ' .. old.plate
                end
            end
        end
    end
    return warnings
end
