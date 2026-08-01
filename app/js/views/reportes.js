import { supabase } from '../supabase.js';

export async function renderReportes(root) {
  root.innerHTML = shell('Reportes', '📈') + `
    <main class="flex-1 p-6 max-w-7xl mx-auto w-full">
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        ${kpi('30d-tickets','Tickets 30 días','marino')}
        ${kpi('30d-ingresos','Ingresos 30 días','barrera-700')}
        ${kpi('30d-ticket-prom','Ticket promedio','marino')}
        ${kpi('30d-ocupacion','Ocup. promedio','barrera-700')}
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="op-card">
          <div class="text-sm font-semibold text-marino mb-3">Ingresos por día (últimos 14)</div>
          <div id="ing-por-dia" class="text-sm">Cargando…</div>
        </div>
        <div class="op-card">
          <div class="text-sm font-semibold text-marino mb-3">Top estacionamientos</div>
          <div id="top-est" class="text-sm">Cargando…</div>
        </div>
        <div class="op-card">
          <div class="text-sm font-semibold text-marino mb-3">Tickets por tipo</div>
          <div id="por-tipo" class="text-sm">Cargando…</div>
        </div>
        <div class="op-card">
          <div class="text-sm font-semibold text-marino mb-3">Método de pago</div>
          <div id="por-metodo" class="text-sm">Cargando…</div>
        </div>
      </div>
    </main>`;
  bindLogout(root);

  const desde30 = new Date(); desde30.setDate(desde30.getDate()-30);
  const desde14 = new Date(); desde14.setDate(desde14.getDate()-14);

  // KPIs 30d
  const [{ data: tick30 }, { data: pagos30 }, { data: cap }] = await Promise.all([
    supabase.from('sesiones').select('sesion_id, estacionamiento_id').gte('entrada_at', desde30.toISOString()),
    supabase.from('pagos').select('monto').gte('cobrado_at', desde30.toISOString()),
    supabase.from('estacionamientos').select('capacidad_total')
  ]);
  const sumaPagos = (pagos30??[]).reduce((a,x)=>a+Number(x.monto||0),0);
  const cajones = (cap??[]).reduce((a,x)=>a+(x.capacidad_total||0),0);
  root.querySelector('#kpi-30d-tickets').textContent = (tick30?.length ?? 0).toLocaleString();
  root.querySelector('#kpi-30d-ingresos').textContent = '$' + sumaPagos.toLocaleString(undefined,{maximumFractionDigits:0});
  root.querySelector('#kpi-30d-ticket-prom').textContent = pagos30?.length ? '$' + (sumaPagos/pagos30.length).toLocaleString(undefined,{maximumFractionDigits:0}) : '$0';
  root.querySelector('#kpi-30d-ocupacion').textContent = cajones ? ((tick30?.length ?? 0) / (30*cajones) * 100).toFixed(1) + '%' : '-';

  // Ingresos por día — usa DWH fact_pagos
  const { data: ingPorDia } = await supabase.schema('dwh')
    .from('fact_pagos')
    .select('fecha_cobro_id, monto')
    .gte('fecha_cobro_id', Number(fmtDateId(desde14)));
  const buckets = {};
  (ingPorDia??[]).forEach(x => { buckets[x.fecha_cobro_id] = (buckets[x.fecha_cobro_id]||0) + Number(x.monto||0); });
  const dias = Object.keys(buckets).sort();
  const maxVal = Math.max(1, ...Object.values(buckets));
  root.querySelector('#ing-por-dia').innerHTML = dias.length ? `
    <div class="space-y-1">
      ${dias.map(d => `
        <div class="flex items-center gap-2 text-xs">
          <span class="w-16 font-mono text-slate-500">${d.slice(4,6)}/${d.slice(6,8)}</span>
          <div class="flex-1 bg-slate-100 rounded h-4 relative">
            <div class="bg-barrera h-4 rounded" style="width:${(buckets[d]/maxVal*100).toFixed(1)}%"></div>
          </div>
          <span class="w-20 text-right text-marino font-semibold">$${buckets[d].toLocaleString(undefined,{maximumFractionDigits:0})}</span>
        </div>`).join('')}
    </div>` : '<div class="text-slate-400">Sin datos</div>';

  // Top estacionamientos
  const { data: topEst } = await supabase.schema('dwh').from('fact_pagos')
    .select('empresa_sk, estacionamiento_sk, monto').gte('fecha_cobro_id', Number(fmtDateId(desde30)));
  const estBucket = {};
  (topEst??[]).forEach(x => { estBucket[x.estacionamiento_sk] = (estBucket[x.estacionamiento_sk]||0) + Number(x.monto||0); });
  const { data: dimEst } = await supabase.schema('dwh').from('dim_estacionamiento').select('estacionamiento_sk, estacionamiento_nombre, empresa_nombre');
  const dimMap = Object.fromEntries((dimEst??[]).map(x=>[x.estacionamiento_sk, x]));
  const rank = Object.entries(estBucket).sort((a,b)=>b[1]-a[1]).slice(0,6);
  const maxE = Math.max(1, ...rank.map(x=>x[1]));
  root.querySelector('#top-est').innerHTML = rank.length ? `
    <div class="space-y-2">
      ${rank.map(([sk,val])=>`
        <div class="flex items-center gap-2 text-xs">
          <div class="flex-1">
            <div class="text-marino font-medium">${dimMap[sk]?.estacionamiento_nombre ?? sk}</div>
            <div class="text-slate-400 text-[10px]">${dimMap[sk]?.empresa_nombre ?? ''}</div>
            <div class="bg-slate-100 rounded h-2 mt-1"><div class="bg-marino h-2 rounded" style="width:${(val/maxE*100).toFixed(0)}%"></div></div>
          </div>
          <span class="w-20 text-right text-marino font-semibold">$${val.toLocaleString(undefined,{maximumFractionDigits:0})}</span>
        </div>`).join('')}
    </div>` : '<div class="text-slate-400">Sin datos</div>';

  // Por tipo
  const { data: porTipo } = await supabase.from('sesiones').select('tipo_sesion_id').gte('entrada_at', desde30.toISOString());
  const { data: tipos } = await supabase.from('cat_tipo_sesion').select('tipo_sesion_id, codigo');
  const tipoMap = Object.fromEntries((tipos??[]).map(x=>[x.tipo_sesion_id, x.codigo]));
  const cuentaTipo = {};
  (porTipo??[]).forEach(x => { const c = tipoMap[x.tipo_sesion_id]||'?'; cuentaTipo[c]=(cuentaTipo[c]||0)+1; });
  const maxT = Math.max(1, ...Object.values(cuentaTipo));
  root.querySelector('#por-tipo').innerHTML = `
    <div class="space-y-1">
      ${Object.entries(cuentaTipo).sort((a,b)=>b[1]-a[1]).map(([k,v])=>`
        <div class="flex items-center gap-2 text-xs">
          <span class="w-24 text-slate-600 capitalize">${k}</span>
          <div class="flex-1 bg-slate-100 rounded h-4"><div class="bg-marino h-4 rounded" style="width:${(v/maxT*100).toFixed(0)}%"></div></div>
          <span class="w-12 text-right text-marino font-semibold">${v}</span>
        </div>`).join('')}
    </div>`;

  // Por método de pago
  const { data: metodos } = await supabase.from('cat_metodo_pago').select('metodo_pago_id, codigo, nombre');
  const metMap = Object.fromEntries((metodos??[]).map(x=>[x.metodo_pago_id, x]));
  const { data: pagosMet } = await supabase.from('pagos').select('metodo_pago_id, monto').gte('cobrado_at', desde30.toISOString());
  const cuentaMet = {};
  (pagosMet??[]).forEach(x => { const c = metMap[x.metodo_pago_id]?.nombre||'?'; cuentaMet[c] = (cuentaMet[c]||{n:0,s:0}); cuentaMet[c].n++; cuentaMet[c].s += Number(x.monto||0); });
  root.querySelector('#por-metodo').innerHTML = `
    <ul class="divide-y">
      ${Object.entries(cuentaMet).sort((a,b)=>b[1].s-a[1].s).map(([k,v])=>`
        <li class="py-1.5 flex justify-between text-xs">
          <span>${k}</span>
          <span class="text-slate-500">${v.n} · <span class="text-marino font-semibold">$${v.s.toLocaleString(undefined,{maximumFractionDigits:0})}</span></span>
        </li>`).join('')}
    </ul>`;
}

