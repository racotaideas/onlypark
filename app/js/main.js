// Punto de entrada de la PWA.
import { supabase } from './supabase.js';
import { renderLogin }     from './views/login.js?v=5';
import { renderHome }      from './views/home.js?v=5';
import { renderCatalogos } from './views/catalogos.js?v=5';
import { renderReportes }  from './views/reportes.js?v=5';
import { renderMonitor }   from './views/monitor.js?v=5';
import { renderCamaras }   from './views/camaras.js?v=5';
import { renderPensiones } from './views/pensiones.js?v=6';
import { renderParametros } from './views/parametros.js?v=2';
import { renderEmpleados } from './views/empleados.js?v=2';
import { renderUsuarios }  from './views/usuarios.js?v=2';
import { renderSupervisor } from './views/supervisor.js?v=1';
import { renderCamara }    from './views/camara.js?v=1';
import { renderNotFound }  from './views/notfound.js?v=5';

const app = document.getElementById('app');

// DEV: unica gate = nombre en localStorage. Sesion Supabase es best-effort.
function isAuthed() {
  return !!localStorage.getItem('op_actor');
}

async function router() {
  const path = window.location.hash.replace(/^#/, '') || '/';
  const authed = isAuthed();
  if (!authed && path !== '/login') {
    window.location.hash = '/login';
    return;
  }
  if (authed && (path === '/' || path === '/login')) {
    return renderHome(app);
  }
  if (path.startsWith('/catalogos')) {
    const tab = path.split('/')[2] || 'grupos';
    return renderCatalogos(app, tab);
  }
  switch (path) {
    case '/login':      return renderLogin(app);
    case '/':           return renderHome(app);
    case '/reportes':   return renderReportes(app);
    case '/monitor':    return renderMonitor(app);
    case '/camaras':    return renderCamaras(app);
    case '/pensiones':  return renderPensiones(app);
    case '/parametros': return renderParametros(app);
    case '/empleados':  return renderEmpleados(app);
    case '/usuarios':   return renderUsuarios(app);
    case '/supervisor': return renderSupervisor(app);
    case '/camara':     return renderCamara(app);
    default:            return renderNotFound(app, path);
  }
}

window.addEventListener('hashchange', router);
// Ejecuta ya (main.js es tipo module, puede cargar despues del evento load)
router();

// Cambios de sesión → reroutear
supabase.auth.onAuthStateChange((_ev, _session) => router());

// Registro del service worker
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((e) => console.warn('SW:', e));
  });
}

// PWA install prompt (Chrome / Edge / Samsung Internet)
let deferredInstall = null;
window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  deferredInstall = e;
  const btn = document.getElementById('btn-install');
  if (btn) btn.classList.remove('hidden');
});
document.addEventListener('click', async (ev) => {
  if (ev.target && ev.target.id === 'btn-install' && deferredInstall) {
    deferredInstall.prompt();
    await deferredInstall.userChoice;
    deferredInstall = null;
    ev.target.classList.add('hidden');
  }
});
