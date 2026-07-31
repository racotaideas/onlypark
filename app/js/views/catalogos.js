import {
  listGrupos, upsertGrupo,
  listEmpresas, upsertEmpresa, optionsGrupos,
  listSucursales, upsertSucursal, optionsEmpresas,
  listEstacionamientos, upsertEstacionamiento, optionsSucursales,
} from '../api/jerarquia.js';

const TABS = [
  { key: 'grupos',           label: 'Grupos',           list: listGrupos,           form: formGrupo },
  { key: 'empresas',         label: 'Empresas',         list: listEmpresas,         form: formEmpresa },
  { key: 'sucursales',       label: 'Sucursales',       list: listSucursales,       form: formSucursal },
  { key: 'estacionamientos', label: 'Estacionamientos', list: listEstacionamientos, form: formEstacionamiento },
];

export async function renderCatalogos(root, tabKey = 'grupos') {
  const tab = TABS.find(t => t.key === tabKey) ?? TABS[0];
  root.innerHTML = shellHtml(tab.key);
  bindLogout(root);

  const cnt = root.querySelector('#op-cnt');
  const { data, error } = await tab.list();
  if (error) { cnt.innerHTML = `<div class="text-red-600">Error: ${error.message}</div>`; return; }

  cnt.innerHTML = `
    <div class="flex justify-between mb-3">
      <h2 class="text-lg font-semibold text-marino">${tab.label} (${data.length})</h2>
      <button id="op-new" class="op-btn-primary text-sm">+ Nuevo</button>
    </div>
    <div class="op-card overflow-x-auto"><table class="w-full text-sm">
      <thead><tr class="text-slate-500 text-left">${headers(tab.key)}</tr></thead>
      <tbody>${data.map(r => rowHtml(tab.key, r)).join('') || '<tr><td colspan="6" class="p-6 text-center text-slate-400">Sin registros visibles (RLS)</td></tr>'}</tbody>
    </table></div>
    <div id="op-form-cnt" class="mt-4"></div>`;

  cnt.querySelector('#op-new').addEventListener('click', () => renderForm(root, tab, null));
  cnt.querySelectorAll('[data-edit]').forEach(btn => btn.addEventListener('click', async () => {
    const id = btn.dataset.edit;
    const rec = data.find(x => Object.values(x).includes(id));
    renderForm(root, tab, rec);
  }));
}

function shellHtml(active) {
  const tabsHtml = TABS.map(t => `
    <a href="#/catalogos/${t.key}"
       class="px-3 py-2 rounded-md text-sm ${t.key===active?'bg-marino text-white':'text-marino hover:bg-slate-100'}">
      ${t.label}
    </a>`).join('');
  return `
    <header class="bg-marino text-white px-4 py-3 flex items-center justify-between">
      <div class="flex items-center gap-2">
        <a href="#/" class="w-8 h-8 rounded-md bg-barrera flex items-center justify-center font-bold">P</a>
        <span class="font-semibold tracking-wide">ONLYPARK / Catálogos</span>
      </div>
      <div class="flex items-center gap-4">
        <div class="text-right leading-tight">
          <div class="text-xs text-white/60">Operando como</div>
          <div class="text-sm font-medium">${(localStorage.getItem('op_actor') || 'operador')}</div>
        </div>
        <button id="op-logout" class="bg-white/10 hover:bg-white/20 text-sm rounded-md px-3 py-1.5 transition">Salir</button>
      </div>
    </header>
    <main class="flex-1 p-6 max-w-6xl mx-auto w-full">
      <nav class="flex gap-1 mb-4 border-b pb-2">${tabsHtml}</nav>
      <div id="op-cnt"></div>
    </main>`;
}

function bindLogout(root) {
  const btn = root.querySelector('#op-logout');
  if (btn) btn.addEventListener('click', async () => {
    const { supabase } = await import('../supabase.js');
    localStorage.removeItem('op_actor');
    await supabase.auth.signOut();
    window.location.hash = '/login';
  });
}

function headers(key) {
  const cols = {
    grupos:           ['Código','Nombre','Activo',''],
    empresas:         ['Código','Razón social','Grupo','Activo',''],
    sucursales:       ['Código','Nombre','Empresa','Activo',''],
    estacionamientos: ['Código','Nombre','Sucursal','Capacidad','Activo',''],
  }[key];
  return cols.map(c => `<th class="px-2 py-2 font-medium">${c}</th>`).join('');
}

