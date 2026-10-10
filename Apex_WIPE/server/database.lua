ApexDB = {}
local D, P = ApexDB, ApexPlanner

function D.initialize()
    -- Somente estas três tabelas próprias são criadas. Sem ALTER no gameplay.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS apex_wipe_jobs (
        id VARCHAR(64) NOT NULL PRIMARY KEY, actor VARCHAR(100) NOT NULL,
        actor_name VARCHAR(100) NOT NULL, scope VARCHAR(20) NOT NULL,
        actor_source INT DEFAULT NULL, actor_identifiers LONGTEXT DEFAULT NULL,
        actor_character LONGTEXT DEFAULT NULL,
        target VARCHAR(100) NOT NULL, reason VARCHAR(250) NOT NULL,
        status VARCHAR(20) NOT NULL, plan LONGTEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Migração automática exclusivamente da auditoria própria, para upgrades.
    for name, definition in pairs({ actor_source = 'INT DEFAULT NULL',
        actor_identifiers = 'LONGTEXT DEFAULT NULL', actor_character = 'LONGTEXT DEFAULT NULL' }) do
        local exists = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'apex_wipe_jobs' AND COLUMN_NAME = ?]], { name })
        if tonumber(exists) == 0 then
            MySQL.query.await('ALTER TABLE apex_wipe_jobs ADD COLUMN ' .. P.identifier(name) .. ' ' .. definition)
        end
    end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS apex_wipe_snapshots (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        job_id VARCHAR(64) NOT NULL, table_name VARCHAR(64) NOT NULL,
        row_data LONGTEXT NOT NULL, INDEX job_idx (job_id),
        CONSTRAINT apex_wipe_job_fk FOREIGN KEY (job_id)
        REFERENCES apex_wipe_jobs(id) ON DELETE RESTRICT
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS apex_wipe_guards (
        id INT NOT NULL PRIMARY KEY
    ) ENGINE=InnoDB]])
    MySQL.query.await('INSERT IGNORE INTO apex_wipe_guards (id) VALUES (1)')
    for _, name in ipairs({ 'apex_wipe_jobs', 'apex_wipe_snapshots', 'apex_wipe_guards' }) do
        local engine = MySQL.scalar.await('SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { name })
        assert(engine == 'InnoDB', 'Tabela de backup precisa ser InnoDB: ' .. name)
    end
    local primary = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'apex_wipe_guards'
        AND COLUMN_NAME = 'id' AND COLUMN_KEY = 'PRI']])
    assert(tonumber(primary) == 1, 'Tabela de guardas incompatível; chave primária ausente.')
end

