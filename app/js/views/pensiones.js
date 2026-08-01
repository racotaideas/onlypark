import { supabase } from '../supabase.js';
import { bindLogout } from './reportes.js';

export async function renderPensiones(root) {
  root.innerHTML = `
    <header class="bg-marino text-white px-4 py-3 flex items-center justify-between shadow-md">
      <div class="flex items-center gap-3">
        <a href="#/" class="text-2xl">🎟️</a>
        <div class="leading-tight"><div class="font-semibold tracking-wide">ONLYPARK / Pensiones</div></div>
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

  const { data, error } = await supabase.from('pensiones')
    .select('pension_id, monto_mensual, fecha_inicio, fecha_fin, dia_pago, codigo_acceso, tipo, estado, hora_inicio, hora_fin, estacionamiento_id')
    .order('fecha_inicio', { ascending:false });
  const cont = root.querySelector('#cont');
  if (error) { cont.innerHTML = `<div class="text-red-600">${error.message}</div>`; return; }

  const total = (data??[]).reduce((a,x)=>a+Number(x.monto_mensual||0), 0);

  cont.innerHTML = `
    <div class="grid grid-cols-3 gap-4 mb-4">
      <div class="op-card">
        <div class="text-xs text-slate-500 uppercase">Pensiones</div>
        <div class="text-3xl font-bold text-marino mt-1">${(data??[]).length}</div>
      </div>
      <div class="op-card">
        <div class="text-xs text-slate-500 uppercase">Mensualización total</div>
        <div class="text-3xl font-bold text-barrera-700 mt-1">$${total.toLocaleString(undefined,{maximumFractionDigits:0})}</div>
      </div>
      <div class="op-card">
        <div class="text-xs text-slate-500 uppercase">Ticket promedio</div>
        <div class="text-3xl font-bold text-marino mt-1">$${(data??[]).length ? (total/data.length).toLocaleString(undefined,{maximumFractionDigits:0}) : '0'}</div>
      </div>
    </div>

    <div class="op-card overflow-x-auto">
      <table class="w-full text-sm">
        <thead><tr class="text-slate-500 text-left">
          <th class="px-2 py-2">Código</th><th class="px-2 py-2">Tipo</th><th class="px-2 py-2">Estado</th>
          <th class="px-2 py-2">Inicio</th><th class="px-2 py-2">Vence</th>
          <th class="px-2 py-2">Horario</th><th class="px-2 py-2">Día pago</th>
          <th class="px-2 py-2 text-right">Monto</th>
        </tr></thead>
        <tbody>
          ${(data??[]).map(p => `
            <tr class="border-t">
              <td class="px-2 py-1.5 font-mono">${p.codigo_acceso ?? '—'}</td>
              <td class="px-2 py-1.5 capitalize">${p.tipo ?? '—'}</td>
              <td class="px-2 py-1.5">
                <span class="inline-block px-2 py-0.5 rounded text-xs ${p.estado==='activo' ? 'bg-barrera/10 text-barrera-700' : 'bg-slate-200 text-slate-600'}">${p.estado ?? '—'}</span>
              </td>
              <td class="px-2 py-1.5">${p.fecha_inicio ?? '—'}</td>
              <td class="px-2 py-1.5">${p.fecha_fin ?? '—'}</td>
              <td class="px-2 py-1.5">${(p.hora_inicio ?? '').slice(0,5)} - ${(p.hora_fin ?? '').slice(0,5)}</td>
              <td class="px-2 py-1.5">${p.dia_pago ?? '—'}</td>
              <td class="px-2 py-1.5 text-right font-semibold text-marino">$${Number(p.monto_mensual||0).toLocaleString(undefined,{maximumFractionDigits:0})}</td>
            </tr>`).join('') || '<tr><td colspan="8" class="text-center text-slate-400 py-4">Sin pensiones</td></tr>'}
        </tbody>
      </table>
    </div>`;
}
