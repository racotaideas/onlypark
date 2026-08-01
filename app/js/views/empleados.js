import { supabase } from '../supabase.js';
import { renderScopeSelector, scopedEstacionamientos, scopeLabel } from '../api/scope.js';
import { bindLogout } from './reportes.js';
import { currentActor, log } from '../api/log.js';

// Empleados = clientes con tipo 'empleado', asignados a un estacionamiento.
// Reciben cortesía cuando entran con su auto.
export async function renderEmpleados(root) {
  root.innerHTML = shell('Empleados', '👥');
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
  const { data: tcs } = await supabase.from('cat_tipo_cliente').select('tipo_cliente_id, codigo').eq('codigo','empleado');
  const tcId = tcs?.[0]?.tipo_cliente_id;
  if (!tcId) { cont.innerHTML = '<div class="op-card text-red-600">Tipo cliente "empleado" no existe</div>'; return; }

  const { data, error } = await supabase.from('clientes')
    .select('cliente_id, nombre, apellidos, telefono, puesto, area, activo, estacionamiento_asignado_id, estacionamientos:estacionamiento_asignado_id(nombre, codigo)')
    .eq('tipo_cliente_id', tcId)
    .in('estacionamiento_asignado_id', estIds.length ? estIds : ['00000000-0000-0000-0000-000000000000'])
    .order('nombre');
  if (error) { cont.innerHTML = `<div class="op-card text-red-600">${error.message}</div>`; return; }

  const activos = data.filter(x => x.activo).length;
  cont.innerHTML = `
    <div class="grid grid-cols-3 gap-4 mb-4">
      <div class="op-card"><div class="text-xs text-slate-500 uppercase">Total empleados</div><div class="text-3xl font-bold text-marino mt-1">${data.length}</div></div>
      <div class="op-card"><div class="text-xs text-slate-500 uppercase">Activos</div><div class="text-3xl font-bold text-barrera-700 mt-1">${activos}</div></div>
      <div class="op-card"><div class="text-xs text-slate-500 uppercase">Plazas del ámbito</div><div class="text-3xl font-bold text-marino mt-1">${ests.length}</div></div>
    </div>
    <div class="op-card overflow-x-auto">
      <table class="w-full text-sm">
        <thead><tr class="text-slate-500 text-left"><th class="px-2 py-2">Nombre</th><th class="px-2 py-2">Puesto</th><th class="px-2 py-2">Área</th><th class="px-2 py-2">Teléfono</th><th class="px-2 py-2">Plaza</th><th class="px-2 py-2">Estado</th><th></th></tr></thead>
        <tbody>${data.map(e => `
          <tr class="border-t hover:bg-slate-50">
            <td class="px-2 py-1.5 font-medium">${e.nombre} ${e.apellidos ?? ''}</td>
            <td class="px-2 py-1.5">${e.puesto ?? '—'}</td>
            <td class="px-2 py-1.5">${e.area ?? '—'}</td>
            <td class="px-2 py-1.5 font-mono text-xs">${e.telefono ?? '—'}</td>
            <td class="px-2 py-1.5 text-xs">${e.estacionamientos?.nombre ?? '—'}</td>
            <td class="px-2 py-1.5">
              <span class="inline-block px-2 py-0.5 rounded text-xs ${e.activo ? 'bg-barrera/10 text-barrera-700' : 'bg-slate-200 text-slate-600'}">${e.activo ? 'activo' : 'baja'}</span>
            </td>
            <td class="px-2 py-1.5 text-right">
              <button data-toggle="${e.cliente_id}" data-activo="${e.activo}" class="text-marino underline text-xs">${e.activo ? 'Dar de baja' : 'Reactivar'}</button>
            </td>
          </tr>`).join('') || '<tr><td colspan="7" class="text-center text-slate-400 py-4">Sin empleados</td></tr>'}
        </tbody>
      </table>
    </div>`;

  cont.querySelectorAll('[data-toggle]').forEach(b => b.addEventListener('click', async () => {
    const id = b.dataset.toggle; const nuevo = b.dataset.activo !== 'true';
    const { error } = await supabase.from('clientes').update({ activo: nuevo }).eq('cliente_id', id);
    if (error) alert(error.message); else { await log('seguridad', 'toggle_empleado', null, { cliente_id:id, activo:nuevo, actor:currentActor() }, `Empleado ${nuevo?'reactivado':'baja'}`); await refresh(root); }
  }));
}

async function nuevoForm(root) {
  const ests = await scopedEstacionamientos();
  const wrap = document.createElement('div');
  wrap.className = 'fixed inset-0 bg-black/40 flex items-center justify-center z-50';
  wrap.innerHTML = `
    <form class="bg-white rounded-xl p-6 w-full max-w-md">
      <h3 class="text-lg font-semibold text-marino mb-3">Nuevo empleado</h3>
      <div class="grid grid-cols-2 gap-2">
        <label class="col-span-2 text-sm">Nombre<input name="nombre" class="op-input mt-0.5" required></label>
        <label class="col-span-2 text-sm">Apellidos<input name="apellidos" class="op-input mt-0.5"></label>
        <label class="text-sm">Puesto<input name="puesto" class="op-input mt-0.5"></label>
        <label class="text-sm">Área<input name="area" class="op-input mt-0.5"></label>
        <label class="col-span-2 text-sm">Teléfono<input name="telefono" class="op-input mt-0.5"></label>
        <label class="col-span-2 text-sm">Estacionamiento<select name="estacionamiento_asignado_id" class="op-input mt-0.5" required>
          <option value="">— elegir —</option>
          ${ests.map(e => `<option value="${e.estacionamiento_id}">${e.nombre} (${e.codigo})</option>`).join('')}
        </select></label>
      </div>
      <div class="flex justify-end gap-2 mt-4">
        <button type="button" data-cancel class="text-slate-500 py-2">Cancelar</button>
        <button type="submit" class="op-btn-primary">Guardar</button>
      </div>
      <p data-err class="text-red-600 text-sm mt-2 min-h-[1.25rem]"></p>
    </form>`;
  document.body.appendChild(wrap);
  wrap.querySelector('[data-cancel]').addEventListener('click', () => wrap.remove());
  wrap.querySelector('form').addEventListener('submit', async ev => {
    ev.preventDefault();
    const fd = Object.fromEntries(new FormData(ev.target).entries());
    const { data: tc } = await supabase.from('cat_tipo_cliente').select('tipo_cliente_id').eq('codigo','empleado').single();
    const { data: est } = await supabase.from('estacionamientos').select('sucursal_id').eq('estacionamiento_id', fd.estacionamiento_asignado_id).single();
    const { data: suc } = await supabase.from('sucursales').select('empresa_id').eq('sucursal_id', est.sucursal_id).single();
    const { error } = await supabase.from('clientes').insert({
      ...fd, tipo_cliente_id: tc.tipo_cliente_id, empresa_id: suc.empresa_id, activo: true
    });
    if (error) { wrap.querySelector('[data-err]').textContent = error.message; return; }
    await log('seguridad', 'alta_empleado', fd.estacionamiento_asignado_id, { ...fd, actor:currentActor() }, `Alta empleado ${fd.nombre}`);
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
      <button id="btn-nuevo" class="op-btn-primary text-sm">+ Nuevo</button>
    </div>
    <div id="cont">…</div>
  </main>`;
}
