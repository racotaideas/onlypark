import { supabase } from '../supabase.js';
import { renderScopeSelector, scopedEstacionamientos, scopeLabel } from '../api/scope.js';
import { bindLogout } from './reportes.js';
import { currentActor, log } from '../api/log.js';

export async function renderPensiones(root) {
  root.innerHTML = shell('Pensiones', '🎟️');
  bindLogout(root);
  await renderScopeSelector(root.querySelector('#scope-selector'));
  root.querySelector('#scope-label').textContent = 'Ámbito: ' + await scopeLabel();

  await refresh(root);
  window.addEventListener('op-scope-change', async () => {
    root.querySelector('#scope-label').textContent = 'Ámbito: ' + await scopeLabel();
    await refresh(root);
  });
  root.querySelector('#btn-nuevo').addEventListener('click', () => nuevoForm(root));
}

async function refresh(root) {
  const cont = root.querySelector('#cont');
  cont.innerHTML = 'Cargando…';
  const ests = await scopedEstacionamientos();
  const estIds = ests.map(x => x.estacionamiento_id);

  const { data, error } = await supabase.from('pensiones')
    .select('pension_id, monto_mensual, fecha_inicio, fecha_fin, dia_pago, codigo_acceso, tipo, estado, hora_inicio, hora_fin, notas, activo, estacionamiento_id, cliente_id')
    .in('estacionamiento_id', estIds.length ? estIds : ['00000000-0000-0000-0000-000000000000'])
    .order('fecha_inicio', { ascending: false });
  if (error) { cont.innerHTML = `<div class="op-card text-red-600">${error.message}</div>`; return; }

  const activas = (data ?? []).filter(x => x.estado === 'activo').length;
  const total = (data ?? []).reduce((a,x) => a + Number(x.monto_mensual || 0), 0);

  cont.innerHTML = `
    <div class="grid grid-cols-3 gap-4 mb-4">
      <div class="op-card"><div class="text-xs text-slate-500 uppercase">Total pensiones</div><div class="text-3xl font-bold text-marino mt-1">${data.length}</div></div>
      <div class="op-card"><div class="text-xs text-slate-500 uppercase">Activas</div><div class="text-3xl font-bold text-barrera-700 mt-1">${activas}</div></div>
      <div class="op-card"><div class="text-xs text-slate-500 uppercase">Mensualización total</div><div class="text-3xl font-bold text-marino mt-1">$${total.toLocaleString(undefined,{maximumFractionDigits:0})}</div></div>
    </div>

    <div class="op-card overflow-x-auto">
      <table class="w-full text-sm">
        <thead><tr class="text-slate-500 text-left">
          <th class="px-2 py-2">Código</th><th class="px-2 py-2">Tipo</th><th class="px-2 py-2">Estado</th>
          <th class="px-2 py-2">Inicio</th><th class="px-2 py-2">Vence</th>
          <th class="px-2 py-2">Horario</th><th class="px-2 py-2">Día pago</th>
          <th class="px-2 py-2 text-right">Monto</th><th></th>
        </tr></thead>
        <tbody>${data.map(p => `
          <tr class="border-t hover:bg-slate-50">
            <td class="px-2 py-1.5 font-mono">${p.codigo_acceso ?? '—'}</td>
            <td class="px-2 py-1.5 capitalize">${p.tipo ?? '—'}</td>
            <td class="px-2 py-1.5"><span class="inline-block px-2 py-0.5 rounded text-xs ${p.estado==='activo'?'bg-barrera/10 text-barrera-700':'bg-slate-200 text-slate-600'}">${p.estado ?? '—'}</span></td>
            <td class="px-2 py-1.5">${p.fecha_inicio ?? '—'}</td>
            <td class="px-2 py-1.5">${p.fecha_fin ?? '—'}</td>
            <td class="px-2 py-1.5">${(p.hora_inicio ?? '').slice(0,5)} - ${(p.hora_fin ?? '').slice(0,5)}</td>
            <td class="px-2 py-1.5">${p.dia_pago ?? '—'}</td>
            <td class="px-2 py-1.5 text-right font-semibold text-marino">$${Number(p.monto_mensual||0).toLocaleString(undefined,{maximumFractionDigits:0})}</td>
            <td class="px-2 py-1.5 text-right whitespace-nowrap">
              <button data-renovar="${p.pension_id}" class="text-marino underline text-xs mr-2">Renovar</button>
              <button data-cancel="${p.pension_id}" class="text-red-600 underline text-xs">Baja</button>
            </td>
          </tr>`).join('') || '<tr><td colspan="9" class="text-center text-slate-400 py-4">Sin pensiones en este ámbito</td></tr>'}
        </tbody>
      </table>
    </div>`;

  cont.querySelectorAll('[data-renovar]').forEach(b => b.addEventListener('click', async () => {
    const id = b.dataset.renovar;
    const meses = Number(prompt('Meses a renovar:', '1') || '0');
    if (meses <= 0) return;
    const { data: p } = await supabase.from('pensiones_base').select('fecha_fin').eq('pension_id', id).single();
    const nueva = new Date(p.fecha_fin || new Date());
    nueva.setMonth(nueva.getMonth() + meses);
    const { error } = await supabase.from('pensiones_base').update({ fecha_fin: nueva.toISOString().slice(0,10) }).eq('pension_id', id);
    if (error) alert(error.message);
    else { await log('operativa','renovar_pension',null,{pension_id:id, meses, actor:currentActor()}, `Renovación pensión ${meses}m`); await refresh(root); }
  }));

  cont.querySelectorAll('[data-cancel]').forEach(b => b.addEventListener('click', async () => {
    const id = b.dataset.cancel;
    if (!confirm('¿Dar de baja esta pensión?')) return;
    const { data: cep } = await supabase.from('cat_estado_pension').select('estado_pension_id').eq('codigo','inactivo').single();
    const { error } = await supabase.from('pensiones_base').update({
      estado_pension_id: cep?.estado_pension_id, activo: false
    }).eq('pension_id', id);
    if (error) alert(error.message);
    else { await log('seguridad','baja_pension',null,{pension_id:id, actor:currentActor()}, 'Baja pensión'); await refresh(root); }
  }));
}

