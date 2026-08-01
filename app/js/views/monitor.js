import { supabase } from '../supabase.js';
import { bindLogout } from './reportes.js';

export async function renderMonitor(root) {
  root.innerHTML = `
    <header class="bg-marino text-white px-4 py-3 flex items-center justify-between shadow-md">
      <div class="flex items-center gap-3">
        <a href="#/" class="text-2xl">⚙️</a>
        <div class="leading-tight"><div class="font-semibold tracking-wide">ONLYPARK / Monitor ETL</div></div>
      </div>
      <div class="flex items-center gap-4">
        <a href="#/" class="text-sm underline text-white/80">← Panel</a>
        <button id="op-logout" class="bg-white/10 hover:bg-white/20 text-sm rounded-md px-3 py-1.5 transition">Salir</button>
      </div>
    </header>

    <main class="flex-1 p-6 max-w-7xl mx-auto w-full">
      <div class="flex justify-between items-center mb-4">
        <h2 class="text-lg font-semibold text-marino">Salud de cargas DWH</h2>
        <button id="btn-run" class="op-btn-primary text-sm">▶ Ejecutar ETL ahora</button>
      </div>

      <div id="jobs" class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">Cargando…</div>

      <h3 class="text-md font-semibold text-marino mb-3">Últimas ejecuciones</h3>
      <div id="ejec" class="op-card overflow-x-auto">Cargando…</div>

      <p id="msg" class="mt-3 text-sm min-h-[1.5rem]"></p>
    </main>`;

  bindLogout(root);

  await refresh(root);

  root.querySelector('#btn-run').addEventListener('click', async () => {
    const btn = root.querySelector('#btn-run'); const msg = root.querySelector('#msg');
    btn.disabled = true; btn.textContent = 'Ejecutando…';
    msg.textContent = '';
    const { data, error } = await supabase.schema('dwh').rpc('fn_etl_run_all');
    if (error) {
      msg.className = 'text-red-600 text-sm mt-3';
      msg.textContent = 'Error: ' + error.message;
    } else {
      msg.className = 'text-barrera-700 text-sm mt-3';
      msg.textContent = 'ETL OK — ' + JSON.stringify(data);
      await refresh(root);
    }
    btn.disabled = false; btn.textContent = '▶ Ejecutar ETL ahora';
  });
}

async function refresh(root) {
  const [{ data: monitor }, { data: ejec }] = await Promise.all([
    supabase.schema('dwh').from('v_etl_monitor').select('*'),
    supabase.schema('dwh').from('log_etl_ejecucion').select('*').order('inicio_at', { ascending:false }).limit(15)
  ]);

  root.querySelector('#jobs').innerHTML = (monitor ?? []).map(j => `
    <div class="op-card">
      <div class="flex justify-between items-start mb-2">
        <div>
          <div class="font-semibold text-marino">${j.job_codigo}</div>
          <div class="text-xs text-slate-500 mt-0.5">${j.descripcion ?? ''}</div>
        </div>
        <span class="px-2 py-0.5 rounded text-xs ${estadoColor(j.last_status)}">${j.last_status ?? '—'}</span>
      </div>
      <div class="grid grid-cols-2 gap-2 text-xs">
        <div><span class="text-slate-500">Última corrida:</span> <span class="font-mono">${j.last_run_at ? new Date(j.last_run_at).toLocaleString() : '—'}</span></div>
        <div><span class="text-slate-500">Filas in/out:</span> <span class="font-mono">${j.last_rows_in ?? 0} / ${j.last_rows_out ?? 0}</span></div>
        <div><span class="text-slate-500">Watermark:</span> <span class="font-mono">${j.last_watermark ? new Date(j.last_watermark).toLocaleString() : '—'}</span></div>
        <div><span class="text-slate-500">Errores tot:</span> <span class="font-mono">${j.errores_totales ?? 0}</span></div>
      </div>
    </div>`).join('') || '<div class="op-card text-slate-400">Sin jobs registrados</div>';

  root.querySelector('#ejec').innerHTML = `
    <table class="w-full text-xs">
      <thead><tr class="text-slate-500 text-left">
        <th class="px-2 py-2">Job</th><th class="px-2 py-2">Inicio</th><th class="px-2 py-2">Duración</th>
        <th class="px-2 py-2">Estado</th><th class="px-2 py-2">In</th><th class="px-2 py-2">Out</th><th class="px-2 py-2">Mensaje</th>
      </tr></thead>
      <tbody>${(ejec ?? []).map(r => `
        <tr class="border-t">
          <td class="px-2 py-1.5 font-mono">${r.job_codigo}</td>
          <td class="px-2 py-1.5">${new Date(r.inicio_at).toLocaleString()}</td>
          <td class="px-2 py-1.5">${r.duracion_ms ? (r.duracion_ms + ' ms') : '—'}</td>
          <td class="px-2 py-1.5"><span class="px-2 py-0.5 rounded ${estadoColor(r.estado)}">${r.estado}</span></td>
          <td class="px-2 py-1.5">${r.rows_in ?? '—'}</td>
          <td class="px-2 py-1.5">${r.rows_out ?? '—'}</td>
          <td class="px-2 py-1.5 text-slate-500">${(r.mensaje ?? '').slice(0,60)}</td>
        </tr>`).join('') || '<tr><td colspan="7" class="text-center text-slate-400 py-3">Sin ejecuciones</td></tr>'}
      </tbody>
    </table>`;
}

function estadoColor(e) {
  return {
    finalizado: 'bg-barrera/10 text-barrera-700',
    ejecutando: 'bg-yellow-100 text-yellow-700',
    error:      'bg-red-100 text-red-700',
    pendiente:  'bg-slate-100 text-slate-600'
  }[e] || 'bg-slate-100 text-slate-600';
}
