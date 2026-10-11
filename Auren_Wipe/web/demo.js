/* Sandbox visual. Não carrega credenciais, não faz fetch, não acessa FiveM. */
window.ApexDemo = (() => {
  const players = [
    { target: 'MRI7A2F9', label: 'Lucas Andrade' },
    { target: 'MRI8B3D1', label: 'Marina Costa' },
    { target: 'MRI2C4E8', label: 'Rafael Martins' },
    { target: 'MRI5D6F2', label: 'Sofia Oliveira' }
  ];
  const stashes = [
    { target: 'police_evidence', owner: '', label: 'police_evidence' },
    { target: 'mechanic_storage', owner: '', label: 'mechanic_storage' },
    { target: 'personal_locker', owner: 'MRI7A2F9', label: 'personal_locker' }
  ];
  const garages = [
    { target: 'pillboxgarage', label: 'pillboxgarage', count: 28 },
    { target: 'legionsquare', label: 'legionsquare', count: 16 },
    { target: 'motelgarage', label: 'motelgarage', count: 12 }
  ];
  const history = [
    { id: 'demo-9f80c2a1', actorName: 'Apex Admin', scope: 'player', target: 'MRI2C4E8', reason: 'Reinício solicitado pelo personagem.', status: 'completed', createdAt: '2026-10-10 14:32:00' },
    { id: 'demo-3d45b219', actorName: 'Apex Admin', scope: 'stash', target: 'mechanic_storage', reason: 'Organização dos itens da oficina.', status: 'completed', createdAt: '2026-10-09 18:20:00' },
    { id: 'demo-a1200f72', actorName: 'Apex Admin', scope: 'garage', target: 'pillboxgarage', reason: 'Revisão do inventário dos veículos.', status: 'failed', createdAt: '2026-10-08 11:08:00' }
  ];
  let currentPlan;
  const demoActor = { actorLicense: 'license:DEMO-000000000000000000000000000000000000',
    actorSource: 1, actorIdentifiers: { license: 'license:DEMO-000000000000000000000000000000000000',
      license2: 'license2:DEMO-00000000000000000000000000000000000', discord: 'discord:DEMO-123456789', fivem: 'fivem:DEMO-12345' },
    actorCharacter: { citizenid: 'MRI7A2F9', name: 'Lucas Andrade' } };
  history.forEach(row => Object.assign(row, demoActor));
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const clone = value => JSON.parse(JSON.stringify(value));
  async function api(action, input = {}) {
    await wait(action === 'execute' ? 2800 : 500);
    if (action === 'bootstrap') return clone({ serverName: 'MRI QBOX', adminName: 'Apex Admin',
      history, compatibility: ['players', 'player_groups', 'player_vehicles', 'ox_inventory'].map(table => ({ table, present: true, engine: 'InnoDB', triggers: table === 'player_vehicles' ? 3 : 0, automatic: true })),
      protectedTables: ['bans', 'users', 'bank_accounts', 'mri_script_config', 'management_funds', 'phone_settings', 'housing_config', 'apex_wipe_jobs'],
      blockers: [], executionEnabled: true, canExecute: true, characterReviewed: true, planLifetime: 180,
      stats: { players: 1284, vehicles: 2637, stashes: 186, jobs: history.length } });
    if (action === 'search') {
      const source = input.kind === 'player' ? players : input.kind === 'stash' ? stashes : garages;
      const term = String(input.term || '').toLowerCase();
      return clone(source.filter(row => (row.target + ' ' + row.label).toLowerCase().includes(term)));
    }
    if (action === 'preview') {
      const request = clone(input), m = request.modules, all = request.scope === 'server';
      if (!all && !request.target.trim()) throw new Error('Informe um alvo para simular.');
      if (request.reason.trim().length < 8) throw new Error('Descreva o motivo com pelo menos 8 caracteres.');
      const operations = [];
      const add = (table, label, count, mode, columns = []) => operations.push({ table, label, count, mode, columns });
      if (m.characters) {
        add('properties', 'Imóveis: propriedade e acessos', all ? 412 : 2, 'update', ['owner_citizenid', 'has_access', 'for_sale']);
        add('ox_doorlock', 'Portas: acessos pessoais', all ? 83 : 3, 'update', ['data']);
        add('player_groups', 'Vínculos de empregos e gangs', all ? 1601 : 2, 'delete');
        add('player_vehicles', 'Veículos e seus compartimentos', all ? 2637 : 3, 'delete');
        add('ox_inventory', m.stashes ? 'Conteúdo dos baús (cadastros mantidos)' : 'Baús pessoais dos personagens', all ? 186 : 1, 'update', ['data']);
        add('players', 'Personagens', all ? 1284 : 1, 'delete');
      } else {
        if (m.vehicles || m.vehicleStorage) add('player_vehicles', m.vehicles ? 'Veículos e seus compartimentos' : 'Porta-malas e porta-luvas', all ? 2637 : request.scope === 'garage' ? 28 : 3, m.vehicles ? 'delete' : 'update', m.vehicles ? [] : ['trunk', 'glovebox']);
        if (m.stashes) add('ox_inventory', 'Conteúdo dos baús (cadastros mantidos)', all ? 186 : 1, 'update', ['data']);
        if (m.inventory || m.money) add('players', 'Inventários / saldos dos personagens', all ? 1284 : 1, 'update', [m.inventory && 'inventory', m.money && 'money'].filter(Boolean));
      }
      if (!operations.length) throw new Error('Selecione ao menos uma categoria.');
      const automation = [];
      if (m.characters) {
        automation.push('Imóveis: proprietário e chaves limpos; cadastros, preço e estrutura preservados.');
        automation.push('Portas e baús dos imóveis tratados automaticamente, com backup.');
      }
      if (m.characters || m.vehicles || m.vehicleStorage) {
        add('police_impound', 'Pátio da polícia: efeitos automáticos da garagem', all ? 42 : 1,
            m.vehicleStorage && !m.characters && !m.vehicles ? 'trigger' : 'delete');
        automation.push('RHD Garage: registros do pátio incluídos no backup automaticamente.');
        if (m.characters || m.vehicles) {
          add('vehicle_financing', 'Financiamentos dos veículos', all ? 81 : 1, 'delete');
          automation.push('Financiamentos vinculados incluídos automaticamente.');
        }
      }
      const rows = operations.reduce((sum, op) => sum + op.count, 0);
      currentPlan = { id: 'demo-' + Date.now().toString(16), request,
        summary: { rows, bytes: rows * 780, operations }, blockers: [],
        confirmation: 'WIPE ' + (all ? 'SERVIDOR' : request.target), expiresIn: 180, automation };
      return clone(currentPlan);
    }
    if (action === 'execute') {
      if (!currentPlan || input.id !== currentPlan.id || input.confirmation !== currentPlan.confirmation || !input.backupAcknowledged) throw new Error('A confirmação não corresponde ao plano.');
      const result = { id: currentPlan.id, rows: currentPlan.summary.rows, backup: true,
        message: 'Simulação concluída. Nenhum dado real foi alterado.', restartWarnings: [] };
      const now = new Date();
      history.unshift({ id: currentPlan.id, actorName: 'Apex Admin', scope: currentPlan.request.scope,
        target: currentPlan.request.target, reason: currentPlan.request.reason, status: 'completed',
        createdAt: now.toLocaleString('sv-SE', { timeZone: 'America/Sao_Paulo' }), ...clone(demoActor), plan: clone(currentPlan.summary) });
      history.splice(30);
      currentPlan = null;
      return result;
    }
    return {};
  }
  return { api };
})();
