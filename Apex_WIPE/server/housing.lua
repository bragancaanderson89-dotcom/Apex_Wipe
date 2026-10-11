-- Integrações revisadas: properties do ps-housing/QBOX e ox_doorlock.
-- As linhas de cadastro permanecem: só vínculos pessoais são alterados.
ApexHousing = {}
local H, P = ApexHousing, ApexPlanner

local function columns(schema, name)
    local result = {}
    for _, col in ipairs(schema.tables[name].columns) do result[col.name] = col end
    return result
end

local function array(value, label)
    if value == nil then return {} end
    if type(value) == 'string' then
        -- O SQL padrão do qbx_properties usa JSON_OBJECT() como lista vazia.
        if label == 'properties.keyholders' and value:match('^%s*{%s*}%s*$') then return {} end
        assert(value:match('^%s*%['), 'Lista de acesso incompatível: ' .. label)
        local ok, decoded = pcall(json.decode, value)
        assert(ok, 'Lista de acesso inválida: ' .. label)
        value = decoded
    end
    assert(type(value) == 'table', 'Lista de acesso incompatível: ' .. label)
    local count = 0
    for key, id in pairs(value) do
        assert(type(key) == 'number' and key >= 1 and key % 1 == 0
            and type(id) == 'string', 'Lista de acesso incompatível: ' .. label)
        count = count + 1
    end
    assert(count == #value, 'Lista de acesso não sequencial: ' .. label)
    return value
end

local function encodeArray(value)
    return #value == 0 and '[]' or json.encode(value)
end

local function replaceCharacters(raw, replacement)
    -- Altera apenas o membro de acesso no JSON original. A serialização dos
    -- demais campos (inclusive arrays vazios) não passa por recodificação Lua.
    local function skip(index)
        while raw:sub(index, index):match('%s') do index = index + 1 end
        return index
    end
    local function stringEnd(index)
        index = index + 1
        while index <= #raw do
            local ch = raw:sub(index, index)
            if ch == '\\' then index = index + 2
            elseif ch == '"' then return index
            else index = index + 1 end
        end
        error('Portas: string JSON incompleta.')
    end
    local function valueEnd(index)
        local first = raw:sub(index, index)
        if first == '"' then return stringEnd(index) end
        if first == '[' or first == '{' then
            local depth = 0
            while index <= #raw do
                local ch = raw:sub(index, index)
                if ch == '"' then index = stringEnd(index)
                elseif ch == '[' or ch == '{' then depth = depth + 1
                elseif ch == ']' or ch == '}' then
                    depth = depth - 1; if depth == 0 then return index end
                end
                index = index + 1
            end
            error('Portas: objeto JSON incompleto.')
        end
        while index <= #raw and not raw:sub(index, index):match('[,}]') do index = index + 1 end
        return index - 1
    end
    local index, found, result = skip(1), false, raw
    assert(raw:sub(index, index) == '{', 'Portas: cadastro precisa ser objeto JSON.')
    index = skip(index + 1)
    while raw:sub(index, index) ~= '}' do
        assert(raw:sub(index, index) == '"', 'Portas: chave JSON inválida.')
        local ending = stringEnd(index)
        local key = json.decode(raw:sub(index, ending))
        index = skip(ending + 1)
        assert(raw:sub(index, index) == ':', 'Portas: separador JSON inválido.')
        local start = skip(index + 1)
        ending = valueEnd(start)
        if key == 'characters' then
            assert(not found, 'Portas: chave characters duplicada.')
            found = true; result = raw:sub(1, start - 1) .. replacement .. raw:sub(ending + 1)
        end
        index = skip(ending + 1)
        if raw:sub(index, index) == '}' then break end
        assert(raw:sub(index, index) == ',', 'Portas: separador de campos inválido.')
        index = skip(index + 1)
    end
    assert(found, 'Portas: campo de acesso não encontrado.')
    return result
end

local function filter(value, targets, label)
    local result, changed = {}, false
    for _, id in ipairs(array(value, label)) do
        if targets[id] then changed = true else result[#result + 1] = id end
    end
    return result, changed
end

local function rows(schema, name)
    -- A impressão inclui a linha completa lida para o patch. A transação verifica
    -- essa mesma impressão antes de salvar o backup ou aplicar qualquer alteração.
    local expression = P.rowExpression(schema.tables[name].columns)
    local found = MySQL.query.await('SELECT *'
        .. (name == 'ox_doorlock' and ', CAST(`data` AS CHAR) AS __apex_raw_data' or '')
        .. ', CRC32(CAST(' .. expression
        .. ' AS CHAR)) AS __apex_fingerprint FROM ' .. P.identifier(name)
        .. ' ORDER BY ' .. P.identifier(name == 'properties' and columns(schema, name).property_id and 'property_id' or 'id')
        .. ' LIMIT ' .. (Config.MaxBackupRows + 1))
    assert(#found <= Config.MaxBackupRows, 'Integração de imóveis excede o limite de leitura segura.')
    return found
end

function H.prepare(ops, schema, request)
    if not schema or not request.modules.characters then return end
    local targets = {}
    -- Resolve apenas personagens existentes, inclusive no wipe seletivo.
    local selected = MySQL.query.await('SELECT `citizenid` FROM `players`'
        .. (request.scope == 'player' and ' WHERE `citizenid` = ?' or ''),
        request.scope == 'player' and { request.target } or {})
    for _, row in ipairs(selected) do targets[row.citizenid] = true end
    local owned, stashNames, planned = {}, {}, {}
    for _, op in ipairs(ops) do planned[op.table] = op end

    local function addPatches(name, key, patches, changedColumns, label, detaches)
        if #patches == 0 then return end
        assert(not P.protected(name) and not planned[name], 'Integração duplicada ou protegida: ' .. name)
        local params, marks, changes = {}, {}, {}
        for _, patch in ipairs(patches) do params[#params + 1] = patch.id; marks[#marks + 1] = '?' end
        for _, column in ipairs(changedColumns) do changes[#changes + 1] = { column = column } end
        local op = { table = name, label = label, mode = 'update', patches = patches,
            patchKey = key, changes = changes, detaches = detaches,
            where = P.identifier(key) .. ' IN (' .. table.concat(marks, ', ') .. ')', values = params,
            automationNote = label .. ': vínculos limpos; cadastros e estrutura preservados.' }
        ops[#ops + 1] = op; planned[name] = op
    end

    if schema.tables.properties then
        local cols = columns(schema, 'properties')
        local ps = cols.property_id and cols.owner_citizenid and cols.has_access
        local qbx = cols.id and cols.owner and cols.keyholders and cols.property_name and cols.coords
        assert((ps and not qbx) or (qbx and not ps), 'Imóveis: schema diferente dos padrões ps-housing/QBOX reconhecidos.')
        local key = ps and 'property_id' or 'id'
        local ownerColumn, accessColumn = ps and 'owner_citizenid' or 'owner', ps and 'has_access' or 'keyholders'
        assert(cols[key].key == 'PRI' and cols[ownerColumn].nullable == 'YES',
            'Imóveis: identificador precisa de chave primária e proprietário deve aceitar NULL.')
        local patches, changedColumns = {}, { ownerColumn, accessColumn }
        if ps and cols.for_sale then changedColumns[#changedColumns + 1] = 'for_sale' end
        for _, row in ipairs(rows(schema, 'properties')) do
            local access, changed = filter(row[accessColumn], targets, 'properties.' .. accessColumn)
            local owner = targets[row[ownerColumn]] == true
            local changes = {}
            if owner then
                if ps then owned[tostring(row[key])] = true end
                changes[#changes + 1] = { column = accessColumn, value = '[]' }
                changes[#changes + 1] = { column = ownerColumn, null = true }
                if ps and cols.for_sale then
                    changes[#changes + 1] = { column = 'for_sale', value = row.apartment and 0 or 1 }
                end
                local base = 'property_' .. tostring(row[key])
                if ps then stashNames[base] = true end
                local furniture = row.furnitures
                if type(furniture) == 'string' then
                    local ok, decoded = pcall(json.decode, furniture)
                    assert(ok, 'Imóveis: mobília inválida; não é possível identificar os baús.')
                    furniture = decoded
                end
                for index, item in ipairs(type(furniture) == 'table' and furniture or {}) do
                    if type(item) == 'table' and item.type == 'storage' and index ~= 1 then
                        assert(type(item.id) == 'string' or type(item.id) == 'number', 'Imóveis: baú sem identificador.')
                        local name = base .. tostring(item.id)
                        assert(#name <= 100, 'Imóveis: nome de baú incompatível.')
                        stashNames[name] = true
                    end
                end
            elseif changed then
                changes[#changes + 1] = { column = accessColumn, value = encodeArray(access) }
            end
            if #changes > 0 then
                patches[#patches + 1] = { id = row[key], fingerprint = tostring(row.__apex_fingerprint), changes = changes }
            end
        end
        -- Um op vazio continua cobrindo a FK quando nenhum imóvel pertence ao alvo.
        if #patches == 0 then
            ops[#ops + 1] = { table = 'properties', label = 'Imóveis: propriedade e acessos', mode = 'update',
                where = '1 = 0', values = {}, changes = { { column = ownerColumn, null = true } },
                detaches = { [ownerColumn] = true } }
            planned.properties = ops[#ops]
        else
            addPatches('properties', key, patches, changedColumns,
                'Imóveis: propriedade e acessos', { [ownerColumn] = true })
        end
    end

    if schema.tables.ox_doorlock then
        local cols = columns(schema, 'ox_doorlock')
        assert(cols.id and cols.id.key == 'PRI' and cols.name and cols.data, 'Portas: schema ox_doorlock incompatível.')
        local patches = {}
        for _, row in ipairs(rows(schema, 'ox_doorlock')) do
            local ok, data = true, row.data
            if type(data) == 'string' then ok, data = pcall(json.decode, data) end
            assert(ok and type(data) == 'table', 'Portas: cadastro JSON inválido.')
            if data.characters ~= nil then
                local access, changed = filter(data.characters, targets, 'ox_doorlock.data.characters')
                local propertyId = type(row.name) == 'string' and row.name:match('^ps_mloproperty(%d+)_%d+$')
                if propertyId and owned[propertyId] then access = {}; changed = #array(data.characters, 'porta') > 0 end
                if changed then
                    -- Mantém grupos, itens, senha, coordenadas e todas as outras opções.
                    local encoded = replaceCharacters(row.__apex_raw_data, encodeArray(access))
                    patches[#patches + 1] = { id = row.id, fingerprint = tostring(row.__apex_fingerprint),
                        changes = { { column = 'data', value = encoded } } }
                end
            end
        end
        addPatches('ox_doorlock', 'id', patches, { 'data' }, 'Portas: acessos pessoais')
    end

    if planned.ox_inventory and not request.modules.stashes and next(stashNames) then
        local names = {}
        for name in pairs(stashNames) do names[#names + 1] = name end
        table.sort(names)
        local op, marks = planned.ox_inventory, {}
        -- Copia para não modificar playerValues compartilhados por outros ops.
        local values = {}; for _, value in ipairs(op.values) do values[#values + 1] = value end
        for _, name in ipairs(names) do marks[#marks + 1] = '?'; values[#values + 1] = name end
        op.where = '(' .. op.where .. ') OR (`name` IN (' .. table.concat(marks, ', ') .. '))'
        op.values = values
        op.label = 'Baús pessoais e dos imóveis liberados'
    end
end
