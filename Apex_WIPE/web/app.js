(() => {
  'use strict';
  const $ = selector => document.querySelector(selector);
  const $$ = selector => Array.from(document.querySelectorAll(selector));
  $('#app').hidden = true;
  $('#app').dataset.open = 'false';
  $('#modal-layer').hidden = true;
  $('#closed-preview').hidden = true;
  const DEMO = window.ApexVisibility?.preview === true;
  const icons = {
    grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    layers: '<path d="m12 3 10 5-10 5L2 8l10-5Z"/><path d="m2 12 10 5 10-5M2 16l10 5 10-5"/>',
    history: '<path d="M3 11a9 9 0 1 1 2.6 7.4M3 4v7h7M12 7v5l3 2"/>',
    shield: '<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Z"/><path d="m8 12 3 3 5-6"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/>',
    refresh: '<path d="M20 8a8 8 0 0 0-14-3L3 8m0-5v5h5M4 16a8 8 0 0 0 14 3l3-3m0 5v-5h-5"/>',
    close: '<path d="m6 6 12 12M6 18 18 6"/>',
    user: '<circle cx="12" cy="7" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
    box: '<path d="m12 3 9 5v9l-9 5-9-5V8l9-5Z"/><path d="m3 8 9 5 9-5M12 13v9M7.5 5.5l9 5"/>',
    car: '<path d="m5 7 2-4h10l2 4M3 10l2-3h14l2 3v8H3v-8Z"/><path d="M6 18v3m12-3v3M6 13h2m8 0h2M3 10h18"/>',
    server: '<rect x="3" y="3" width="18" height="7" rx="2"/><rect x="3" y="14" width="18" height="7" rx="2"/><path d="M7 6.5h.01M7 17.5h.01M12 6.5h5M12 17.5h5"/>',
    search: '<circle cx="10.5" cy="10.5" r="7.5"/><path d="m16 16 5 5"/>',
    arrow: '<path d="M4 12h16m-6-6 6 6-6 6"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
    scan: '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5M7 12h10M12 7v10"/>',
    download: '<path d="M12 3v12m-5-5 5 5 5-5M4 17v4h16v-4"/>',
    database: '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 4 18 4 18 0V5M3 12c0 4 18 4 18 0"/>',
    wallet: '<path d="M21 7H5a2 2 0 0 1 0-4h13v4M3 5v14a2 2 0 0 0 2 2h16V7M21 12h-7v5h7M17 14.5h.01"/>',
    bag: '<path d="M5 8h14l2 13H3L5 8ZM8 8V6a4 4 0 0 1 8 0v2"/>',
    warning: '<path d="m12 3 10 18H2L12 3Z"/><path d="M12 9v5m0 3h.01"/>'
  };
  const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name] || icons.info}</svg>`;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
  const number = value => new Intl.NumberFormat('pt-BR').format(value);
  const scopeNames = { player: 'Personagem', stash: 'Baú', garage: 'Garagem', server: 'Servidor inteiro' };
  const pageNames = { overview: 'Visão geral', wipe: 'Wipe seletivo', history: 'Histórico', protections: 'Proteções' };
  const catalog = {
    inventory: { name: 'Inventário', hint: 'Itens do personagem', icon: 'bag' },
    money: { name: 'Dinheiro', hint: 'Zerar moedas detectadas no core', icon: 'wallet' },
    vehicles: { name: 'Veículos', hint: 'Remover veículos e conteúdos', icon: 'car' },
    vehicleStorage: { name: 'Compartimentos', hint: 'Porta-malas e porta-luvas', icon: 'box' },
    stashes: { name: 'Conteúdo de baús', hint: 'Cadastros e estrutura mantidos', icon: 'box' },
    characters: { name: 'Remover personagem', hint: 'Inclui vínculos conhecidos e baús pessoais', icon: 'warning' }
  };
  const state = { scope: 'player', page: 'wipe', modules: new Set(['inventory']), bootstrap: null,
    plan: null, loading: false, executing: false, modalOpener: null, selectedLabel: '', searchSeq: 0, searchTimer: null };
  let expiryTimer;
  function hydrateIcons(root = document) { root.querySelectorAll('[data-icon]').forEach(node => { node.innerHTML = icon(node.dataset.icon); }); }
  function toast(message, kind = 'info') {
    const node = document.createElement('div'); node.className = 'toast';
    node.innerHTML = icon(kind === 'error' ? 'warning' : 'info') + `<span>${esc(message)}</span>`;
    $('#toast-region').append(node);
    setTimeout(() => { node.classList.add('toast-out'); setTimeout(() => node.remove(), 300); }, 5500);
  }
  async function api(action, payload) {
    if (DEMO) return window.ApexDemo.api(action, payload);
    if (typeof GetParentResourceName !== 'function') throw new Error('Abra DEV.HTML para visualizar a demonstração.');
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), action === 'execute' ? 240000 : 30000);
    try {
      const response = await fetch(`https://${GetParentResourceName()}/${action}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {}), signal: controller.signal
      });
      if (!response.ok) throw new Error('Falha na comunicação com o servidor.');
      const result = await response.json();
      if (!result.ok) throw new Error(result.error || 'Solicitação recusada.');
      return result.data;
    } catch (error) {
      if (error.name === 'AbortError') throw new Error(action === 'execute'
        ? 'A resposta demorou. O resultado é incerto; confira o histórico e o console antes de uma nova operação.'
        : 'O servidor não respondeu a tempo.');
      throw error;
    } finally { clearTimeout(timeout); }
  }
  function setLoading(value) {
    state.loading = value;
    $('#preview').disabled = value;
    $('#search').disabled = value;
    $('#refresh').disabled = value;
    $('#preview').innerHTML = value ? `${icon('refresh')}Preparando plano…` : `${icon('scan')}Simular e revisar<span class="button-arrow">↗</span>`;
  }
  function invalidate() { state.plan = null; $('#impact-count').textContent = '—'; }
  function changePage(page) {
    if (state.executing) return;
    state.page = page;
    $$('.page').forEach(node => { node.hidden = node.id !== 'page-' + page; });
    $$('.nav-item').forEach(node => node.classList.toggle('active', node.dataset.page === page));
    $('#breadcrumb-page').textContent = pageNames[page];
    $('#main-content').scrollTop = 0;
  }
  function availableModules() {
    if (state.scope === 'stash') return ['stashes'];
    if (state.scope === 'garage') return ['vehicleStorage', 'vehicles'];
    return ['inventory', 'money', 'vehicleStorage', 'vehicles', ...(state.scope === 'server' ? ['stashes'] : []), 'characters'];
  }
  function renderModules() {
    $('#module-options').innerHTML = availableModules().map(key => {
      const item = catalog[key], disabled = state.modules.has('characters') && ['inventory', 'money', 'vehicleStorage', 'vehicles'].includes(key);
      return `<label class="module-option ${key === 'characters' ? 'danger' : ''} ${state.modules.has(key) ? 'selected' : ''} ${disabled ? 'disabled' : ''}"><input type="checkbox" data-module="${key}" ${state.modules.has(key) ? 'checked' : ''} ${disabled ? 'disabled' : ''}><span><strong>${esc(item.name)}</strong><small>${esc(item.hint)}</small></span>${icon(item.icon)}</label>`;
    }).join('');
    const count = state.modules.size;
    $('#summary-modules').textContent = `${count} ${count === 1 ? 'selecionada' : 'selecionadas'}`;
    $('#select-all').textContent = availableModules().filter(k => k !== 'characters' && k !== 'vehicles').every(k => state.modules.has(k)) ? 'Limpar seleção' : 'Selecionar reinícios';
  }
  function changeScope(scope) {
    if (state.loading || state.executing) return;
    state.scope = scope;
    state.modules = new Set([scope === 'stash' ? 'stashes' : scope === 'garage' ? 'vehicleStorage' : 'inventory']);
    $('#target').value = ''; $('#owner').value = ''; state.selectedLabel = '';
    state.searchSeq++; clearTimeout(state.searchTimer); $('#search-results').hidden = true;
    $('#target-fields').hidden = scope === 'server'; $('#server-target').hidden = scope !== 'server';
    $('#owner-field').hidden = scope !== 'stash';
    const labels = {
      player: ['Personagem', 'Informe o citizenid ou busque um personagem', 'O citizenid identifica um personagem específico, mesmo offline.'],
      stash: ['Identificador do baú', 'Ex.: police_evidence', 'Use o nome exato salvo no banco. A busca mostra os proprietários.'],
      garage: ['Identificador da garagem', 'Ex.: pillboxgarage', 'São alterados os veículos desta garagem; sua configuração permanece.']
    };
    if (scope !== 'server') {
      $('#target-label').textContent = labels[scope][0]; $('#target').placeholder = labels[scope][1]; $('#target-hint').textContent = labels[scope][2];
      $('#target').maxLength = scope === 'player' ? 50 : 100;
    }
    $$('.scope-card').forEach(node => {
      const selected = node.dataset.scope === scope;
      node.classList.toggle('selected', selected); node.setAttribute('aria-pressed', String(selected));
    });
    $('#summary-scope').textContent = scopeNames[scope];
    $('.configuration .tag').textContent = scope === 'server' ? 'GLOBAL' : 'SELETIVO';
    invalidate(); renderModules();
  }
  async function search() {
    if (state.loading || state.executing || state.scope === 'server') return;
    const seq = ++state.searchSeq, scope = state.scope, term = $('#target').value.trim();
    $('#search').disabled = true;
    try {
      const rows = await api('search', { kind: scope, term });
      if (seq !== state.searchSeq || scope !== state.scope || term !== $('#target').value.trim()) return;
      $('#search-results').hidden = false;
      $('#search-results').innerHTML = rows.length ? rows.map((row, i) => `<button class="search-result" data-result="${i}">${icon(scope === 'player' ? 'user' : scope === 'stash' ? 'box' : 'car')}<span><strong>${esc(row.label || row.target)}</strong><small>${esc(row.target)}${scope === 'stash' ? ' · ' + esc(row.owner || 'Compartilhado') : scope === 'garage' ? ' · ' + esc(row.count) + ' veículos' : ''}</small></span><span>↗</span></button>`).join('') : '<div class="search-empty">Nenhum resultado. Você também pode informar o identificador exato.</div>';
      $$('#search-results [data-result]').forEach(button => button.addEventListener('click', () => {
        const row = rows[Number(button.dataset.result)];
        $('#target').value = row.target; $('#owner').value = row.owner || '';
        state.selectedLabel = row.label; $('#search-results').hidden = true;
        state.searchSeq++; invalidate();
      }));
    } catch (error) { if (seq === state.searchSeq) toast(error.message, 'error'); }
    finally { $('#search').disabled = state.loading; }
  }
  function openModal(html) {
    state.modalOpener = document.activeElement;
    $('#modal-content').innerHTML = html; $('#modal-layer').hidden = false;
    $('#modal-close').disabled = false;
    requestAnimationFrame(() => $('.modal').focus());
  }
  function closeModal() {
    if (state.executing) return;
    $('#modal-layer').hidden = true; clearInterval(expiryTimer);
    if (state.modalOpener?.isConnected) state.modalOpener.focus();
  }
  function prettyDate(value) {
    // O banco retorna horário do próprio servidor. Não converte para um fuso presumido.
    const match = String(value || '').match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/);
    return match ? `${match[3]}/${match[2]}/${match[1]} · ${match[4]}:${match[5]}` : String(value || '—');
  }
  function renderHistory() {
    const list = state.bootstrap?.history || [], term = $('#history-filter').value.toLowerCase().trim();
    const rows = list.filter(row => [row.target, row.reason, row.actorName, row.actorLicense, row.scope].join(' ').toLowerCase().includes(term));
    $('#history-count').textContent = list.length;
    $('#history-empty').hidden = rows.length > 0;
    $('#history-body').innerHTML = rows.map(row => `<tr><td><strong>${esc(scopeNames[row.scope])} · ${esc(row.target || 'Todo o servidor')}</strong><small>${esc(row.reason)}</small></td><td><strong>${esc(row.actorName)}</strong><small title="${esc(row.actorLicense)}">${esc(row.actorLicense || 'License não disponível')}</small></td><td>${esc(prettyDate(row.createdAt))}</td><td><span class="status-pill ${row.status === 'failed' ? 'failed' : ''}">${row.status === 'completed' ? 'Concluído' : 'Recusado / falhou'}</span></td><td><button class="row-action" data-job="${esc(row.id)}" aria-label="Ver detalhes da operação">↗</button></td></tr>`).join('');
    $$('#history-body [data-job]').forEach(button => button.addEventListener('click', () => showJob(list.find(row => row.id === button.dataset.job))));
    $('#recent-activity').innerHTML = list.slice(0, 3).map(row => `<div class="activity-row"><span class="activity-icon">${icon(row.scope === 'player' ? 'user' : row.scope === 'garage' ? 'car' : 'box')}</span><div><strong>${esc(scopeNames[row.scope])} · ${esc(row.target || 'Todo o servidor')}</strong><small>${esc(row.actorName)} · ${row.status === 'completed' ? 'Concluído com backup' : 'Execução não concluída'}</small></div><time>${esc(prettyDate(row.createdAt))}</time></div>`).join('') || '<div class="empty-state"><h3>Nenhuma operação registrada.</h3><p>Comece preparando um plano de wipe.</p></div>';
  }
  function showJob(row) {
    if (!row) return;
    openModal(`<div class="eyebrow">REGISTRO DA OPERAÇÃO ${DEMO ? '/ FICTÍCIO' : ''}</div><h2 id="modal-title">${esc(scopeNames[row.scope])}</h2><p class="modal-subtitle">${esc(row.reason)}</p><div class="detail-meta"><div><span>Alvo</span>${esc(row.target || 'Todo o servidor')}</div><div><span>Administrador</span>${esc(row.actorName)}</div><div><span>Data no banco</span>${esc(prettyDate(row.createdAt))}</div><div><span>Status</span>${row.status === 'completed' ? 'Concluído' : 'Falhou / recusado'}</div></div><div class="muted">Referência</div><code class="backup-command">${esc(row.id)}</code>${row.status === 'completed' ? `<h3 class="subheading">Exportar backup pelo console</h3><p class="muted">${DEMO ? 'Este registro é fictício. Em produção, use o comando no console do servidor.' : 'O arquivo é salvo na pasta backups do resource, sem expor os dados à interface.'}</p><code class="backup-command">apex_wipe_export ${esc(row.id)}</code>` : '<p class="muted">Este registro não representa um wipe confirmado e não possui backup concluído.</p>'}<div class="modal-actions"><button class="secondary-button" id="detail-close">Fechar detalhes</button></div>`);
    const identifiers = { ...(row.actorIdentifiers || {}) };
    if (!identifiers.license && row.actorLicense) identifiers.license = row.actorLicense;
    const audit = document.createElement('div'); audit.className = 'audit-details';
    audit.innerHTML = `<h3 class="subheading">Quem autorizou o WIPE</h3><div class="detail-meta"><div><span>Nome no servidor</span>${esc(row.actorName)}</div><div><span>ID de sessão no momento</span>${esc(row.actorSource ?? 'Não disponível')}</div>${row.actorCharacter?.citizenid ? `<div><span>Personagem do admin</span>${esc(row.actorCharacter.name || '—')} · ${esc(row.actorCharacter.citizenid)}</div>` : ''}</div>${Object.entries(identifiers).map(([key, value]) => `<div class="audit-identifier"><span>${esc(key)}</span><code>${esc(value)}</code></div>`).join('')}${row.plan?.operations?.length ? `<h3 class="subheading">Categorias e registros afetados</h3>${row.plan.operations.map(op => `<div class="review-operation"><div><strong>${esc(op.label)}</strong><code>${esc(op.table)}</code></div><span>${number(op.count)}</span></div>`).join('')}` : ''}`;
    $('#modal-content .detail-meta').after(audit);
    $('#detail-close').addEventListener('click', closeModal);
  }
  function renderBootstrap(data) {
    state.bootstrap = data;
    $('#server-name').textContent = data.serverName || 'MRI QBOX'; $('#admin-name').textContent = data.adminName || 'Administrador';
    $('#admin-initials').textContent = (data.adminName || 'Admin').split(/\s+/).slice(0, 2).map(s => s[0]).join('').toUpperCase();
    $('#environment-label').textContent = DEMO ? 'Ambiente de demonstração' : data.canExecute ? 'Admin autorizado' : 'Acesso de revisão';
    $('#footer-mode').textContent = DEMO ? 'PREVIEW / DADOS FICTÍCIOS' : 'MRI QBOX / ADMIN CONSOLE';
    const compatibility = data.compatibility || [];
    $('#overview-compatibility').innerHTML = compatibility.map(row => `<div class="compatibility-cell"><div><code>${esc(row.table)}</code><small style="display:block;margin-top:6px">${row.present ? esc(row.engine) : 'Não encontrada'}</small></div>${icon(row.present && row.engine === 'InnoDB' && !row.triggers ? 'check' : 'warning')}</div>`).join('');
    $('#compatibility-details').innerHTML = compatibility.map(row => `<div class="compat-row"><code>${esc(row.table)}</code><span>${row.present ? esc(row.engine) + (row.triggers ? ' · trigger detectado' : ' · detectada') : 'Não encontrada'}</span></div>`).join('');
    $('#blockers-list').innerHTML = data.blockers?.length ? data.blockers.map(message => `<div class="blocker">${icon('info')}<span>${esc(message)}</span></div>`).join('') : `<div class="blocker">${icon('check')}<span>Manutenção e backup serão preparados automaticamente ao confirmar.${DEMO ? ' Nesta prévia, todas as etapas são simuladas.' : ''}</span></div>`;
    $('#protected-tables').innerHTML = (data.protectedTables || []).map(name => `<code>${esc(name)}</code>`).join('') || '<p class="muted">Nenhuma tabela adicional encontrada.</p>';
    const stats = data.stats || {};
    $('#overview-stats').innerHTML = [['Personagens', stats.players], ['Veículos', stats.vehicles], ['Baús persistidos', stats.stashes], ['Operações recentes', (data.history || []).length]].map(([label, value]) => `<div class="stat-row"><span>${esc(label)}</span><strong>${typeof value === 'number' ? number(value) : '—'}</strong></div>`).join('');
    renderHistory();
  }
  function animateCount(value) {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) { $('#impact-count').textContent = number(value); return; }
    const start = performance.now();
    function step(time) {
      const progress = Math.min((time - start) / 650, 1);
      $('#impact-count').textContent = number(Math.round(value * (1 - (1 - progress) ** 3)));
      if (progress < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }
  async function preview() {
    if (state.loading || state.executing) return;
    if (state.scope !== 'server' && !$('#target').value.trim()) { toast('Informe ou selecione o alvo da operação.', 'error'); $('#target').focus(); return; }
    if (!state.modules.size) { toast('Selecione ao menos uma categoria.', 'error'); return; }
    if ($('#reason').value.trim().length < 8) { toast('Descreva o motivo com pelo menos 8 caracteres.', 'error'); $('#reason').focus(); return; }
    setLoading(true);
    try {
      const plan = await api('preview', { scope: state.scope, target: $('#target').value.trim(),
        owner: $('#owner').value.trim(), reason: $('#reason').value.trim(),
        modules: Object.fromEntries([...state.modules].map(key => [key, true])) });
      state.plan = plan; animateCount(plan.summary.rows); renderReview(plan);
    } catch (error) { toast(error.message, 'error'); }
    finally { setLoading(false); }
  }
  function renderReview(plan) {
    const blocked = (plan.blockers || []).length > 0;
    openModal(`<div class="eyebrow">03 / REVISÃO ${DEMO ? '· DEMONSTRAÇÃO' : 'DO PLANO'}</div><h2 id="modal-title">Tudo certo para recomeçar?</h2><p class="modal-subtitle">Revise exatamente o que será afetado. As configurações dos recursos permanecem fora do plano.</p><div class="review-target"><span>${esc(scopeNames[plan.request.scope])}</span><strong>${esc(plan.request.target || 'Todo o servidor')}${plan.request.scope === 'stash' ? ' · ' + esc(plan.request.owner || 'Compartilhado') : ''}</strong></div><div>${plan.summary.operations.map(op => `<div class="review-operation"><div><strong>${esc(op.label)}</strong><code>${esc(op.table)} · ${op.mode === 'delete' ? 'remover registros' : 'reiniciar ' + (op.columns || []).join(', ')}</code></div><span>${number(op.count)}</span></div>`).join('')}</div><div class="review-stats"><span>Registros<strong>${number(plan.summary.rows)}</strong></span><span>Backup estimado<strong>${number(Math.ceil(plan.summary.bytes / 1024))} KB</strong></span></div>${blocked ? `<div class="review-blockers"><h3>Antes de executar</h3><ul>${plan.blockers.map(message => `<li>${esc(message)}</li>`).join('')}</ul></div>` : ''}<div class="confirmation-section"><label for="confirm-text">Para confirmar, digite exatamente <code>${esc(plan.confirmation)}</code></label><input id="confirm-text" type="text" autocomplete="off" placeholder="${esc(plan.confirmation)}" ${blocked ? 'disabled' : ''}><label class="acknowledge"><input id="backup-ack" type="checkbox" ${blocked ? 'disabled' : ''}><span>${DEMO ? 'Entendo que esta é uma demonstração com dados fictícios.' : 'Autorizo o backup e a manutenção automática. Os jogadores serão desconectados e os recursos de gameplay serão pausados e retomados.'}</span></label><p class="review-lifetime" id="review-lifetime">Plano válido por ${plan.expiresIn} segundos.</p></div><div class="modal-actions"><button class="secondary-button" id="cancel-review">Voltar à configuração</button><button class="primary-button" id="execute" disabled>${icon('layers')}${DEMO ? 'Simular WIPE' : 'Fazer WIPE'}<span>↗</span></button></div>`);
    const deadline = Date.now() + plan.expiresIn * 1000;
    const validate = () => {
      const remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
      $('#execute').disabled = blocked || $('#confirm-text').value !== plan.confirmation || !$('#backup-ack').checked || remaining <= 0;
      $('#review-lifetime').textContent = remaining > 0 ? `Plano válido por ${remaining} segundos. ${DEMO ? 'Nenhum dado real será alterado.' : 'Você precisará reconectar após a operação.'}` : 'Plano expirado. Volte e faça uma nova simulação.';
    };
    $('#confirm-text').addEventListener('input', validate); $('#backup-ack').addEventListener('change', validate);
    $('#cancel-review').addEventListener('click', closeModal); $('#execute').addEventListener('click', execute);
    clearInterval(expiryTimer); expiryTimer = setInterval(validate, 1000); validate();
  }
  async function execute() {
    if (state.executing || !state.plan || $('#execute').disabled) return;
    const plan = state.plan, confirmation = $('#confirm-text').value, acknowledged = $('#backup-ack').checked;
    state.executing = true; clearInterval(expiryTimer); $('#modal-close').disabled = true;
    $('#modal-content').innerHTML = `<div class="operation-progress"><div class="spinner"></div><div class="eyebrow" style="justify-content:center">${DEMO ? 'SIMULAÇÃO VISUAL' : 'OPERAÇÃO EM ANDAMENTO'}</div><h2 id="modal-title">Preparando um novo começo.</h2><p>${DEMO ? 'Simulando manutenção, backup e execução do plano.' : 'Pausando recursos, salvando os alvos e aplicando o plano.<br>Aguarde a confirmação do servidor.'}</p><div class="progress-line"></div></div>`;
    try {
      const result = await api('execute', { id: plan.id, confirmation, backupAcknowledged: acknowledged });
      state.plan = null; state.executing = false; $('#modal-close').disabled = false;
      const warnings = result.restartWarnings || [];
      $('#modal-content').innerHTML = `<div class="success"><div class="success-icon">${icon('check')}</div><div class="eyebrow" style="justify-content:center">${DEMO ? 'DEMONSTRAÇÃO FINALIZADA' : 'OPERAÇÃO CONCLUÍDA'}</div><h2 id="modal-title">${DEMO ? 'É assim que um recomeço acontece.' : 'Um novo começo, confirmado.'}</h2><p>${esc(result.message)}</p><div class="review-target"><span>Registros no plano</span><strong>${number(result.rows)}</strong></div><p class="muted">${DEMO ? 'Este backup é fictício.' : 'Backup dos registros afetados salvo no banco.'}</p><code class="backup-command">${esc(result.id)}</code>${warnings.length ? `<div class="review-blockers"><h3>Recursos que exigem atenção</h3><ul>${warnings.map(w => `<li>${esc(w)}</li>`).join('')}</ul></div>` : ''}<div class="modal-actions"><button class="primary-button" id="success-close">${DEMO ? 'Consultar histórico' : 'Entendido'}</button></div></div>`;
      $('#success-close').addEventListener('click', () => { closeModal(); changePage('history'); });
      if (DEMO) renderBootstrap(await api('bootstrap'));
    } catch (error) {
      state.executing = false; state.plan = null; $('#modal-close').disabled = false;
      $('#modal-content').innerHTML = `<div class="eyebrow">OPERAÇÃO NÃO CONFIRMADA</div><h2 id="modal-title">Confira o resultado antes de continuar.</h2><p class="modal-subtitle">${esc(error.message)}</p><code class="backup-command">${esc(plan.id)}</code><p class="modal-subtitle">Consulte o histórico e o console. Prepare uma nova revisão somente depois de verificar este resultado.</p><div class="modal-actions"><button class="secondary-button" id="failure-close">Voltar</button></div>`;
      $('#failure-close').addEventListener('click', closeModal);
    }
  }
  async function refresh() {
    if (state.loading || state.executing) return;
    $('#refresh').disabled = true;
    try { renderBootstrap(await api('bootstrap')); toast('Diagnóstico e histórico atualizados.'); }
    catch (error) { toast(error.message, 'error'); }
    finally { $('#refresh').disabled = false; }
  }
  function exportHistory() {
    const rows = state.bootstrap?.history || [];
    const cell = value => {
      let text = String(value ?? ''); if (/^[=+@\-\t\r]/.test(text)) text = "'" + text;
      return '"' + text.replace(/"/g, '""') + '"';
    };
    const csv = '\ufeff' + [['id', 'escopo', 'alvo', 'admin', 'license', 'license2', 'discord', 'fivem', 'steam', 'id_sessao', 'motivo', 'status', 'data'],
      ...rows.map(row => [row.id, row.scope, row.target, row.actorName, row.actorLicense,
        row.actorIdentifiers?.license2, row.actorIdentifiers?.discord, row.actorIdentifiers?.fivem,
        row.actorIdentifiers?.steam, row.actorSource, row.reason, row.status, row.createdAt])]
      .map(row => row.map(cell).join(';')).join('\r\n');
    const link = document.createElement('a'); link.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    link.download = 'Apex_WIPE_historico' + (DEMO ? '_DEMO' : '') + '.csv'; link.click(); setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  }
  async function closeApp() {
    if (state.executing) return;
    if (!$('#modal-layer').hidden) { closeModal(); return; }
    if (!DEMO) {
      window.ApexVisibility.hide();
      try { await api('close'); } catch (error) { console.error('[Apex_WIPE] Fechamento:', error.message); }
    }
    $('#app').hidden = true; $('#app').dataset.open = 'false'; $('#closed-preview').hidden = !DEMO;
  }
  hydrateIcons(); renderModules();
  $$('.nav-item').forEach(node => node.addEventListener('click', () => changePage(node.dataset.page)));
  $$('[data-go]').forEach(node => node.addEventListener('click', () => changePage(node.dataset.go)));
  $('.brand').addEventListener('click', event => { event.preventDefault(); changePage('wipe'); });
  $$('.scope-card').forEach(node => node.addEventListener('click', () => changeScope(node.dataset.scope)));
  $('#module-options').addEventListener('change', event => {
    const key = event.target.dataset.module; if (!key) return;
    if (event.target.checked) state.modules.add(key); else state.modules.delete(key);
    if (key === 'characters' && event.target.checked) ['inventory', 'money', 'vehicleStorage', 'vehicles'].forEach(k => state.modules.delete(k));
    if (key === 'vehicles' && event.target.checked) state.modules.delete('vehicleStorage');
    if (key === 'vehicleStorage' && event.target.checked) state.modules.delete('vehicles');
    invalidate(); renderModules();
  });
  $('#select-all').addEventListener('click', () => {
    const wanted = availableModules().filter(k => k !== 'characters' && k !== 'vehicles');
    state.modules = wanted.every(k => state.modules.has(k)) ? new Set() : new Set(wanted);
    invalidate(); renderModules();
  });
  $('#target').addEventListener('input', () => { invalidate(); state.selectedLabel = ''; state.searchSeq++; $('#search-results').hidden = true; clearTimeout(state.searchTimer); });
  $('#target').addEventListener('keydown', event => { if (event.key === 'Enter') { event.preventDefault(); search(); } });
  $('#owner').addEventListener('input', invalidate);
  $('#reason').addEventListener('input', () => { $('#reason-count').textContent = `${$('#reason').value.length} / 250`; invalidate(); });
  $('#search').addEventListener('click', search); $('#preview').addEventListener('click', preview);
  $('#refresh').addEventListener('click', refresh); $('#close').addEventListener('click', closeApp);
  $('#modal-close').addEventListener('click', closeModal); $('#history-filter').addEventListener('input', renderHistory);
  $('#export-history').addEventListener('click', exportHistory);
  $('#modal-layer').addEventListener('click', event => { if (event.target === $('#modal-layer')) closeModal(); });
  document.addEventListener('click', event => { if (!event.target.closest('.search-field') && !event.target.closest('.search-results')) $('#search-results').hidden = true; });
  document.addEventListener('keydown', event => {
    if ($('#app').hidden) return;
    if (event.key === 'Escape') { event.preventDefault(); closeApp(); }
    if (event.key === 'Tab' && !$('#modal-layer').hidden) {
      const focusable = $$('.modal button:not(:disabled), .modal input:not(:disabled), .modal [tabindex="0"]');
      if (!focusable.length) { event.preventDefault(); return; }
      const first = focusable[0], last = focusable[focusable.length - 1];
      if (event.shiftKey && (document.activeElement === first || document.activeElement === $('.modal'))) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && (document.activeElement === last || document.activeElement === $('.modal'))) { event.preventDefault(); first.focus(); }
    }
  });
  window.addEventListener('message', event => {
    if (DEMO || event.data?.channel !== 'Apex_WIPE') return;
    const message = event.data;
    if (message?.action === 'open' && message.data && typeof message.token === 'string' && message.token.length >= 8) {
      try {
        renderBootstrap(message.data);
        if (!window.ApexVisibility.show()) return;
        $('#app').dataset.open = 'true'; $('#app').hidden = false;
        api('uiShown', { token: message.token }).catch(error => {
          window.ApexVisibility.hide(); console.error('[Apex_WIPE] Foco:', error.message);
        });
      } catch (error) { window.ApexVisibility.hide(); console.error('[Apex_WIPE] Abertura:', error.message); }
    }
    if (message?.action === 'close') { window.ApexVisibility.hide(); clearInterval(expiryTimer); }
  });
  $('#reopen').addEventListener('click', () => {
    if (!DEMO) return;
    $('#closed-preview').hidden = true; $('#app').dataset.open = 'true'; $('#app').hidden = false;
  });
  if (DEMO) {
    window.ApexVisibility.show();
    $('#app').dataset.open = 'true'; $('#app').hidden = false; $('#demo-banner').hidden = false;
    window.ApexDemo.api('bootstrap').then(renderBootstrap).catch(error => toast(error.message, 'error'));
  } else if (typeof GetParentResourceName === 'function') {
    api('uiReady').catch(() => window.ApexVisibility.hide());
  }
})();