function fmtDateId(d) { return `${d.getFullYear()}${String(d.getMonth()+1).padStart(2,'0')}${String(d.getDate()).padStart(2,'0')}`; }
function kpi(id,label,color) {
  return `<div class="op-card">
    <div class="text-xs text-slate-500 uppercase tracking-wide">${label}</div>
    <div id="kpi-${id}" class="text-2xl font-bold text-${color} mt-1">—</div>
  </div>`;
}
function shell(titulo, icon) {
  return `<header class="bg-marino text-white px-4 py-3 flex items-center justify-between shadow-md">
    <div class="flex items-center gap-3">
      <a href="#/" class="text-2xl">${icon}</a>
      <div class="leading-tight"><div class="font-semibold tracking-wide">ONLYPARK / ${titulo}</div></div>
    </div>
    <div class="flex items-center gap-4">
      <a href="#/" class="text-sm underline text-white/80">← Panel</a>
      <button id="op-logout" class="bg-white/10 hover:bg-white/20 text-sm rounded-md px-3 py-1.5 transition">Salir</button>
    </div>
  </header>`;
}
export function bindLogout(root) {
  const btn = root.querySelector('#op-logout');
  if (btn) btn.addEventListener('click', async () => {
    localStorage.removeItem('op_actor');
    await supabase.auth.signOut();
    window.location.hash = '/login';
  });
}
