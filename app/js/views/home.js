import { supabase } from '../supabase.js';
import { currentActor } from '../api/log.js';
import { renderScopeSelector, scopedEstacionamientos, scopedEmpresas, scopedGrupos, getScope, scopeLabel } from '../api/scope.js';

export async function renderHome(root) {
  const actor = currentActor();
  root.innerHTML = `
    <header class="bg-marino text-white px-4 py-3 shadow-md">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-3">
          <img src="/assets/logo.png" alt="ONLYPARK" class="h-8 w-auto bg-white rounded p-0.5" />
          <div class="leading-tight">
            <div class="font-semibold tracking-wide">ONLYPARK</div>
            <div class="text-xs text-white/60">Panel principal</div>
          </div>
        </div>
        <div class="flex items-center gap-4">
          <div class="text-right leading-tight">
            <div class="text-xs text-white/60">Operando como</div>
            <div class="text-sm font-medium">${actor}</div>
          </div>
          <button id="op-logout" class="bg-white/10 hover:bg-white/20 text-sm rounded-md px-3 py-1.5 transition">Salir</button>
        </div>
      </div>
      <div id="scope-selector"></div>
    </header>

    <main class="flex-1 p-6 max-w-7xl mx-auto w-full">
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-marino">Bienvenido, ${actor}</h1>
        <p id="scope-label" class="text-slate-500 text-sm">—</p>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        ${kpi('empresas','Empresas','marino')}
        ${kpi('est','Estacionamientos','marino')}
        ${kpi('cajones','Cajones','barrera-700')}
        ${kpi('tickets-hoy','Tickets hoy','marino')}
      </div>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        ${kpi('ingresos-7d','Ingresos 7d','barrera-700')}
        ${kpi('ticket-prom','Ticket promedio','marino')}
        ${kpi('abiertas','Sesiones abiertas','marino')}
        ${kpi('pensiones','Pensiones activas','marino')}
      </div>

      <div class="mb-6">
        <h2 class="text-lg font-semibold text-marino mb-3">Módulos</h2>
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
          ${modulo('/portales/operador.html','Operador','🎫','Caja: entradas, cobros',true)}
          ${modulo('/portales/admin.html','Admin de plaza','🏢','KPIs de plaza',true)}
          ${modulo('/portales/corporativo.html','Corporativo','📊','Vista ejecutiva',true)}
          ${modulo('#/catalogos/grupos','Catálogos','📋','Jerarquía',false)}
          ${modulo('#/reportes','Reportes','📈','Ingresos, ocupación',false)}
          ${modulo('#/monitor','Monitor ETL','⚙️','Salud DWH',false)}
          ${modulo('#/camaras','Cámaras LPR','📹','Streams',false)}
          ${modulo('#/pensiones','Pensiones','🎟️','Pensionados',false)}
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div id="op-empresas" class="op-card">…</div>
        <div id="op-estacionamientos" class="op-card">…</div>
      </div>
      <div id="op-actividad" class="op-card mt-4">…</div>
    </main>`;

  root.querySelector('#op-logout').addEventListener('click', async () => {
    localStorage.removeItem('op_actor');
    await supabase.auth.signOut();
    window.location.hash = '/login';
  });

  await renderScopeSelector(root.querySelector('#scope-selector'));

  await refresh(root);
  window.addEventListener('op-scope-change', () => refresh(root));
}

function kpi(id, label, color) {
  return `<div class="op-card">
    <div class="text-xs text-slate-500 uppercase tracking-wide">${label}</div>
    <div id="kpi-${id}" class="text-2xl font-bold text-${color} mt-1">—</div>
  </div>`;
}

function modulo(href, titulo, icono, sub, externo) {
  const link = externo ? `href="${href}" target="_blank"` : `href="${href}"`;
  return `
    <a ${link} class="op-card hover:shadow-lg hover:border-marino transition group">
      <div class="flex items-center gap-3">
        <div class="text-3xl">${icono}</div>
        <div class="flex-1">
          <div class="font-semibold text-marino group-hover:underline">${titulo}${externo ? ' ↗' : ''}</div>
          <div class="text-xs text-slate-500 mt-0.5">${sub}</div>
        </div>
      </div>
    </a>`;
}

