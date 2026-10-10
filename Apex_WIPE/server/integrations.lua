ApexIntegrations = {}
local I = ApexIntegrations
-- Bridges opcionais: nenhuma dependência rígida de framework.
function I.core()
    if GetResourceState('qbx_core') == 'started' then return 'qbx_core' end
    if GetResourceState('qb-core') == 'started' then return 'qb-core' end
end

function I.player(source)
    local core = I.core()
    if core == 'qbx_core' then return exports.qbx_core:GetPlayer(source) end
    if core == 'qb-core' then return exports['qb-core']:GetCoreObject().Functions.GetPlayer(source) end
end

function I.permission(source)
    local core = I.core()
    if not core then return false end
    for _, permission in ipairs({ 'god', 'admin' }) do
        local ok, allowed = pcall(function()
            if core == 'qbx_core' then return exports.qbx_core:HasPermission(source, permission) end
            return exports['qb-core']:GetCoreObject().Functions.HasPermission(source, permission)
        end)
        if ok and allowed then return true end
    end
    return false
end

function I.savePlayers()
    local core = I.core()
    if not core then return end
    for _, id in ipairs(GetPlayers()) do
        local source = tonumber(id)
        local player = I.player(source)
        if player then
            if core == 'qbx_core' then exports.qbx_core:Save(source)
            else player.Functions.Save() end
        end
    end
end
-- Dados pessoais conhecidos; imóveis e tabelas mistas de banco NÃO entram.
local builtins = {
    playerskins = 'citizenid', player_outfits = 'citizenid', player_mails = 'citizenid',
    npwd_calls = 'identifier', npwd_darkchat_channel_members = 'user_identifier',
    npwd_marketplace_listings = 'identifier', npwd_messages_participants = 'participant',
    npwd_notes = 'identifier', npwd_phone_contacts = 'identifier', npwd_phone_gallery = 'identifier',
    npwd_twitter_profiles = 'identifier', npwd_match_profiles = 'identifier'
}

function I.coreConfig()
    -- Apenas leitura de literais conhecidos. Não executa o arquivo de outro resource.
    local core = I.core()
    local text = core == 'qb-core' and LoadResourceFile('qb-core', 'config.lua')
        or LoadResourceFile('qbx_core', 'config/server.lua')
    if not text then return nil end
    return text:gsub('%-%-%[%[.-%]%]', ''):gsub('%-%-[^\r\n]*', '')
end

function I.money()
    local result = { cash = 0, bank = 0, crypto = 0 }
    local text = I.coreConfig()
    local block = text and (text:match('moneyTypes%s*=%s*(%b{})') or text:match('MoneyTypes%s*=%s*(%b{})'))
    if block then
        for key in block:gmatch('([%a_][%w_]*)%s*=%s*[%-%d%.]+') do result[key] = 0 end
        for key in block:gmatch('%[%s*[\'"]([%a_][%w_]*)[\'"]%s*%]%s*=') do result[key] = 0 end
    end
    Config.StartingMoney = result
end

function I.adapters(schema)
    local result, seen = {}, {}
    local text = I.coreConfig()
    local block = text and text:match('characterDataTables%s*=%s*(%b{})')
    if block and schema then
        for name, column in block:gmatch('{%s*[\'"]([%w_]+)[\'"]%s*,%s*[\'"]([%w_]+)[\'"]%s*}') do
            if builtins[name] == column and schema.tables[name] then
                result[#result + 1] = { table = name, citizenColumn = column, reviewed = true }
                seen[name] = true
            end
        end
    end
    -- Aparência padrão também é segura quando a lista do core usa outro formato.
    if schema then
        for _, name in ipairs({ 'playerskins', 'player_outfits', 'player_mails' }) do
            if schema.tables[name] and not seen[name] then
                result[#result + 1] = { table = name, citizenColumn = builtins[name], reviewed = true }
                seen[name] = true
            end
        end
    end
    for _, adapter in ipairs(Config.CharacterAdapters) do
        assert(not seen[adapter.table], 'Adaptador já detectado automaticamente: ' .. adapter.table)
        result[#result + 1] = adapter
        seen[adapter.table] = true
    end
    table.sort(result, function(a, b) return a.table < b.table end)
    return result
end
