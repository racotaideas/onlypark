// Punto de entrada de la PWA.
import { supabase, getSession } from './supabase.js';
import { renderLogin }     from './views/login.js';
import { renderHome }      from './views/home.js';
import { renderCatalogos } from './views/catalogos.js';
import { renderNotFound }  from './views/notfound.js';

const app = document.getElementById('app');

async function router() {
  const path = window.location.hash.replace(/^#/, '') || '/';
  const session = await getSession();
  if (!session && path !== '/login') {
    window.location.hash = '/login';
    return;
  }
  if (session && (path === '/' || path === '/login')) {
    return renderHome(app);
  }
  if (path.startsWith('/catalogos')) {
    const tab = path.split('/')[2] || 'grupos';
    return renderCatalogos(app, tab);
  }
  switch (path) {
    case '/login':   return renderLogin(app);
    case '/':        return renderHome(app);
    default:         return renderNotFound(app, path);
  }
}

window.addEventListener('hashchange', router);
window.addEventListener('load', router);

// Cambios de sesión → reroutear
supabase.auth.onAuthStateChange((_ev, _session) => router());

// Registro del service worker
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((e) => console.warn('SW:', e));
  });
}
