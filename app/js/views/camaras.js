import { supabase } from '../supabase.js';
import { bindLogout } from './reportes.js';

export async function renderCamaras(root) {
  root.innerHTML = `
    <header class="bg-marino text-white px-4 py-3 flex items-center justify-between shadow-md">
      <div class="flex items-center gap-3">
        <a href="#/" class="text-2xl">📹</a>
        <div class="leading-tight"><div class="font-semibold tracking-wide">ONLYPARK / Cámaras LPR</div></div>
      </div>
      <div class="flex items-center gap-4">
        <a href="#/" class="text-sm underline text-white/80">← Panel</a>
        <button id="op-logout" class="bg-white/10 hover:bg-white/20 text-sm rounded-md px-3 py-1.5 transition">Salir</button>
      </div>
    </header>
    <main class="flex-1 p-6 max-w-7xl mx-auto w-full">
      <div id="cont">Cargando…</div>
    </main>`;
  bindLogout(root);

  const { data, error } = await supabase.from('camaras')
    .select('camara_id, codigo, nombre, proposito, activa, es_simulada, estacionamiento_id, estacionamientos(nombre)')
    .order('codigo');
  const cont = root.querySelector('#cont');
  if (error) { cont.innerHTML = `<div class="text-red-600">${error.message}</div>`; return; }

  const porEstac = {};
  (data??[]).forEach(c => { const k = c.estacionamientos?.nombre ?? '—'; (porEstac[k] = porEstac[k] || []).push(c); });

  cont.innerHTML = Object.entries(porEstac).map(([est, cams]) => `
    <div class="mb-6">
      <h3 class="text-marino font-semibold mb-2">${est} <span class="text-slate-400 text-sm">(${cams.length})</span></h3>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
        ${cams.map(c => `
          <div class="op-card">
            <div class="flex justify-between items-start mb-2">
              <div>
                <div class="font-mono text-xs text-slate-500">${c.codigo}</div>
                <div class="font-semibold text-marino">${c.nombre}</div>
              </div>
              <span class="px-2 py-0.5 rounded text-xs ${c.activa ? 'bg-barrera/10 text-barrera-700' : 'bg-slate-200 text-slate-500'}">${c.activa ? 'activa' : 'inactiva'}</span>
            </div>
            <div class="aspect-video bg-slate-900 rounded flex items-center justify-center relative">
              <div class="text-white/30 text-4xl">📷</div>
              <span class="absolute bottom-1 right-2 text-white/60 text-xs">${c.es_simulada ? 'SIMULADA' : 'RTSP'}</span>
              <span class="absolute top-1 left-2 px-1.5 py-0.5 rounded text-[10px] font-bold ${c.proposito==='entrada'?'bg-barrera text-white':'bg-marino text-white'}">${c.proposito.toUpperCase()}</span>
            </div>
          </div>`).join('')}
      </div>
    </div>`).join('') || '<div class="op-card text-slate-400">Sin cámaras registradas</div>';
}