function D.schema()
    local tables = MySQL.query.await([[SELECT TABLE_NAME AS name, ENGINE AS engine,
        TABLE_TYPE AS kind FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()]])
    local columns = MySQL.query.await([[SELECT TABLE_NAME AS table_name, COLUMN_NAME AS name,
        DATA_TYPE AS kind, EXTRA AS extra FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() ORDER BY TABLE_NAME, ORDINAL_POSITION]])
    local triggers = MySQL.query.await([[SELECT EVENT_OBJECT_TABLE AS table_name, TRIGGER_NAME AS name
        FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE()]])
    local foreign = MySQL.query.await([[SELECT TABLE_NAME AS child, COLUMN_NAME AS child_column,
        REFERENCED_TABLE_NAME AS parent, REFERENCED_COLUMN_NAME AS parent_column,
        CONSTRAINT_NAME AS name, REFERENCED_TABLE_SCHEMA AS parent_schema
        FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA = DATABASE()
        AND REFERENCED_TABLE_NAME IS NOT NULL]])
    -- Inclui referências vindas de outros schemas, se visíveis ao usuário do banco.
    local external = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE
        WHERE REFERENCED_TABLE_SCHEMA = DATABASE() AND TABLE_SCHEMA <> DATABASE()]])
    local result = { tables = {}, foreign = foreign, external = tonumber(external) or 0 }
    for _, t in ipairs(tables) do result.tables[t.name] = { engine = t.engine, kind = t.kind, columns = {}, triggers = {} } end
    for _, col in ipairs(columns) do
        local t = result.tables[col.table_name]
        if t then t.columns[#t.columns + 1] = col end
    end
    for _, trigger in ipairs(triggers) do
        local t = result.tables[trigger.table_name]
        if t then t.triggers[#t.triggers + 1] = trigger.name end
    end
    return result
end

function D.inspect(ops, schema)
    for _, name in ipairs({ 'apex_wipe_jobs', 'apex_wipe_snapshots', 'apex_wipe_guards' }) do
        local t = schema.tables[name]
        assert(t and t.kind == 'BASE TABLE' and t.engine == 'InnoDB', 'Auditoria incompatível: ' .. name)
        assert(#t.triggers == 0, 'Trigger detectado na auditoria: ' .. name)
    end
    local planned = {}
    for _, op in ipairs(ops) do planned[op.table] = op end
    for _, op in ipairs(ops) do
        local t = schema.tables[op.table]
        assert(t and t.kind == 'BASE TABLE', 'Tabela ausente ou incompatível: ' .. op.table)
        assert(t.engine == 'InnoDB', 'Wipe exige InnoDB: ' .. op.table)
        assert(#t.triggers == 0, 'Trigger detectado em ' .. op.table .. '. Revise externamente antes de continuar.')
        local names, expression = {}, {}
        for _, col in ipairs(t.columns) do
            names[col.name] = true
            assert(not col.kind:match('blob') and col.kind ~= 'binary' and col.kind ~= 'varbinary'
                and col.kind ~= 'bit' and col.kind ~= 'geometry', 'Backup JSON não suporta coluna binária: ' .. op.table .. '.' .. col.name)
            local extra = (col.extra or ''):upper()
            assert(not extra:find('VIRTUAL GENERATED', 1, true)
                and not extra:find('STORED GENERATED', 1, true)
                and not extra:find('PERSISTENT GENERATED', 1, true),
                'Coluna gerada exige adaptador de backup: ' .. op.table .. '.' .. col.name)
            P.identifier(col.name)
            -- Nomes de coluna vêm do schema, mas ainda são validados.
            expression[#expression + 1] = "'" .. col.name .. "', " .. P.identifier(col.name)
        end
        if op.relation then assert(names[op.relation], 'Coluna ausente: ' .. op.table .. '.' .. op.relation) end
        if op.table == 'players' then assert(names.citizenid, 'players.citizenid ausente.') end
        if op.table == 'ox_inventory' then assert(names.name and names.owner and names.data, 'Schema de ox_inventory incompatível.') end
        if op.table == 'player_vehicles' then assert(names.citizenid and names.garage, 'Schema de veículos incompatível.') end
        if op.table == 'player_vehicles' and op.mode == 'delete' then
            assert(names.id and names.plate, 'Remoção de veículos exige id e plate para limpar entidades persistentes.')
        end
        for _, change in ipairs(op.changes or {}) do assert(names[change.column], 'Coluna ausente: ' .. op.table .. '.' .. change.column) end
        op.rowExpression = 'JSON_OBJECT(' .. table.concat(expression, ', ') .. ')'
        op.schemaSignature = json.encode(t.columns)
        op.incoming = {}
        if op.mode == 'delete' then
            assert(schema.external == 0, 'Referências externas ao banco detectadas; revise antes de remover registros.')
            for _, fk in ipairs(schema.foreign) do
                if fk.parent == op.table then
                    local child = planned[fk.child]
                    assert(child and child.mode == 'delete', 'Relação não coberta pelo plano: ' .. fk.child .. ' → ' .. op.table)
                    -- Cada relação recebe uma guarda de ausência após excluir seus filhos.
                    op.incoming[#op.incoming + 1] = fk
                end
            end
        end
    end
    -- Ordenação topológica por FK. Ciclos são rejeitados, sem desabilitar constraints.
    local ordered, done = {}, {}
    local function visit(op, visiting)
        if done[op.table] then return end
        assert(not visiting[op.table], 'Ciclo de foreign keys: ' .. op.table)
        visiting[op.table] = true
        for _, fk in ipairs(op.incoming) do visit(planned[fk.child], visiting) end
        visiting[op.table] = nil
        done[op.table] = true
        ordered[#ordered + 1] = op
    end
    for _, op in ipairs(ops) do visit(op, {}) end
    return ordered
end

function D.measure(op)
    local row = op.rowExpression
    local sql = ('SELECT COUNT(*) AS n, COALESCE(BIT_XOR(CRC32(CAST(%s AS CHAR))), 0) AS fingerprint, '
        .. 'COALESCE(SUM(OCTET_LENGTH(CAST(%s AS CHAR))), 0) AS bytes FROM %s WHERE %s')
        :format(row, row, P.identifier(op.table), op.where)
    local result = MySQL.single.await(sql, op.values)
    return { count = tonumber(result.n), fingerprint = tostring(result.fingerprint), bytes = tonumber(result.bytes) }
end

function D.transaction(ops, job)
    local queries = {}
    local function push(sql, values) queries[#queries + 1] = { query = sql, values = values or {} } end
    -- A sentinela é garantida dentro da própria transação, antes de testar alcance.
    push('INSERT IGNORE INTO apex_wipe_guards (id) VALUES (1)')
    push([[INSERT INTO apex_wipe_jobs (id, actor, actor_name, actor_source, actor_identifiers,
        actor_character, scope, target, reason, status, plan)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'completed', ?)]],
        { job.id, job.actor, job.actorName, job.actorSource, json.encode(job.actorIdentifiers),
            json.encode(job.actorCharacter), job.request.scope, job.request.target, job.request.reason, json.encode(job.summary) })
    -- Bloqueia linhas de todos os alvos antes das guardas e dos backups.
    for _, op in ipairs(ops) do
        push('SELECT 1 FROM ' .. P.identifier(op.table) .. ' WHERE ' .. op.where .. ' FOR UPDATE', op.values)
    end
    for _, op in ipairs(ops) do
        -- Uma alteração desde a revisão causa chave duplicada e rollback integral.
        push(('INSERT INTO apex_wipe_guards (id) SELECT 1 WHERE '
            .. '(SELECT COUNT(*) FROM %s WHERE %s) <> ? OR '
            .. '(SELECT COALESCE(BIT_XOR(CRC32(CAST(%s AS CHAR))), 0) FROM %s WHERE %s) <> ?')
            :format(P.identifier(op.table), op.where, op.rowExpression, P.identifier(op.table), op.where),
            (function()
                local v = {}
                for _, x in ipairs(op.values) do v[#v + 1] = x end
                v[#v + 1] = op.measure.count
                for _, x in ipairs(op.values) do v[#v + 1] = x end
                v[#v + 1] = op.measure.fingerprint
                return v
            end)())
    end
    -- Todos os backups são feitos antes de qualquer mutação.
    for _, op in ipairs(ops) do
        local values = { job.id, op.table }
        for _, v in ipairs(op.values) do values[#values + 1] = v end
        push(('INSERT INTO apex_wipe_snapshots (job_id, table_name, row_data) SELECT ?, ?, %s FROM %s WHERE %s')
            :format(op.rowExpression, P.identifier(op.table), op.where), values)
    end
    for _, op in ipairs(ops) do
        for _, fk in ipairs(op.incoming) do
            -- Guarda global conservadora: não permite cascata remanescente.
            -- Para alvo seletivo, correlaciona somente os pais do plano.
            push(('INSERT INTO apex_wipe_guards (id) SELECT 1 WHERE EXISTS ('
                .. 'SELECT 1 FROM %s c JOIN (SELECT * FROM %s WHERE %s) p ON c.%s = p.%s)')
                :format(P.identifier(fk.child), P.identifier(op.table), op.where,
                    P.identifier(fk.child_column), P.identifier(fk.parent_column)), op.values)
        end
        local sql, values = P.mutation(op)
        push(sql, values)
    end
    return MySQL.transaction.await(queries)
end
