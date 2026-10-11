-- Preflight de efeitos conhecidos. Nenhum trigger é removido ou desativado.
ApexAutomation = {}
local A, P = ApexAutomation, ApexPlanner

local function body(value)
    if type(value) ~= 'string' then return nil end
    -- Compara corpos completos revisados; nunca executa definições recebidas.
    value = value:lower():gsub('`([%a_][%w_]*)`', '%1'):gsub('%s+', ' ')
    value = value:match('^%s*(.-)%s*$'):gsub(';%s*$', '')
    if value:match('^begin ') and value:match(' end$') then
        value = value:sub(7, -5):gsub(';%s*$', '')
    end
    return value:gsub('%s*=%s*', '='):gsub('%s*<>%s*', '<>'):gsub('%s*%.%s*', '.')
end

local reviewed = {
    ['delete from police_impound where plate=old.plate'] = { event = 'DELETE', kind = 'impoundDelete' },
    ['update police_impound set plate=new.plate where plate=old.plate'] = { event = 'UPDATE', kind = 'impoundPlate' },
    ['if new.state<>2 then delete from police_impound where plate=old.plate; end if'] = {
        event = 'UPDATE', kind = 'impoundState' }
}

function A.classify(tableName, trigger, mode)
    if type(trigger) ~= 'table' then return nil, 'Metadados do trigger indisponíveis.' end
    local event = trigger.event
    if event ~= 'INSERT' and event ~= 'UPDATE' and event ~= 'DELETE' then
        return nil, 'Evento do trigger indisponível.'
    end
    local operation = mode == 'delete' and 'DELETE' or mode == 'update' and 'UPDATE' or nil
    if operation and event ~= operation then return { kind = 'inactive' } end
    local rule = reviewed[body(trigger.statement)]
    if tableName == 'player_vehicles' and trigger.timing == 'AFTER' and rule and rule.event == event then
        return { kind = rule.kind }
    end
    return nil, 'Definição ativa fora dos padrões reconhecidos.'
end

function A.prepare(ops, schema)
    local vehicles, seen = nil, {}
    for _, op in ipairs(ops) do seen[op.table] = op; if op.table == 'player_vehicles' then vehicles = op end end
    local notes, issues, kinds = {}, {}, {}
    for _, op in ipairs(ops) do
        if op.automationNote then notes[#notes + 1] = op.automationNote end
        local t = schema.tables[op.table]
        for _, trigger in ipairs(t and t.triggers or {}) do
            local rule, reason = A.classify(op.table, trigger, op.mode)
            local name = type(trigger) == 'table' and trigger.name or tostring(trigger)
            if not rule then
                issues[#issues + 1] = op.table .. ' · ' .. name .. ': ' .. reason
            elseif rule.kind ~= 'inactive' then
                kinds[rule.kind] = true
                notes[#notes + 1] = name .. ': efeitos incluídos automaticamente no backup.'
            end
        end
    end
    if #issues > 0 then return notes, issues end
    local function requireColumn(tableName, column)
        local t = schema.tables[tableName]
        for _, col in ipairs(t and t.columns or {}) do if col.name == column then return end end
        error('Integração de garagem incompatível: coluna ausente ' .. tableName .. '.' .. column)
    end
    local function addDependent(name, column, parentColumn, label, mode)
        assert(not P.protected(name), 'Tabela protegida: ' .. name)
        assert(not seen[name], 'Dependência de garagem duplicada: ' .. name)
        requireColumn(name, column); requireColumn('player_vehicles', parentColumn)
        local op = { table = name, label = label, mode = mode, relation = column,
            where = P.membership(name, column, 'player_vehicles', parentColumn,
                vehicles.where, schema), values = vehicles.values }
        ops[#ops + 1] = op; seen[name] = op
        if mode == 'delete' then
            vehicles.automaticIncoming = vehicles.automaticIncoming or {}
            vehicles.automaticIncoming[#vehicles.automaticIncoming + 1] = {
                child = name, child_column = column, parent = 'player_vehicles', parent_column = parentColumn }
        end
        return op
    end
    if vehicles then
        if vehicles.mode == 'delete' then
            if schema.tables.vehicle_financing then
                addDependent('vehicle_financing', 'vehicleId', 'id', 'Financiamentos dos veículos', 'delete')
                notes[#notes + 1] = 'Financiamentos vinculados incluídos automaticamente.'
            end
            if schema.tables.police_impound or kinds.impoundDelete then
                addDependent('police_impound', 'plate', 'plate', 'Pátio da polícia: veículos removidos', 'delete')
            end
        elseif kinds.impoundPlate or kinds.impoundState then
            -- Só atualizamos compartimentos: placa/estado permanecem como OLD.
            for _, change in ipairs(vehicles.changes or {}) do
                assert(change.column == 'trunk' or change.column == 'glovebox',
                    'Alteração de veículo fora do tratamento automático da garagem.')
            end
            requireColumn('player_vehicles', 'state')
            local child = addDependent('police_impound', 'plate', 'plate',
                'Pátio da polícia: efeitos automáticos da garagem', 'trigger')
            if kinds.impoundState then
                child.verifyAbsent = P.membership('police_impound', 'plate', 'player_vehicles', 'plate',
                    '(' .. vehicles.where .. ') AND `state` <> 2', schema)
            end
        end
    end
    for _, op in ipairs(ops) do
        if op.mode == 'trigger' then
            local t = schema.tables[op.table]
            assert(t and #t.triggers == 0, 'Efeitos adicionais não reconhecidos em ' .. op.table)
        end
    end
    return notes, issues
end

function A.compatibility(name, schema)
    local t = schema.tables[name]
    if not t then return false end
    for _, trigger in ipairs(t.triggers) do
        if not A.classify(name, trigger, 'delete') or not A.classify(name, trigger, 'update') then return false end
    end
    return true
end
