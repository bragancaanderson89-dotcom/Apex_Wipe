/* A página inteira fica fechada, mesmo se app.js ou styles.css falharem. */
(() => {
  'use strict';
  const root = document.documentElement;
  const localPreview = location.protocol === 'file:' ||
    (location.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(location.hostname));
  const preview = root.dataset.apexPreview === 'true' && localPreview &&
    typeof GetParentResourceName !== 'function';
  let authorized = false;

  function hide() {
    authorized = false;
    root.dataset.uiState = 'closed';
    const body = document.body;
    if (body) {
      body.hidden = true;
      body.style.setProperty('display', 'none', 'important');
      body.style.setProperty('visibility', 'hidden', 'important');
      body.style.setProperty('opacity', '0', 'important');
      body.style.setProperty('pointer-events', 'none', 'important');
    }
    const app = document.getElementById('app');
    if (app) { app.hidden = true; app.dataset.open = 'false'; }
    const modal = document.getElementById('modal-layer');
    if (modal) modal.hidden = true;
    const toasts = document.getElementById('toast-region');
    if (toasts) toasts.replaceChildren();
  }

  function reveal() {
    root.dataset.uiState = 'open';
    document.body.hidden = false;
    for (const property of ['display', 'visibility', 'opacity', 'pointer-events']) {
      document.body.style.removeProperty(property);
    }
  }

  window.ApexVisibility = Object.freeze({
    preview,
    hide,
    show() {
      if (!preview && !authorized) return false;
      reveal();
      return true;
    }
  });
  hide();
  window.addEventListener('message', event => {
    if (preview || event.data?.channel !== 'Apex_WIPE') return;
    if (event.data.action === 'close') hide();
    if (event.data.action === 'open' && event.data.data && typeof event.data.token === 'string'
        && event.data.token.length >= 8) authorized = true;
  });
  window.addEventListener('pagehide', hide);
})();
