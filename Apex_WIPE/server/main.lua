local P, D, M = ApexPlanner, ApexDB, ApexMaintenance
local ready, busy = false, false
local plans, cooldowns, requests = {}, {}, {}
local handlers = {}
local function actor(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return 'source:' .. source
end
local function admin(source)
    if source <= 0 then return false end
    if IsPlayerAceAllowed(source, Config.AdminAce) then return true end
    for _, ace in ipairs(Config.InheritedAdminAces) do
        if IsPlayerAceAllowed(source, ace) then return true end
    end
    -- Compatibilidade com cores antigos; ACE é sempre a primeira opção.
    if ApexIntegrations.permission(source) then return true end
    -- A permissão do operador é retida somente na manutenção que ele já autorizou.
    return M.active and M.operator == source and M.authorizedActor == actor(source)
end
local function canExecute(source)
    return admin(source) and (not Config.ExecuteAce or IsPlayerAceAllowed(source, Config.ExecuteAce))
end
local function auditActor(source, job)
    job.actorName = (GetPlayerName(source) or 'Administrador'):sub(1, 100)
    job.actorSource = source
    job.actorIdentifiers = {}
    local wanted = { license = true, license2 = true, discord = true, fivem = true, steam = true }
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        local kind = identifier:match('^([^:]+):')
        if wanted[kind] then job.actorIdentifiers[kind] = identifier end
    end
    job.actorCharacter = {}
    if ApexIntegrations.core() then
        local ok, player = pcall(ApexIntegrations.player, source)
        if ok and player and player.PlayerData then
            local data = player.PlayerData
            job.actorCharacter = { citizenid = data.citizenid,
                name = (data.charinfo and ((data.charinfo.firstname or '') .. ' ' .. (data.charinfo.lastname or ''))) or data.name }
        end
    end
end
local function safeError(err)
    local message = tostring(err):gsub('^.-:%d+: ', '')
    -- Erros SQL não vazam detalhes do banco pela NUI.
    if message:lower():find('sql') or message:lower():find('query') then
        return 'Falha no banco de dados. Confira o console do servidor.'
    end
    return message:sub(1, 350)
end
local function endpoint(name, handler)
    handlers[name] = function(source, input)
        if not admin(source) then return { ok = false, error = 'Acesso restrito aos administradores autorizados.' } end
        if not ready then return { ok = false, error = 'Banco de auditoria ainda não está pronto.' } end
        if busy then return { ok = false, error = 'Uma execução está em andamento. Aguarde.' } end
        if requests[source] then return { ok = false, error = 'Sua solicitação anterior ainda está em andamento.' } end
        local now = GetGameTimer()
        cooldowns[source] = cooldowns[source] or {}
        if cooldowns[source][name] and now - cooldowns[source][name] < Config.RequestCooldown then
            return { ok = false, error = 'Aguarde um instante entre as solicitações.' }
        end
        cooldowns[source][name] = now
        local lease = { actor = actor(source) }
        requests[source] = lease
        local ok, result = pcall(handler, source, input or {}, lease.actor)
        if requests[source] == lease then requests[source] = nil end
        if not GetPlayerName(source) or actor(source) ~= lease.actor then
            return { ok = false, error = 'Sessão encerrada durante a solicitação.' }
        end
        if ok then return { ok = true, data = result } end
        print(('[Apex_WIPE] Requisição %s recusada: %s'):format(name, tostring(result)))
        return { ok = false, error = safeError(result) }
    end
end

local function maintenanceBlockers()
    local blockers = {}
    if not Config.ExecutionEnabled then blockers[#blockers + 1] = 'Execução desabilitada em config.server.lua.' end
    if not Config.AutomaticMaintenance then blockers[#blockers + 1] = 'Manutenção automática desabilitada em config.server.lua.' end
    if M.active then blockers[#blockers + 1] = 'Manutenção anterior pendente. Consulte o console.' end
    return blockers
end

local function summarize(ops)
    local rows, bytes, list = 0, 0, {}
    for _, op in ipairs(ops) do
        op.measure = D.measure(op)
        rows = rows + op.measure.count
        bytes = bytes + op.measure.bytes
        list[#list + 1] = { table = op.table, label = op.label, mode = op.mode,
            count = op.measure.count, columns = op.changes and (function()
                local cols = {}; for _, c in ipairs(op.changes) do cols[#cols + 1] = c.column end; return cols
            end)() or {} }
    end
    assert(rows > 0, 'Nenhum registro corresponde ao alvo informado.')
    assert(rows <= Config.MaxBackupRows, 'Plano excede o limite de linhas de backup. Use um dump externo ou lotes menores.')
    assert(bytes <= Config.MaxBackupBytes, 'Plano excede o limite de tamanho de backup.')
    return { rows = rows, bytes = bytes, operations = list }
end

endpoint('bootstrap', function(source)
    local schema = D.schema()
    local history = MySQL.query.await([[SELECT id, actor_name AS actorName, actor AS actorLicense,
        actor_source AS actorSource, actor_identifiers AS actorIdentifiers, actor_character AS actorCharacter,
        scope, target, reason, status, plan, CAST(created_at AS CHAR) AS createdAt
        FROM apex_wipe_jobs ORDER BY created_at DESC LIMIT 30]])
    for _, row in ipairs(history) do
        for _, key in ipairs({ 'actorIdentifiers', 'actorCharacter', 'plan' }) do
            local ok, decoded = pcall(json.decode, row[key] or '{}')
            row[key] = ok and type(decoded) == 'table' and decoded or {}
        end
    end
    local compatibility, protected = {}, {}
    for _, name in ipairs({ 'players', 'player_groups', 'player_vehicles', 'ox_inventory' }) do
        local t = schema.tables[name]
        compatibility[#compatibility + 1] = { table = name, present = t ~= nil,
            engine = t and t.engine or '', triggers = t and #t.triggers or 0 }
    end
    for name in pairs(schema.tables) do
        if name ~= 'players' and name ~= 'player_groups' and name ~= 'player_vehicles' and name ~= 'ox_inventory' then
            protected[#protected + 1] = name
        end
    end
    table.sort(protected)
    local stats = {}
    for key, name in pairs({ players = 'players', vehicles = 'player_vehicles', stashes = 'ox_inventory' }) do
        if schema.tables[name] then stats[key] = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM ' .. P.identifier(name))) end
    end
    return { serverName = Config.ServerName, adminName = GetPlayerName(source), history = history,
        compatibility = compatibility, protectedTables = protected, blockers = maintenanceBlockers(),
        executionEnabled = Config.ExecutionEnabled, canExecute = canExecute(source),
        stats = stats, maintenance = M.describe(), planLifetime = Config.PlanLifetime }
end)

endpoint('search', function(_, input)
    local term = P.text(input.term or '', 60, 'Busca', true)
    -- Busca limitada. % e _ são literais, nunca ampliam o escopo.
    local escaped = term:gsub('!', '!!'):gsub('%%', '!%%'):gsub('_', '!_')
    local like = '%' .. escaped .. '%'
    if input.kind == 'player' then
        local rows = MySQL.query.await([[SELECT citizenid AS target, name AS label, charinfo
            FROM players WHERE citizenid LIKE ? ESCAPE '!' OR name LIKE ? ESCAPE '!'
            ORDER BY name LIMIT 30]], { like, like })
        for _, row in ipairs(rows) do
            local ok, info = pcall(json.decode, row.charinfo or '{}')
            if ok and type(info) == 'table' then row.label = (info.firstname or '') .. ' ' .. (info.lastname or '') end
            row.charinfo = nil
        end
        return rows
    elseif input.kind == 'stash' then
        return MySQL.query.await([[SELECT name AS target, COALESCE(owner, '') AS owner, name AS label
            FROM ox_inventory WHERE name LIKE ? ESCAPE '!' ORDER BY name LIMIT 30]], { like })
    elseif input.kind == 'garage' then
        return MySQL.query.await([[SELECT garage AS target, garage AS label, COUNT(*) AS count
            FROM player_vehicles WHERE garage IS NOT NULL AND garage <> '' AND garage LIKE ? ESCAPE '!'
            GROUP BY garage ORDER BY garage LIMIT 30]], { like })
    end
    error('Tipo de busca inválido.')
end)

endpoint('preview', function(source, input, identity)
    local request = P.normalize(input)
    local schema = D.schema()
    ApexIntegrations.money()
    local ops = D.inspect(P.build(request, schema), schema)
    local summary = summarize(ops)
    local id = MySQL.scalar.await('SELECT UUID()')
    assert(GetPlayerName(source) and actor(source) == identity, 'Sessão encerrada durante a simulação.')
    local blockers = maintenanceBlockers()
    if not canExecute(source) then blockers[#blockers + 1] = 'Sua permissão permite revisão, mas não execução.' end
    plans[source] = { id = id, request = request, ops = ops, summary = summary,
        actor = identity, expires = os.time() + Config.PlanLifetime }
    return { id = id, request = request, summary = summary, blockers = blockers,
        maintenance = M.describe(), confirmation = P.confirmation(request), expiresIn = Config.PlanLifetime }
end)

endpoint('execute', function(source, input)
    assert(canExecute(source), 'Sem permissão de execução.')
    assert(type(input) == 'table' and type(input.id) == 'string', 'Plano inválido.')
    local job = plans[source]
    assert(job and job.id == input.id and job.actor == actor(source), 'Plano inexistente. Faça uma nova simulação.')
    assert(os.time() <= job.expires, 'Plano expirado. Faça uma nova simulação.')
    assert(input.confirmation == P.confirmation(job.request) and input.backupAcknowledged == true,
        'Confirmação incorreta ou backup não confirmado.')
    local blockers = maintenanceBlockers()
    assert(#blockers == 0, table.concat(blockers, '\n'))
    -- O plano é de uso único, inclusive quando uma execução falha.
    plans[source] = nil
    busy = true
    auditActor(source, job)
    local ok, result = pcall(function()
        local schema = D.schema()
        local current = D.inspect(P.build(job.request, schema), schema)
        assert(#current == #job.ops, 'Schema alterado. Faça uma nova simulação.')
        for i, op in ipairs(current) do
            local old = job.ops[i]
            assert(op.table == old.table and op.schemaSignature == old.schemaSignature, 'Schema alterado. Faça uma nova simulação.')
        end
        assert(canExecute(source), 'Permissão revogada durante a revisão.')
        M.authorizedActor = job.actor
        M.jobId = job.id
        M.begin(source)
        -- Salvamentos legítimos podem alterar conteúdo/horários durante o fechamento.
        -- Reavalia os alvos estáveis; não amplia o número de registros aprovado.
        M.stable(current)
        for i, op in ipairs(current) do
            assert(op.measure.count == job.ops[i].measure.count,
                'O alcance mudou durante a manutenção. Nenhum wipe aplicado; simule novamente.')
        end
        job.ops = current
        job.summary = summarize(current)
        assert(GetPlayerName(source) and actor(source) == job.actor, 'Operador desconectado. Execução cancelada.')
        M.assertStopped()
        local entities = ApexEntities.capture(job.ops)
        M.entitiesPending = #entities > 0
        M.persist('transaction')
        local success = D.transaction(job.ops, job)
        assert(success, 'Transação recusada. Nenhum wipe foi confirmado. Faça uma nova simulação e confira o console.')
        M.persist(M.entitiesPending and 'entity_cleanup_pending' or 'completed')
        local cleaned, warnings = pcall(ApexEntities.cleanup, entities)
        if not cleaned then
            print('[Apex_WIPE] Limpeza de entidades falhou: ' .. tostring(warnings))
            warnings = { 'Wipe no banco concluído. Limpeza de veículos não confirmada; confira o console antes de retomar.' }
        end
        if #warnings > 0 then
            M.resumeBlocked = warnings
            M.persist('entity_cleanup_pending')
        else
            M.entitiesPending = false
            M.persist('completed')
        end
        print(('[Apex_WIPE] Wipe concluído. Job=%s Admin=%s Linhas=%d'):format(job.id, job.actor, job.summary.rows))
        return { id = job.id, rows = job.summary.rows, backup = true,
            message = #warnings == 0
                and ('Wipe concluído com backup. Você será desconectado em %d segundos; os recursos serão retomados automaticamente.'):format(Config.OperatorReconnectSeconds)
                or 'Wipe concluído no banco, com backup. A manutenção permanece ativa para revisar os veículos no console.',
            restartWarnings = warnings }
    end)
    if not ok then
        print('[Apex_WIPE] Execução falhou: ' .. tostring(result))
        -- Auditoria de falha fora da transação; não confunde backup com execução concluída.
        pcall(MySQL.insert.await, [[INSERT INTO apex_wipe_jobs
            (id, actor, actor_name, actor_source, actor_identifiers, actor_character,
                scope, target, reason, status, plan) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'failed', ?)]],
            { job.id, job.actor, job.actorName, job.actorSource, json.encode(job.actorIdentifiers),
                json.encode(job.actorCharacter), job.request.scope,
                job.request.target, job.request.reason, json.encode(job.summary) })
        if M.active then
            CreateThread(function()
                Wait(Config.OperatorReconnectSeconds * 1000)
                local resumed, resumeError = pcall(M.finish)
                if not resumed then print('[Apex_WIPE] Falha na retomada: ' .. tostring(resumeError)) end
                busy = false
            end)
        else busy = false end
        error(result)
    end
    -- Entrega a confirmação pela NUI antes de desconectar o operador.
    CreateThread(function()
        Wait(Config.OperatorReconnectSeconds * 1000)
        local resumed, resumeError = pcall(M.finish)
        if not resumed then print('[Apex_WIPE] Falha na retomada: ' .. tostring(resumeError)) end
        busy = false
    end)
    return result
end)

RegisterCommand(Config.Command, function(source)
    if not admin(source) then
        if source > 0 then TriggerClientEvent('apex_wipe:notify', source, 'Acesso restrito aos admins autorizados.') end
        return
    end
    TriggerClientEvent('apex_wipe:open', source)
end, false)

-- RPC próprio: a interface não depende de ox_lib, QBCore nem ESX.
RegisterNetEvent('apex_wipe:request', function(id, action, input)
    local src = source
    if type(id) ~= 'number' or id % 1 ~= 0 or id < 1 or id > 1000000000 then return end
    local handler = type(action) == 'string' and handlers[action]
    if not handler then return end
    if not admin(src) then
        TriggerClientEvent('apex_wipe:response', src, id, { ok = false, error = 'Acesso restrito aos admins autorizados.' })
        return
    end
    local encoded, content = pcall(json.encode, input or {})
    if not encoded or #content > 8192 or type(input) ~= 'table' then
        TriggerClientEvent('apex_wipe:response', src, id, { ok = false, error = 'Pedido inválido.' })
        return
    end
    local identity = actor(src)
    local result = handler(src, input)
    if GetPlayerName(src) and identity == actor(src) then
        TriggerClientEvent('apex_wipe:response', src, id, result)
    end
end)

RegisterCommand('apex_wipe_resume', function(source)
    if source ~= 0 then return end
    if busy then print('[Apex_WIPE] Aguarde a execução terminar.'); return end
    CreateThread(function() M.recover(true) end)
end, true)

-- Exportação só pelo console. Backups com dados sensíveis não são enviados à NUI.
RegisterCommand('apex_wipe_export', function(source, args)
    if source ~= 0 or not ready or busy then return end
    local id = args[1]
    if not id or not id:match('^[%w%-]+$') or #id > 64 then print('Uso: apex_wipe_export <job-id>'); return end
    CreateThread(function()
        local ok, err = pcall(function()
            local job = MySQL.single.await('SELECT * FROM apex_wipe_jobs WHERE id = ? AND status = ?', { id, 'completed' })
            assert(job, 'Backup concluído não encontrado.')
            local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM apex_wipe_snapshots WHERE job_id = ?', { id }))
            assert(count <= Config.MaxExportRows, 'Backup grande: exporte pelo cliente SQL em lotes.')
            local rows = MySQL.query.await('SELECT table_name, row_data FROM apex_wipe_snapshots WHERE job_id = ? ORDER BY id', { id })
            local content = json.encode({ format = 'Apex_WIPE/1', job = job, snapshots = rows }, { indent = true })
            local path = 'backups/' .. id .. '.json'
            assert(SaveResourceFile(GetCurrentResourceName(), path, content, #content), 'Não foi possível salvar o arquivo de backup.')
            print('[Apex_WIPE] Backup exportado em ' .. path)
        end)
        if not ok then print('[Apex_WIPE] Exportação falhou: ' .. tostring(err)) end
    end)
end, true)

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source
    if not M.active and not busy then return end
    deferrals.defer(); Wait(0)
    deferrals.done('Servidor em manutenção administrativa. Tente novamente mais tarde.')
end)
AddEventHandler('playerDropped', function()
    plans[source] = nil; cooldowns[source] = nil
    requests[source] = nil
end)
AddEventHandler('onResourceStarting', function(name)
    if M.active and not M.resuming and not M.keep(name) then CancelEvent() end
end)

MySQL.ready(function()
    local ok, err = pcall(function() D.initialize(); ApexIntegrations.money(); M.recover() end)
    ready = ok
    if ok then print('[Apex_WIPE] Pronto. Execução: ' .. tostring(Config.ExecutionEnabled))
    else print('[Apex_WIPE] Inicialização falhou: ' .. tostring(err)) end
end)
