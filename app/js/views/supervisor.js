import { supabase } from '../supabase.js';
import { renderScopeSelector, scopedEstacionamientos, scopeLabel } from '../api/scope.js';
import { bindLogout } from './reportes.js';
import { currentActor } from '../api/log.js';

// Vista Supervisor mobile-first — pensada para tablet / celular Android en modo standalone (PWA).
// Un solo tap por acción, tiles grandes, KPIs esenciales, sin distracciones.
export async function renderSupervisor(root) {
  root.innerHTML = shell();
  bindLogout(root);
  await renderScopeSelector(root.querySelector('#scope-selector'));
  root.querySelector('#scope-label').textContent = await scopeLabel();

  await refreshKpis(root);
  window.addEventListener('op-scope-change', async () => {
    root.querySelector('#scope-label').textContent = await scopeLabel();
    await refreshKpis(root);
  });

  // Auto-refresh cada 30s
  const interval = setInterval(() => refreshKpis(root), 30000);
  root.addEventListener('op-unmount', () => clearInterval(interval), { once: true });
}

function shell() {
  const actor = currentActor();
  return `
    <header class="bg-marino text-white shadow-md">
      <div class="px-3 py-2 flex items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <img src="/assets/logo.png" alt="ONLYPARK" class="h-8 w-auto bg-white rounded p-0.5" />
          <div class="leading-tight">
            <div class="font-bold text-sm">ONLYPARK</div>
            <div id="scope-label" class="text-[10px] text-white/70">…</div>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <a href="#/" class="text-white/80 text-xs underline">← Panel</a>
          <button id="op-logout" class="bg-white/10 text-xs rounded px-2 py-1">Salir</button>
        </div>
      </div>
      <div class="px-3 pb-2">
        <div id="scope-selector"></div>
      </div>
    </header>

    <main class="flex-1 p-3">
      <div class="text-xs text-slate-500 uppercase tracking-wider mb-2">Hola, ${actor}</div>

      <!-- KPIs en 2 columnas grandes -->
      <div class="grid grid-cols-2 gap-2 mb-3" id="kpi-grid">
        ${kpiTile('tickets-hoy','Tickets hoy','#0d2340')}
        ${kpiTile('ingresos-hoy','Ingresos hoy','#3aa757')}
        ${kpiTile('abiertas','Autos dentro','#0d2340')}
        ${kpiTile('ocup','Ocupación','#3aa757')}
      </div>

      <!-- Acciones grandes tipo tiles -->
      <div class="grid grid-cols-2 gap-2 mb-3">
        ${bigTile('/portales/operador.html','Abrir caja','🎫','bg-marino text-white',true)}
        ${bigTile('/portales/admin.html','Tablero admin','📊','bg-white text-marino border border-slate-200',true)}
        ${bigTile('#/camara','Cámara','📸','bg-white text-marino border border-slate-200',false)}
        ${bigTile('#/pensiones','Pensiones','🎟️','bg-white text-marino border border-slate-200',false)}
        ${bigTile('#/empleados','Empleados','👥','bg-white text-marino border border-slate-200',false)}
        ${bigTile('#/reportes','Reportes','📈','bg-white text-marino border border-slate-200',false)}
      </div>

      <div id="ult-tickets" class="op-card">Cargando últimos tickets…</div>

      <button id="btn-install" class="hidden fixed bottom-4 right-4 bg-barrera text-white rounded-full shadow-lg px-5 py-3 font-semibold z-50">
        📲 Instalar app
      </button>
    </main>`;
}

function kpiTile(id, label, color) {
  return `<div class="op-card !p-3">
    <div class="text-[10px] text-slate-500 uppercase tracking-wide">${label}</div>
    <div id="kpi-${id}" class="text-3xl font-bold mt-1" style="color:${color}">—</div>
  </div>`;
}
function bigTile(href, titulo, ico, cls, externo) {
  const link = externo ? `href="${href}" target="_blank"` : `href="${href}"`;
  return `<a ${link} class="${cls} rounded-xl p-4 flex flex-col items-center justify-center min-h-[90px] shadow-sm active:scale-95 transition-transform">
    <div class="text-3xl mb-1">${ico}</div>
    <div class="text-sm font-semibold text-center leading-tight">${titulo}</div>
  </a>`;
}

async function refreshKpis(root) {
  const ests = await scopedEstacionamientos();
  const estIds = ests.length ? ests.map(x=>x.estacionamiento_id) : ['00000000-0000-0000-0000-000000000000'];
  const cajones = ests.reduce((a,x)=>a+(x.capacidad_total||0),0);
  const hoy0 = new Date(); hoy0.setHours(0,0,0,0);

  const [{ count: tHoy }, { count: abt }, { data: pagos }, { data: recientes }] = await Promise.all([
    supabase.from('sesiones').select('*',{count:'exact',head:true}).gte('entrada_at',hoy0.toISOString()).in('estacionamiento_id',estIds),
    supabase.from('sesiones').select('*',{count:'exact',head:true}).is('salida_at',null).in('estacionamiento_id',estIds),
    supabase.from('pagos').select('monto').gte('cobrado_at',hoy0.toISOString()).in('estacionamiento_id',estIds),
    supabase.from('sesiones').select('folio_entrada,entrada_at,importe_total,tipo_sesion_id,estacionamiento_id')
      .in('estacionamiento_id',estIds).order('entrada_at',{ascending:false}).limit(6)
  ]);
  const ingresos = (pagos ?? []).reduce((a,x)=>a+Number(x.monto||0),0);

  root.querySelector('#kpi-tickets-hoy').textContent = (tHoy ?? 0).toLocaleString();
  root.querySelector('#kpi-ingresos-hoy').textContent = '$' + ingresos.toLocaleString(undefined,{maximumFractionDigits:0});
  root.querySelector('#kpi-abiertas').textContent = abt ?? 0;
  root.querySelector('#kpi-ocup').textContent = cajones ? Math.round((abt ?? 0) * 100 / cajones) + '%' : '—';

  root.querySelector('#ult-tickets').innerHTML = `
    <div class="text-sm font-semibold text-marino mb-2">Últimos 6 tickets</div>
    <ul class="divide-y">
      ${(recientes ?? []).map(t => `
        <li class="py-1.5 flex justify-between text-sm">
          <span class="font-mono text-xs">${t.folio_entrada}</span>
          <span class="text-slate-500 text-xs">${new Date(t.entrada_at).toLocaleTimeString()}</span>
          <span class="font-semibold text-marino">${t.importe_total ? '$'+t.importe_total : '—'}</span>
        </li>`).join('') || '<li class="py-2 text-slate-400 text-sm">Sin tickets</li>'}
    </ul>`;
}
