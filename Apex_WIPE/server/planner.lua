-- Planejador puro: o navegador nunca envia SQL, tabelas ou predicados.
ApexPlanner = {}
local P = ApexPlanner
local modules = { inventory = true, money = true, vehicles = true,
    vehicleStorage = true, stashes = true, characters = true }

function P.identifier(value)
    assert(type(value) == 'string' and #value > 0 and #value <= 64
        and value:match('^[%a_][%w_]*$'), 'Identificador SQL inválido.')
    return '`' .. value .. '`'
end

function P.text(value, max, label, allowEmpty)
    assert(type(value) == 'string', (label or 'Campo') .. ' inválido.')
    value = value:match('^%s*(.-)%s*$')
    assert(#value <= max and (allowEmpty or #value > 0)
        and not value:find('[%z\1-\31]'), (label or 'Campo') .. ' inválido.')
    return value
end

function P.protected(name)
    local lower = name:lower()
    if lower:match('^apex_wipe_') or lower:find('config', 1, true)
        or lower:find('setting', 1, true) then return true end
    for _, value in ipairs(Config.ProtectedTables) do
        if lower == value:lower() then return true end
    end
    return false
end

function P.normalize(input)
    assert(type(input) == 'table', 'Pedido inválido.')
    local scope = input.scope
    assert(scope == 'player' or scope == 'stash' or scope == 'garage' or scope == 'server', 'Escopo inválido.')
    local request = { scope = scope, modules = {}, target = '', owner = '' }
    assert(type(input.modules) == 'table', 'Selecione ao menos uma categoria.')
    local selected = 0
    for key, enabled in pairs(input.modules) do
        assert(modules[key] and type(enabled) == 'boolean', 'Categoria inválida.')
        if enabled then request.modules[key] = true; selected = selected + 1 end
    end
    assert(selected > 0, 'Selecione ao menos uma categoria.')
    if scope ~= 'server' then request.target = P.text(input.target, scope == 'player' and 50 or 100, 'Alvo') end
    if scope == 'stash' then
        request.owner = P.text(input.owner or '', 60, 'Proprietário', true)
        assert(request.modules.stashes and selected == 1, 'Baús aceitam apenas conteúdo de baú.')
    elseif scope == 'garage' then
        assert(not request.modules.inventory and not request.modules.money and not request.modules.stashes
            and not request.modules.characters, 'Categoria incompatível com garagem.')
    elseif scope == 'player' then
        assert(not request.modules.stashes, 'Use a aba Baús para limpar um baú específico.')
    end
    if request.modules.characters then
        -- Remover personagem inclui relações conhecidas, mesmo sem checkbox.
        request.modules.inventory = nil
        request.modules.money = nil
        request.modules.vehicles = true
        request.modules.vehicleStorage = nil
    elseif request.modules.vehicles then
        request.modules.vehicleStorage = nil -- a remoção do veículo já inclui seus compartimentos.
    end
    request.reason = P.text(input.reason, 250, 'Motivo')
    assert(#request.reason >= 8, 'Descreva o motivo com pelo menos 8 caracteres.')
    return request
end

function P.build(request, schema)
    local ops = {}
    local function add(name, label, mode, predicate, values, changes, relation)
        assert(not P.protected(name), 'Tabela protegida: ' .. name)
        P.identifier(name)
        ops[#ops + 1] = { table = name, label = label, mode = mode,
            where = predicate, values = values or {}, changes = changes,
            relation = relation }
    end
    local scope, m = request.scope, request.modules
    local playerWhere = scope == 'player' and '`citizenid` = ?' or '1 = 1'
    local playerValues = scope == 'player' and { request.target } or {}
    local vehicleWhere, vehicleValues = playerWhere, playerValues
    if scope == 'garage' then vehicleWhere = '`garage` = ?'; vehicleValues = { request.target } end
    if m.characters then
        local adapters = ApexIntegrations and ApexIntegrations.adapters(schema) or Config.CharacterAdapters
        for _, adapter in ipairs(adapters) do
            assert(adapter.reviewed == true, 'Adaptador não revisado: ' .. tostring(adapter.table))
            assert(adapter.table ~= 'players' and adapter.table ~= 'player_vehicles'
                and adapter.table ~= 'player_groups' and adapter.table ~= 'ox_inventory', 'Adaptador duplicado.')
            local column = P.identifier(adapter.citizenColumn)
            add(adapter.table, 'Dados adicionais de personagem', 'delete',
                scope == 'player' and (column .. ' = ?')
                    or (column .. ' IN (SELECT `citizenid` FROM `players`)'), playerValues, nil, adapter.citizenColumn)
        end
        if not schema or schema.tables.player_groups then
            add('player_groups', 'Vínculos de empregos e gangs', 'delete', playerWhere, playerValues, nil, 'citizenid')
        end
    end
    if m.vehicles then
        add('player_vehicles', 'Veículos e seus compartimentos', 'delete', vehicleWhere, vehicleValues, nil, 'citizenid')
    elseif m.vehicleStorage then
        add('player_vehicles', 'Porta-malas e porta-luvas', 'update', vehicleWhere, vehicleValues,
            { { column = 'trunk', value = '[]' }, { column = 'glovebox', value = '[]' } })
    end
    if m.stashes then
        local where, values = '1 = 1', {}
        if scope == 'stash' then
            where, values = '`name` = ? AND (`owner` IS NULL OR `owner` = ?)', { request.target, '' }
            if request.owner ~= '' then where, values = '`name` = ? AND `owner` = ?', { request.target, request.owner } end
        end
        add('ox_inventory', 'Conteúdo dos baús (cadastros mantidos)', 'update', where, values,
            { { column = 'data', value = '[]' } })
    elseif m.characters and (not schema or schema.tables.ox_inventory) then
        local where = '`owner` IN (SELECT `citizenid` FROM `players` WHERE ' .. playerWhere .. ')'
        add('ox_inventory', 'Baús pessoais dos personagens', 'update', where, playerValues,
            { { column = 'data', value = '[]' } })
    end
    if m.characters then
        add('players', 'Personagens', 'delete', playerWhere, playerValues, nil, 'citizenid')
    else
        local changes = {}
        if m.inventory then changes[#changes + 1] = { column = 'inventory', value = '[]' } end
        if m.money then changes[#changes + 1] = { column = 'money', value = json.encode(Config.StartingMoney) } end
        if #changes > 0 then add('players', 'Inventários / saldos dos personagens', 'update', playerWhere, playerValues, changes) end
    end
    assert(#ops > 0, 'Plano vazio.')
    local seen = {}
    for _, op in ipairs(ops) do
        assert(not seen[op.table], 'Tabela repetida no plano: ' .. op.table)
        seen[op.table] = true
    end
    return ops
end

function P.confirmation(request)
    local target = request.scope == 'server' and 'SERVIDOR' or request.target
    return 'WIPE ' .. target
end

function P.mutation(op)
    local tableName = P.identifier(op.table)
    local values = {}
    if op.mode == 'delete' then
        for _, v in ipairs(op.values) do values[#values + 1] = v end
        return 'DELETE FROM ' .. tableName .. ' WHERE ' .. op.where, values
    end
    local set = {}
    for _, change in ipairs(op.changes) do
        set[#set + 1] = P.identifier(change.column) .. ' = ?'
        values[#values + 1] = change.value
    end
    for _, v in ipairs(op.values) do values[#values + 1] = v end
    return 'UPDATE ' .. tableName .. ' SET ' .. table.concat(set, ', ') .. ' WHERE ' .. op.where, values
end
