-- Manutenção automática: pausa somente resources com código no servidor,
-- mantendo oxmysql, ox_lib e Auren_Wipe vivos para concluir backup + transação.
ApexMaintenance = { active = false, resuming = false, operator = nil, original = {} }
local M = ApexMaintenance
function M.persist(phase)
    M.phase = phase or M.phase or 'preparing'
    SetResourceKvp('apex_wipe_recovery', json.encode({ resources = M.original,
        phase = M.phase, jobId = M.jobId, entitiesPending = M.entitiesPending }))
end

function M.keep(name)
    return name == GetCurrentResourceName() or Config.MaintenanceAllowedResources[name] == true
        or (GetNumResourceMetadata(name, 'server_script') == 0
            and GetNumResourceMetadata(name, 'shared_script') == 0)
end

function M.resources()
    local list = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if GetResourceState(name) == 'started' then list[#list + 1] = name end
    end
    return list
end

local function ordered(names)
    local known, visiting, done, result = {}, {}, {}, {}
    local byLower = {}
    for _, name in ipairs(names) do known[name] = true; byLower[name:lower()] = name end
    -- Integrações opcionais verificadas: o fechamento chama esses exports,
    -- mas os manifests ZSX não declaram as dependências correspondentes.
    local optionalDependencies = {
        zsx_garages = { 'zsx_uiv2', 'vehicledeformation' },
        zsx_dealershipv2 = { 'zsx_uiv2' }
    }
    local function visit(name)
        if done[name] then return end
        assert(not visiting[name], 'Ciclo de dependências entre resources: ' .. name)
        visiting[name] = true
        for _, dependency in ipairs(optionalDependencies[name:lower()] or {}) do
            if byLower[dependency] then visit(byLower[dependency]) end
        end
        -- Includes @resource/arquivo também precisam da biblioteca em execução.
        for _, kind in ipairs({ 'shared_script', 'server_script', 'client_script' }) do
            for i = 0, GetNumResourceMetadata(name, kind) - 1 do
                local entry = GetResourceMetadata(name, kind, i)
                local dependency = type(entry) == 'string' and entry:match('^@([^/]+)/')
                if dependency and known[dependency] and dependency ~= name then visit(dependency) end
            end
        end
        -- Ordem adicional para bases que não declaram todas as dependências.
        if name == 'ox_inventory' or name == 'qbx_vehicles' then
            if known.qbx_core then visit('qbx_core') end
        elseif name ~= 'qbx_core' and not M.keep(name) then
            for _, core in ipairs({ 'qbx_core', 'qbx_vehicles', 'ox_inventory' }) do
                if known[core] then visit(core) end
            end
        end
        for i = 0, GetNumResourceMetadata(name, 'dependency') - 1 do
            local dependency = GetResourceMetadata(name, 'dependency', i)
            if known[dependency] then visit(dependency) end
        end
        visiting[name] = nil; done[name] = true
        result[#result + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do visit(name) end
    return result
end

function M.describe()
    local paused = 0
    for _, name in ipairs(M.resources()) do if not M.keep(name) then paused = paused + 1 end end
    return { resources = paused, players = #GetPlayers(), automatic = Config.AutomaticMaintenance }
end

function M.assertStopped()
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        local state = GetResourceState(name)
        assert(M.keep(name) or (state ~= 'started' and state ~= 'starting'), 'Recurso ainda ativo: ' .. name)
    end
    for _, id in ipairs(GetPlayers()) do
        assert(tonumber(id) == M.operator, 'Jogador ainda conectado: ' .. id)
    end
end

function M.begin(source)
    assert(Config.AutomaticMaintenance, 'Manutenção automática desabilitada pelo responsável.')
    assert(not M.active, 'Manutenção já está em andamento.')
    local names = M.resources()
    M.original = ordered(names) -- valida dependências antes de qualquer efeito.
    M.active = true; M.operator = source
    -- Registra recuperação antes de qualquer parada, inclusive em erro intermediário.
    M.persist('preparing')
    TriggerClientEvent('apex_wipe:maintenance', -1)
    -- Salva jogadores pelo core antes de desconectar e parar seus dependentes.
    ApexIntegrations.savePlayers()
    if GetResourceState('ox_inventory') == 'started' then
        local inventory = exports.ox_inventory:Inventory()
        assert(type(inventory) == 'table' and inventory.SaveInventories ~= nil,
            'Esta versão de ox_inventory não fornece o salvamento de manutenção.')
        inventory.SaveInventories(true, false) -- fecha, trava e aguarda gravação de inventários.
    end
    for _, id in ipairs(GetPlayers()) do
        if tonumber(id) ~= source then DropPlayer(id, 'Manutenção Auren_Wipe. Reconecte após a conclusão.') end
    end
    Wait(Config.SaveDrainMilliseconds)
    -- Impede todos os clientes remanescentes de enviar alterações enquanto pausamos.
    for i = #M.original, 1, -1 do
        local name = M.original[i]
        if not M.keep(name) and GetResourceState(name) == 'started' then
            assert(StopResource(name), 'Não foi possível pausar o recurso: ' .. name)
            Wait(0)
        end
    end
    Wait(Config.SaveDrainMilliseconds)
    M.assertStopped()
end

function M.stable(ops)
    local previous, stableRounds = nil, 0
    for _ = 1, Config.StabilityAttempts do
        M.assertStopped()
        local signature = {}
        for _, op in ipairs(ops) do
            op.measure = ApexDB.measure(op)
            signature[#signature + 1] = { op.table, op.measure.count, op.measure.fingerprint, op.measure.bytes }
        end
        local current = json.encode(signature)
        if current == previous then stableRounds = stableRounds + 1 else stableRounds = 0 end
        if stableRounds >= 2 then return end
        previous = current
        Wait(Config.StabilityInterval)
    end
    error('Dados continuam mudando durante a manutenção. Execução interrompida antes do wipe.')
end

function M.finish()
    local warnings = {}
    if not M.active then return warnings end
    -- Recuperações salvas por versões anteriores também usam a ordem corrigida.
    M.original = ordered(M.original)
    M.resuming = true
    -- A sessão do operador deve terminar ANTES de religar recursos de gameplay.
    -- O resultado já foi enviado à NUI quando finish é chamado no caminho de sucesso.
    local sessions = GetPlayers()
    for _, id in ipairs(sessions) do
        DropPlayer(id, 'Auren_Wipe concluiu a manutenção. Reconecte para carregar os dados atualizados.')
    end
    if #sessions > 0 then
        Wait(500)
    end
    if M.resumeBlocked then
        M.resuming = false
        for _, warning in ipairs(M.resumeBlocked) do print('[Auren_Wipe] ' .. warning) end
        return M.resumeBlocked
    end
    -- Tenta múltiplas passagens para dependências implícitas e recursos parados em cascata.
    for _ = 1, 3 do
        for _, name in ipairs(M.original) do
            if GetResourceState(name) == 'stopped' then StartResource(name); Wait(0) end
        end
        Wait(500)
    end
    for _, name in ipairs(M.original) do
        if GetResourceState(name) ~= 'started' then warnings[#warnings + 1] = 'Recurso não retomado: ' .. name end
    end
    M.resuming = false
    if #warnings == 0 then
        M.active = false; M.operator = nil; M.original = {}
        DeleteResourceKvp('apex_wipe_recovery')
    else
        -- Não reabre a cidade com retomada incompleta. Console mantém rota de recuperação.
        M.persist('resume_pending')
        for _, warning in ipairs(warnings) do print('[Auren_Wipe] ' .. warning) end
    end
    return warnings
end

function M.recover(force)
    local saved = GetResourceKvpString('apex_wipe_recovery')
    if not saved then return end
    local ok, data = pcall(json.decode, saved)
    if not ok or type(data) ~= 'table' or type(data.resources) ~= 'table' then
        print('[Auren_Wipe] Recuperação inválida. Revise o console antes de liberar conexões.'); M.active = true; return
    end
    M.original = data.resources; M.operator = nil; M.active = true
    M.phase = data.phase; M.jobId = data.jobId
    if data.phase == 'entity_cleanup_pending' and not force then
        print('[Auren_Wipe] Banco concluído, mas limpeza de veículos pendente. Revise as entidades e o console antes de apex_wipe_resume.')
        return
    end
    if force then M.resumeBlocked = nil end
    if data.phase == 'transaction' and not force then
        local completed = data.jobId and MySQL.scalar.await('SELECT COUNT(*) FROM apex_wipe_jobs WHERE id = ? AND status = ?', { data.jobId, 'completed' })
        if tonumber(completed) ~= 1 then
            print('[Auren_Wipe] Transação interrompida com resultado incerto. Verifique job ' .. tostring(data.jobId)
                .. ' no banco antes de executar apex_wipe_resume no console.')
            return
        end
    end
    if data.entitiesPending and not force then
        print('[Auren_Wipe] Limpeza de veículos não confirmada após interrupção. Revise o job e as entidades antes de apex_wipe_resume.')
        return
    end
    local warnings = M.finish()
    print('[Auren_Wipe] Recuperação de manutenção: ' .. (#warnings == 0 and 'concluída.' or 'requer atenção no console.'))
end
