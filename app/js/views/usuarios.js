import { supabase } from '../supabase.js';
import { renderScopeSelector, scopedEstacionamientos, scopeLabel } from '../api/scope.js';
import { bindLogout } from './reportes.js';
import { currentActor, log } from '../api/log.js';

// Usuarios = perfiles_usuario + asignaciones_rol.
// Cajeros, supervisores, admins de plaza asignados a estacionamientos.
export async function renderUsuarios(root) {
  root.innerHTML = shell('Usuarios', '🔑');
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

  // Cajeros_view mapea perfiles_usuario + asignaciones_rol y expone rol_original
  const { data, error } = await supabase.from('cajeros')
    .select('cajero_id, usuario, nombre, rol, rol_original, activo, plaza_id, vigencia_desde, vigencia_hasta')
    .in('plaza_id', estIds.length ? estIds : ['00000000-0000-0000-0000-000000000000'])
    .order('nombre');
  if (error) { cont.innerHTML = `<div class="op-card text-red-600">${error.message}</div>`; return; }

  const activos = data.filter(x => x.activo).length;
  const porRol = {};
  data.forEach(x => { porRol[x.rol_original || x.rol] = (porRol[x.rol_original || x.rol] || 0) + 1; });

  cont.innerHTML = `
    <div class="grid grid-cols-3 gap-4 mb-4">
      <div class="op-card"><div class="text-xs text-slate-500 uppercase">Total usuarios</div><div class="text-3xl font-bold text-marino mt-1">${data.length}</div></div>
      <div class="op-card"><div class="text-xs text-slate-500 uppercase">Activos</div><div class="text-3xl font-bold text-barrera-700 mt-1">${activos}</div></div>
      <div class="op-card">
        <div class="text-xs text-slate-500 uppercase mb-1">Distribución de roles</div>
        <div class="text-xs space-y-0.5">${Object.entries(porRol).map(([r,n])=>`<div class="flex justify-between"><span class="text-slate-600">${r}</span><span class="font-semibold text-marino">${n}</span></div>`).join('')}</div>
      </div>
    </div>

    <div class="op-card overflow-x-auto">
      <table class="w-full text-sm">
        <thead><tr class="text-slate-500 text-left">
          <th class="px-2 py-2">Usuario</th><th class="px-2 py-2">Nombre</th><th class="px-2 py-2">Rol</th>
          <th class="px-2 py-2">Plaza</th><th class="px-2 py-2">Vigencia</th><th class="px-2 py-2">Estado</th>
        </tr></thead>
        <tbody>${data.map(u => `
          <tr class="border-t hover:bg-slate-50">
            <td class="px-2 py-1.5 font-mono text-xs">${u.usuario}</td>
            <td class="px-2 py-1.5">${u.nombre}</td>
            <td class="px-2 py-1.5"><span class="inline-block px-2 py-0.5 rounded text-xs bg-marino/10 text-marino">${u.rol_original ?? u.rol}</span></td>
            <td class="px-2 py-1.5 text-xs text-slate-500">${u.plaza_id ? u.plaza_id.slice(0,8)+'…' : '—'}</td>
            <td class="px-2 py-1.5 text-xs">${u.vigencia_desde ?? '—'}${u.vigencia_hasta ? ' → '+u.vigencia_hasta : ''}</td>
            <td class="px-2 py-1.5"><span class="inline-block px-2 py-0.5 rounded text-xs ${u.activo ? 'bg-barrera/10 text-barrera-700' : 'bg-slate-200 text-slate-600'}">${u.activo ? 'activo' : 'baja'}</span></td>
          </tr>`).join('') || '<tr><td colspan="6" class="text-center text-slate-400 py-4">Sin usuarios en este ámbito</td></tr>'}
        </tbody>
      </table>
    </div>`;
}

async function nuevoForm(root) {
  const [{ data: roles }, ests] = await Promise.all([
    supabase.from('cat_rol').select('rol_id, codigo, nombre').order('codigo'),
    scopedEstacionamientos()
  ]);
  const wrap = document.createElement('div');
  wrap.className = 'fixed inset-0 bg-black/40 flex items-center justify-center z-50';
  wrap.innerHTML = `
    <form class="bg-white rounded-xl p-6 w-full max-w-md">
      <h3 class="text-lg font-semibold text-marino mb-3">Nuevo usuario</h3>
      <div class="space-y-2">
        <label class="block text-sm">Usuario (email)<input name="email" type="email" class="op-input mt-0.5" required></label>
        <label class="block text-sm">Nombre completo<input name="nombre_completo" class="op-input mt-0.5" required></label>
        <label class="block text-sm">Rol<select name="rol_id" class="op-input mt-0.5" required>
          <option value="">— elegir —</option>
          ${(roles ?? []).map(r => `<option value="${r.rol_id}">${r.nombre}</option>`).join('')}
        </select></label>
        <label class="block text-sm">Estacionamiento (opcional)<select name="estacionamiento_id" class="op-input mt-0.5">
          <option value="">— sin restricción / según rol —</option>
          ${ests.map(e => `<option value="${e.estacionamiento_id}">${e.nombre} (${e.codigo})</option>`).join('')}
        </select></label>
        <label class="block text-sm">Contraseña provisional<input name="password" type="text" value="1234" class="op-input mt-0.5"></label>
      </div>
      <div class="flex justify-end gap-2 mt-4">
        <button type="button" data-cancel class="text-slate-500 py-2">Cancelar</button>
        <button type="submit" class="op-btn-primary">Crear</button>
      </div>
      <p data-err class="text-red-600 text-sm mt-2 min-h-[1.25rem]"></p>
    </form>`;
  document.body.appendChild(wrap);
  wrap.querySelector('[data-cancel]').addEventListener('click', () => wrap.remove());
  wrap.querySelector('form').addEventListener('submit', async ev => {
    ev.preventDefault();
    const fd = Object.fromEntries(new FormData(ev.target).entries());
    // SHA-256 hex de password
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(fd.password));
    const hash = [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2,'0')).join('');

    // 1) INSERT perfil (auth_user_id nullable en dev)
    const { data: perfil, error: e1 } = await supabase.from('perfiles_usuario').insert({
      email: fd.email, nombre_completo: fd.nombre_completo, activo: true, idioma:'es', password_hash: hash
    }).select().single();
    if (e1) { wrap.querySelector('[data-err]').textContent = e1.message; return; }

    // 2) Resolver jerarquía completa desde el estacionamiento (si aplica)
    let asig = { perfil_id: perfil.perfil_id, rol_id: fd.rol_id, activo: true };
    if (fd.estacionamiento_id) {
      const { data: e } = await supabase.from('estacionamientos').select('sucursal_id').eq('estacionamiento_id', fd.estacionamiento_id).single();
      const { data: s } = await supabase.from('sucursales').select('empresa_id').eq('sucursal_id', e.sucursal_id).single();
      const { data: em } = await supabase.from('empresas').select('grupo_id').eq('empresa_id', s.empresa_id).single();
      asig.estacionamiento_id = fd.estacionamiento_id;
      asig.sucursal_id = e.sucursal_id;
      asig.empresa_id = s.empresa_id;
      asig.grupo_id = em.grupo_id;
    }
    const { error: e2 } = await supabase.from('asignaciones_rol').insert(asig);
    if (e2) { wrap.querySelector('[data-err]').textContent = 'Perfil creado pero asignación falló: ' + e2.message; return; }

    await log('seguridad', 'alta_usuario', fd.estacionamiento_id || null, { email: fd.email, actor: currentActor() }, `Alta usuario ${fd.email}`);
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
