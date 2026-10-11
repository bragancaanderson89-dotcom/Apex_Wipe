Config = {}

Config.Command = 'apexwipe'
Config.AdminAce = 'apex.wipe.admin'
-- Admins padrão da MRI QBOX são reconhecidos automaticamente.
Config.InheritedAdminAces = { 'admin', 'god', 'command' }
Config.ExecuteAce = nil -- nil: qualquer admin reconhecido pode executar.
Config.ServerName = 'MRI QBOX'

-- Pronto para uso. Nenhuma destas opções precisa ser editada na base padrão.
Config.ExecutionEnabled = true
Config.AutomaticMaintenance = true
Config.SaveDrainMilliseconds = 2500
Config.StabilityInterval = 1500
Config.StabilityAttempts = 8
Config.OperatorReconnectSeconds = 15
Config.PlanLifetime = 180
Config.MaxBackupRows = 50000
Config.MaxBackupBytes = 64 * 1024 * 1024
Config.RequestCooldown = 1000
Config.MaxExportRows = 50000
Config.StartingMoney = { cash = 0, bank = 0, crypto = 0 }

-- Só infraestrutura sem gravação de gameplay pode permanecer ativa.
-- NÃO adicione qbx_core, ox_inventory, garages, phones ou scripts de gameplay.
Config.MaintenanceAllowedResources = {
    Auren_Wipe = true, oxmysql = true, ox_lib = true,
    monitor = true, sessionmanager = true, mapmanager = true,
    spawnmanager = true, chat = true, hardcap = true, rconlog = true,
    ['basic-gamemode'] = true, baseevents = true
}

-- Tabelas protegidas jamais podem ser usadas por adaptadores.
Config.ProtectedTables = {
    'bans', 'users', 'accounts', 'management_funds', 'bank_accounts',
    'banking_accounts', 'server_settings', 'script_settings', 'config', 'settings'
}

-- Personagens removidos também podem possuir dados de recursos externos.
-- Esses recursos NÃO são adivinhados. Cadastre apenas dados do personagem,
-- após conferir o SQL do recurso. O adaptador abaixo é só documentação.
-- Todos os adaptadores cadastrados são obrigatórios ao remover personagens.
Config.CharacterAdapters = {
    -- { table = 'my_phone_messages', citizenColumn = 'citizenid', reviewed = true }
}

-- Adaptadores padrão de aparência e NPWD são detectados automaticamente.
-- Recursos externos desconhecidos continuam protegidos ou bloqueiam a ação.