function rowHtml(key, r) {
  if (key === 'grupos') return `<tr class="border-t"><td class="px-2 py-2">${r.codigo}</td><td class="px-2 py-2">${r.nombre}</td><td class="px-2 py-2">${badge(r.activo)}</td><td class="px-2 py-2 text-right"><button data-edit="${r.grupo_id}" class="text-marino underline text-sm">Editar</button></td></tr>`;
  if (key === 'empresas') return `<tr class="border-t"><td class="px-2 py-2">${r.codigo}</td><td class="px-2 py-2">${r.razon_social}</td><td class="px-2 py-2">${r.grupos_empresariales?.nombre ?? '-'}</td><td class="px-2 py-2">${badge(r.activo)}</td><td class="px-2 py-2 text-right"><button data-edit="${r.empresa_id}" class="text-marino underline text-sm">Editar</button></td></tr>`;
  if (key === 'sucursales') return `<tr class="border-t"><td class="px-2 py-2">${r.codigo}</td><td class="px-2 py-2">${r.nombre}</td><td class="px-2 py-2">${r.empresas?.razon_social ?? '-'}</td><td class="px-2 py-2">${badge(r.activo)}</td><td class="px-2 py-2 text-right"><button data-edit="${r.sucursal_id}" class="text-marino underline text-sm">Editar</button></td></tr>`;
  return `<tr class="border-t"><td class="px-2 py-2">${r.codigo}</td><td class="px-2 py-2">${r.nombre}</td><td class="px-2 py-2">${r.sucursales?.nombre ?? '-'}</td><td class="px-2 py-2">${r.capacidad_total ?? '-'}</td><td class="px-2 py-2">${badge(r.activo)}</td><td class="px-2 py-2 text-right"><button data-edit="${r.estacionamiento_id}" class="text-marino underline text-sm">Editar</button></td></tr>`;
}

function badge(active) {
  return active
    ? '<span class="inline-block px-2 py-0.5 rounded text-xs bg-barrera/10 text-barrera-700">activo</span>'
    : '<span class="inline-block px-2 py-0.5 rounded text-xs bg-slate-200 text-slate-600">inactivo</span>';
}

async function renderForm(root, tab, rec) {
  const cnt = root.querySelector('#op-form-cnt');
  cnt.innerHTML = '<div class="op-card">Cargando…</div>';
  cnt.innerHTML = await tab.form(rec);

  cnt.querySelector('form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const fd = Object.fromEntries(new FormData(e.target).entries());
    // Normalización
    if ('activo' in fd) fd.activo = fd.activo === 'on';
    if (fd.capacidad_total === '') delete fd.capacidad_total;
    else if (fd.capacidad_total) fd.capacidad_total = Number(fd.capacidad_total);
    Object.keys(fd).forEach(k => { if (fd[k] === '') fd[k] = null; });
    // Determinar upsert por tab
    const map = { grupos: upsertGrupo, empresas: upsertEmpresa, sucursales: upsertSucursal, estacionamientos: upsertEstacionamiento };
    const res = await map[tab.key](fd);
    const err = cnt.querySelector('#op-form-msg');
    if (res.error) { err.textContent = res.error.message; err.className = 'text-red-600 text-sm mt-2'; return; }
    err.textContent = 'Guardado ✓'; err.className = 'text-barrera-700 text-sm mt-2';
    setTimeout(() => renderCatalogos(root, tab.key), 600);
  });
}

// ---------- forms por entidad (retornan HTML) ----------
async function formGrupo(rec) {
  return `<div class="op-card"><h3 class="font-semibold mb-3">${rec?'Editar':'Nuevo'} grupo</h3>
    <form class="grid grid-cols-2 gap-3">
      ${rec ? `<input type="hidden" name="grupo_id" value="${rec.grupo_id}">` : ''}
      <label>Código<input class="op-input" name="codigo" required value="${rec?.codigo ?? ''}"></label>
      <label>Nombre<input class="op-input" name="nombre" required value="${rec?.nombre ?? ''}"></label>
      <label class="flex items-center gap-2 col-span-2 mt-2"><input type="checkbox" name="activo" ${rec?.activo!==false?'checked':''}> Activo</label>
      <div class="col-span-2 flex gap-2 mt-2">
        <button type="submit" class="op-btn-primary">Guardar</button>
        <a href="#/catalogos/grupos" class="text-slate-500 py-2">Cancelar</a>
      </div>
      <p id="op-form-msg" class="col-span-2"></p>
    </form></div>`;
}

