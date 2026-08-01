import { supabase } from '../supabase.js';
import { currentActor } from '../api/log.js';

export async function renderHome(root) {
  const actor = currentActor();
  root.innerHTML = `
    <header class="bg-marino text-white px-4 py-3 flex items-center justify-between shadow-md">
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
    </header>

    <main class="flex-1 p-6 max-w-7xl mx-auto w-full">
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-marino">Bienvenido, ${actor}</h1>
        <p class="text-slate-500 text-sm">Panel ejecutivo consolidado</p>
      </div>

      <!-- KPIs principales -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Empresas</div>
          <div id="kpi-empresas" class="text-3xl font-bold text-marino mt-1">—</div>
        </div>
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Estacionamientos</div>
          <div id="kpi-est" class="text-3xl font-bold text-marino mt-1">—</div>
        </div>
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Cajones totales</div>
          <div id="kpi-cajones" class="text-3xl font-bold text-barrera mt-1">—</div>
        </div>
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Tickets hoy</div>
          <div id="kpi-tickets-hoy" class="text-3xl font-bold text-marino mt-1">—</div>
        </div>
      </div>

      <!-- KPIs de operacion (leidos del DWH) -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Ingresos 7 días</div>
          <div id="kpi-ingresos-7d" class="text-2xl font-bold text-barrera-700 mt-1">—</div>
        </div>
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Ticket promedio</div>
          <div id="kpi-ticket-prom" class="text-2xl font-bold text-marino mt-1">—</div>
        </div>
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Sesiones abiertas</div>
          <div id="kpi-abiertas" class="text-2xl font-bold text-marino mt-1">—</div>
        </div>
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Pensiones activas</div>
          <div id="kpi-pensiones" class="text-2xl font-bold text-marino mt-1">—</div>
        </div>
      </div>

      <!-- Modulos -->
      <div class="mb-6">
        <h2 class="text-lg font-semibold text-marino mb-3">Módulos</h2>
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
          ${modulo('/portales/operador.html','Operador','🎫','Caja: entradas, cobros, cortes',true)}
          ${modulo('/portales/admin.html','Admin de plaza','🏢','KPIs, ocupación, cajeros',true)}
          ${modulo('/portales/corporativo.html','Corporativo','📊','Vista ejecutiva',true)}
          ${modulo('#/catalogos/grupos','Catálogos','📋','Jerarquía Grupo→Empresa→Estac',false)}
          ${modulo('#/reportes','Reportes','📈','Ingresos, ocupación, tickets',false)}
          ${modulo('#/monitor','Monitor ETL','⚙️','Salud de las cargas DWH',false)}
          ${modulo('#/camaras','Cámaras LPR','📹','Streams entrada/salida',false)}
          ${modulo('#/pensiones','Pensiones','🎟️','Pensionados activos',false)}
        </div>
      </div>

      <!-- Actividad reciente + listas -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div id="op-empresas" class="op-card">Cargando empresas visibles…</div>
        <div id="op-estacionamientos" class="op-card">Cargando estacionamientos visibles…</div>
      </div>

      <div id="op-actividad" class="op-card mt-4">Cargando actividad reciente…</div>
    </main>`;

  root.querySelector('#op-logout').addEventListener('click', async () => {
    localStorage.removeItem('op_actor');
    await supabase.auth.signOut();
    window.location.hash = '/login';
  });

  await Promise.all([kpisPrincipales(root), kpisOperacion(root), listas(root), actividad(root)]);
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

async function kpisPrincipales(root) {
  const [{ data: emp }, { data: est }, { count: tickHoy }] = await Promise.all([
    supabase.from('empresas').select('empresa_id, codigo, razon_social').order('razon_social'),
    supabase.from('estacionamientos').select('estacionamiento_id, codigo, nombre, capacidad_total').order('nombre'),
    supabase.from('sesiones').select('*', { count:'exact', head:true }).gte('entrada_at', new Date(new Date().setHours(0,0,0,0)).toISOString())
  ]);
  root.querySelector('#kpi-empresas').textContent = emp?.length ?? '-';
  root.querySelector('#kpi-est').textContent = est?.length ?? '-';
  root.querySelector('#kpi-cajones').textContent = (est ?? []).reduce((a,x)=>a+(x.capacidad_total||0),0).toLocaleString();
  root.querySelector('#kpi-tickets-hoy').textContent = tickHoy ?? 0;
  root._emp = emp; root._est = est;
}

async function kpisOperacion(root) {
  const desde = new Date(); desde.setDate(desde.getDate()-7);
  const [{ data: pagos7 }, { count: abiertas }, { count: pens }] = await Promise.all([
    supabase.from('pagos').select('monto').gte('cobrado_at', desde.toISOString()),
    supabase.from('sesiones').select('*', { count:'exact', head:true }).is('salida_at', null),
    supabase.from('pensiones').select('*', { count:'exact', head:true }).eq('estado','activo')
  ]);
  const suma = (pagos7 ?? []).reduce((a,x)=>a+Number(x.monto||0),0);
  const prom = pagos7?.length ? suma / pagos7.length : 0;
  root.querySelector('#kpi-ingresos-7d').textContent = '$' + suma.toLocaleString(undefined, {maximumFractionDigits:0});
  root.querySelector('#kpi-ticket-prom').textContent = '$' + prom.toLocaleString(undefined, {maximumFractionDigits:0});
  root.querySelector('#kpi-abiertas').textContent = abiertas ?? '-';
  root.querySelector('#kpi-pensiones').textContent = pens ?? '-';
}

async function listas(root) {
  const emp = root._emp; const est = root._est;
  root.querySelector('#op-empresas').innerHTML = !emp ? 'Sin datos' : `
    <div class="flex justify-between items-baseline mb-2">
      <div class="text-sm font-semibold text-marino">Empresas visibles</div>
      <div class="text-xs text-slate-400">${emp.length}</div>
    </div>
    <ul class="divide-y">${emp.map(x=>`
      <li class="py-1.5 flex justify-between text-sm"><span>${x.razon_social}</span><span class="text-slate-400 font-mono text-xs">${x.codigo}</span></li>`).join('')}</ul>`;
  root.querySelector('#op-estacionamientos').innerHTML = !est ? 'Sin datos' : `
    <div class="flex justify-between items-baseline mb-2">
      <div class="text-sm font-semibold text-marino">Estacionamientos visibles</div>
      <div class="text-xs text-slate-400">${est.length}</div>
    </div>
    <ul class="divide-y">${est.map(x=>`
      <li class="py-1.5 flex justify-between text-sm">
        <span>${x.nombre} <span class="text-slate-400 font-mono text-xs">${x.codigo}</span></span>
        <span class="text-slate-500">${(x.capacidad_total ?? 0).toLocaleString()} cajones</span>
      </li>`).join('')}</ul>`;
}

async function actividad(root) {
  const { data } = await supabase.from('log_evento')
    .select('subtipo, descripcion, ocurrido_at')
    .order('ocurrido_at', { ascending: false }).limit(10);
  root.querySelector('#op-actividad').innerHTML = `
    <div class="text-sm font-semibold text-marino mb-2">Actividad reciente</div>
    <ul class="divide-y">
      ${(data??[]).map(x=>`
        <li class="py-1.5 flex justify-between text-xs">
          <span><span class="inline-block px-2 py-0.5 bg-slate-100 rounded font-mono mr-2">${x.subtipo??'-'}</span>${(x.descripcion??'').slice(0,80)}</span>
          <span class="text-slate-400">${new Date(x.ocurrido_at).toLocaleString()}</span>
        </li>`).join('') || '<li class="py-2 text-slate-400 text-sm">Sin actividad</li>'}
    </ul>`;
}