async function nuevoForm(root) {
  const [ests, { data: clientes }, { data: tipos }] = await Promise.all([
    scopedEstacionamientos(),
    supabase.from('clientes').select('cliente_id, nombre, apellidos, empresa_id').eq('activo', true).order('nombre').limit(200),
    supabase.from('cat_tipo_pension').select('tipo_pension_id, codigo, nombre').eq('activo', true)
  ]);

  const wrap = document.createElement('div');
  wrap.className = 'fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4';
  wrap.innerHTML = `
    <form class="bg-white rounded-xl p-6 w-full max-w-lg overflow-y-auto max-h-full">
      <h3 class="text-lg font-semibold text-marino mb-3">Nueva pensión</h3>
      <div class="grid grid-cols-2 gap-2">
        <label class="col-span-2 text-sm">Estacionamiento<select name="estacionamiento_id" class="op-input mt-0.5" required>
          <option value="">— elegir —</option>
          ${ests.map(e => `<option value="${e.estacionamiento_id}">${e.nombre} (${e.codigo})</option>`).join('')}
        </select></label>
        <label class="col-span-2 text-sm">Cliente<select name="cliente_id" class="op-input mt-0.5" required>
          <option value="">— elegir —</option>
          ${(clientes ?? []).map(c => `<option value="${c.cliente_id}">${c.nombre} ${c.apellidos ?? ''}</option>`).join('')}
        </select></label>
        <label class="text-sm">Tipo<select name="tipo_pension_id" class="op-input mt-0.5" required>
          ${(tipos ?? []).map(t => `<option value="${t.tipo_pension_id}">${t.nombre}</option>`).join('')}
        </select></label>
        <label class="text-sm">Monto mensual<input name="monto_mensual" type="number" step="0.01" required class="op-input mt-0.5"></label>
        <label class="text-sm">Fecha inicio<input name="fecha_inicio" type="date" required value="${new Date().toISOString().slice(0,10)}" class="op-input mt-0.5"></label>
        <label class="text-sm">Fecha fin<input name="fecha_fin" type="date" required value="${new Date(Date.now()+90*86400000).toISOString().slice(0,10)}" class="op-input mt-0.5"></label>
        <label class="text-sm">Hora entrada<input name="hora_inicio" type="time" value="06:00" class="op-input mt-0.5"></label>
        <label class="text-sm">Hora salida<input name="hora_fin" type="time" value="22:00" class="op-input mt-0.5"></label>
        <label class="text-sm">Día de pago<input name="dia_pago" type="number" min="1" max="31" value="5" class="op-input mt-0.5"></label>
        <label class="text-sm">Código de acceso<input name="codigo_acceso" placeholder="PEN-XXXX" class="op-input mt-0.5"></label>
        <label class="col-span-2 text-sm">Notas<textarea name="notas" rows="2" class="op-input mt-0.5"></textarea></label>
      </div>
      <div class="flex justify-end gap-2 mt-4">
        <button type="button" data-cancel class="text-slate-500 py-2">Cancelar</button>
        <button type="submit" class="op-btn-primary">Crear pensión</button>
      </div>
      <p data-err class="text-red-600 text-sm mt-2 min-h-[1.25rem]"></p>
    </form>`;
  document.body.appendChild(wrap);
  wrap.querySelector('[data-cancel]').addEventListener('click', () => wrap.remove());
  wrap.querySelector('form').addEventListener('submit', async ev => {
    ev.preventDefault();
    const fd = Object.fromEntries(new FormData(ev.target).entries());
    const { data: ep } = await supabase.from('cat_estado_pension').select('estado_pension_id').eq('codigo','activo').single();
    const payload = {
      estacionamiento_id: fd.estacionamiento_id, cliente_id: fd.cliente_id,
      tipo_pension_id: fd.tipo_pension_id, estado_pension_id: ep?.estado_pension_id,
      monto_mensual: Number(fd.monto_mensual),
      fecha_inicio: fd.fecha_inicio, fecha_fin: fd.fecha_fin,
      hora_inicio: fd.hora_inicio || null, hora_fin: fd.hora_fin || null,
      dia_pago: Number(fd.dia_pago) || null,
      codigo_acceso: fd.codigo_acceso || null, notas: fd.notas || null,
      activo: true
    };
    const { error } = await supabase.from('pensiones_base').insert(payload);
    if (error) { wrap.querySelector('[data-err]').textContent = error.message; return; }
    await log('seguridad','alta_pension', fd.estacionamiento_id, { ...payload, actor: currentActor() }, `Alta pensión ${fd.codigo_acceso ?? ''}`);
    wrap.remove();
    await refresh(root);
  });
}

function shell(titulo, icon) {
  return `<header class="bg-marino text-white px-4 py-3 shadow-md">
    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center gap-3">
        <a href="#/" class="text-2xl">${icon}</a>
        <div class="leading-tight">
          <div class="font-semibold tracking-wide">ONLYPARK / ${titulo}</div>
          <div id="scope-label" class="text-xs text-white/60">…</div>
        </div>
      </div>
      <div class="flex items-center gap-4">
        <a href="#/" class="text-sm underline text-white/80">← Panel</a>
        <button id="op-logout" class="bg-white/10 hover:bg-white/20 text-sm rounded-md px-3 py-1.5 transition">Salir</button>
      </div>
    </div>
    <div id="scope-selector"></div>
  </header>
  <main class="flex-1 p-6 max-w-7xl mx-auto w-full">
    <div class="flex justify-between items-center mb-4">
      <h1 class="text-2xl font-bold text-marino">${titulo}</h1>
      <button id="btn-nuevo" class="op-btn-primary text-sm">+ Nueva pensión</button>
    </div>
    <div id="cont">…</div>
  </main>`;
}