async function formEmpresa(rec) {
  const grupos = await optionsGrupos();
  const opts = grupos.map(g => `<option value="${g.grupo_id}" ${rec?.grupo_id===g.grupo_id?'selected':''}>${g.nombre}</option>`).join('');
  return `<div class="op-card"><h3 class="font-semibold mb-3">${rec?'Editar':'Nueva'} empresa</h3>
    <form class="grid grid-cols-2 gap-3">
      ${rec ? `<input type="hidden" name="empresa_id" value="${rec.empresa_id}">` : ''}
      <label class="col-span-2">Grupo<select class="op-input" name="grupo_id" required><option value="">— elegir —</option>${opts}</select></label>
      <label>Código<input class="op-input" name="codigo" required value="${rec?.codigo ?? ''}"></label>
      <label>RFC<input class="op-input" name="rfc" value="${rec?.rfc ?? ''}"></label>
      <label class="col-span-2">Razón social<input class="op-input" name="razon_social" required value="${rec?.razon_social ?? ''}"></label>
      <label class="col-span-2">Nombre comercial<input class="op-input" name="nombre_comercial" value="${rec?.nombre_comercial ?? ''}"></label>
      <label class="flex items-center gap-2 col-span-2 mt-2"><input type="checkbox" name="activo" ${rec?.activo!==false?'checked':''}> Activa</label>
      <div class="col-span-2 flex gap-2 mt-2">
        <button type="submit" class="op-btn-primary">Guardar</button>
        <a href="#/catalogos/empresas" class="text-slate-500 py-2">Cancelar</a>
      </div>
      <p id="op-form-msg" class="col-span-2"></p>
    </form></div>`;
}

async function formSucursal(rec) {
  const empresas = await optionsEmpresas(null);
  const opts = empresas.map(e => `<option value="${e.empresa_id}" ${rec?.empresa_id===e.empresa_id?'selected':''}>${e.razon_social}</option>`).join('');
  return `<div class="op-card"><h3 class="font-semibold mb-3">${rec?'Editar':'Nueva'} sucursal</h3>
    <form class="grid grid-cols-2 gap-3">
      ${rec ? `<input type="hidden" name="sucursal_id" value="${rec.sucursal_id}">` : ''}
      <label class="col-span-2">Empresa<select class="op-input" name="empresa_id" required><option value="">— elegir —</option>${opts}</select></label>
      <label>Código<input class="op-input" name="codigo" required value="${rec?.codigo ?? ''}"></label>
      <label>Nombre<input class="op-input" name="nombre" required value="${rec?.nombre ?? ''}"></label>
      <label class="col-span-2">Dirección<input class="op-input" name="direccion" value="${rec?.direccion ?? ''}"></label>
      <label>Teléfono<input class="op-input" name="telefono" value="${rec?.telefono ?? ''}"></label>
      <label class="flex items-center gap-2 mt-2"><input type="checkbox" name="activo" ${rec?.activo!==false?'checked':''}> Activa</label>
      <div class="col-span-2 flex gap-2 mt-2">
        <button type="submit" class="op-btn-primary">Guardar</button>
        <a href="#/catalogos/sucursales" class="text-slate-500 py-2">Cancelar</a>
      </div>
      <p id="op-form-msg" class="col-span-2"></p>
    </form></div>`;
}

async function formEstacionamiento(rec) {
  const sucs = await optionsSucursales(null);
  const opts = sucs.map(s => `<option value="${s.sucursal_id}" ${rec?.sucursal_id===s.sucursal_id?'selected':''}>${s.nombre}</option>`).join('');
  return `<div class="op-card"><h3 class="font-semibold mb-3">${rec?'Editar':'Nuevo'} estacionamiento</h3>
    <form class="grid grid-cols-2 gap-3">
      ${rec ? `<input type="hidden" name="estacionamiento_id" value="${rec.estacionamiento_id}">` : ''}
      <label class="col-span-2">Sucursal<select class="op-input" name="sucursal_id" required><option value="">— elegir —</option>${opts}</select></label>
      <label>Código<input class="op-input" name="codigo" required value="${rec?.codigo ?? ''}"></label>
      <label>Nombre<input class="op-input" name="nombre" required value="${rec?.nombre ?? ''}"></label>
      <label>Capacidad total<input class="op-input" type="number" min="0" name="capacidad_total" value="${rec?.capacidad_total ?? ''}"></label>
      <label class="flex items-center gap-2 mt-2"><input type="checkbox" name="activo" ${rec?.activo!==false?'checked':''}> Activo</label>
      <div class="col-span-2 flex gap-2 mt-2">
        <button type="submit" class="op-btn-primary">Guardar</button>
        <a href="#/catalogos/estacionamientos" class="text-slate-500 py-2">Cancelar</a>
      </div>
      <p id="op-form-msg" class="col-span-2"></p>
    </form></div>`;
}