async function refresh(root) {
  const [grp, emp, est, label] = await Promise.all([scopedGrupos(), scopedEmpresas(), scopedEstacionamientos(), scopeLabel()]);
  const cajones = est.reduce((a,x)=>a+(x.capacidad_total||0),0);
  root.querySelector('#kpi-empresas').textContent = emp.length;
  root.querySelector('#kpi-est').textContent = est.length;
  root.querySelector('#kpi-cajones').textContent = cajones.toLocaleString();
  root.querySelector('#scope-label').textContent = 'Ámbito: ' + label;

  const idsEst = est.map(x => x.estacionamiento_id);

  const desde7 = new Date(); desde7.setDate(desde7.getDate()-7);
  const hoy0 = new Date(); hoy0.setHours(0,0,0,0);

  const qHoy = supabase.from('sesiones').select('*', { count:'exact', head:true }).gte('entrada_at', hoy0.toISOString());
  const qAbt = supabase.from('sesiones').select('*', { count:'exact', head:true }).is('salida_at', null);
  const qPag = supabase.from('pagos').select('monto').gte('cobrado_at', desde7.toISOString());
  const qPen = supabase.from('pensiones').select('*', { count:'exact', head:true }).eq('estado','activo');

  const inList = idsEst.length ? idsEst : ['00000000-0000-0000-0000-000000000000'];
  const [{ count: tHoy }, { count: abt }, { data: pagos7 }, { count: pens }] = await Promise.all([
    qHoy.in('estacionamiento_id', inList),
    qAbt.in('estacionamiento_id', inList),
    qPag.in('estacionamiento_id', inList),
    qPen.in('estacionamiento_id', inList)
  ]);
  const suma = (pagos7 ?? []).reduce((a,x)=>a+Number(x.monto||0),0);
  const prom = pagos7?.length ? suma / pagos7.length : 0;

  root.querySelector('#kpi-tickets-hoy').textContent = tHoy ?? 0;
  root.querySelector('#kpi-abiertas').textContent = abt ?? 0;
  root.querySelector('#kpi-ingresos-7d').textContent = '$' + suma.toLocaleString(undefined,{maximumFractionDigits:0});
  root.querySelector('#kpi-ticket-prom').textContent = '$' + prom.toLocaleString(undefined,{maximumFractionDigits:0});
  root.querySelector('#kpi-pensiones').textContent = pens ?? 0;

  root.querySelector('#op-empresas').innerHTML = `
    <div class="flex justify-between items-baseline mb-2">
      <div class="text-sm font-semibold text-marino">Empresas del ámbito</div>
      <div class="text-xs text-slate-400">${emp.length}</div>
    </div>
    <ul class="divide-y">${emp.map(x=>`
      <li class="py-1.5 flex justify-between text-sm"><span>${x.razon_social}</span><span class="text-slate-400 font-mono text-xs">${x.codigo}</span></li>`).join('') || '<li class="py-2 text-slate-400 text-sm">Sin datos</li>'}</ul>`;

  root.querySelector('#op-estacionamientos').innerHTML = `
    <div class="flex justify-between items-baseline mb-2">
      <div class="text-sm font-semibold text-marino">Estacionamientos del ámbito</div>
      <div class="text-xs text-slate-400">${est.length}</div>
    </div>
    <ul class="divide-y">${est.map(x=>`
      <li class="py-1.5 flex justify-between text-sm">
        <span>${x.nombre} <span class="text-slate-400 font-mono text-xs">${x.codigo}</span></span>
        <span class="text-slate-500">${(x.capacidad_total ?? 0).toLocaleString()} cajones</span>
      </li>`).join('') || '<li class="py-2 text-slate-400 text-sm">Sin datos</li>'}</ul>`;

  const { data: activ } = await supabase.from('log_evento')
    .select('subtipo, descripcion, ocurrido_at, estacionamiento_id')
    .in('estacionamiento_id', inList)
    .order('ocurrido_at', { ascending:false }).limit(10);
  root.querySelector('#op-actividad').innerHTML = `
    <div class="text-sm font-semibold text-marino mb-2">Actividad reciente del ámbito</div>
    <ul class="divide-y">${(activ??[]).map(x=>`
      <li class="py-1.5 flex justify-between text-xs">
        <span><span class="inline-block px-2 py-0.5 bg-slate-100 rounded font-mono mr-2">${x.subtipo??'-'}</span>${(x.descripcion??'').slice(0,80)}</span>
        <span class="text-slate-400">${new Date(x.ocurrido_at).toLocaleString()}</span>
      </li>`).join('') || '<li class="py-2 text-slate-400 text-sm">Sin actividad</li>'}</ul>`;
}
