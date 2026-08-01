// Selector de ámbito operativo (dev mode) — 3 niveles jerárquicos:
//   GRUPO → EMPRESA → ESTACIONAMIENTO
//
// Simula lo que en producción vendría del rol del usuario logueado:
//   - Todos vacíos            = corporativo (todo)
//   - Grupo X                 = corporativo de grupo (toda la cadena)
//   - Grupo X + Empresa Y     = admin de empresa (todas sus plazas)
//   - Grupo X + Emp Y + Est Z = admin de plaza (solo esa)
//
// Persiste en localStorage. Publica 'op-scope-change' al cambiar.
import { supabase } from '../supabase.js';

const K_GRP = 'op_scope_grupo_id';
const K_EMP = 'op_scope_empresa_id';
const K_EST = 'op_scope_estacionamiento_id';

export function getScope() {
  return {
    grupo_id:            localStorage.getItem(K_GRP) || null,
    empresa_id:          localStorage.getItem(K_EMP) || null,
    estacionamiento_id:  localStorage.getItem(K_EST) || null,
  };
}
export function setScope(grupo_id, empresa_id, estacionamiento_id) {
  const put = (k,v) => v ? localStorage.setItem(k,v) : localStorage.removeItem(k);
  put(K_GRP, grupo_id); put(K_EMP, empresa_id); put(K_EST, estacionamiento_id);
  window.dispatchEvent(new CustomEvent('op-scope-change', { detail: getScope() }));
}

export async function scopedGrupos() {
  const s = getScope();
  let q = supabase.from('grupos_empresariales').select('grupo_id, codigo, nombre');
  if (s.grupo_id) q = q.eq('grupo_id', s.grupo_id);
  const { data } = await q.order('nombre');
  return data ?? [];
}

export async function scopedEmpresas() {
  const s = getScope();
  let q = supabase.from('empresas').select('empresa_id, codigo, razon_social, grupo_id');
  if (s.empresa_id) q = q.eq('empresa_id', s.empresa_id);
  else if (s.grupo_id) q = q.eq('grupo_id', s.grupo_id);
  const { data } = await q.order('razon_social');
  return data ?? [];
}

export async function scopedEstacionamientos() {
  const s = getScope();
  let q = supabase.from('estacionamientos').select('estacionamiento_id, codigo, nombre, capacidad_total, sucursal_id');
  if (s.estacionamiento_id) q = q.eq('estacionamiento_id', s.estacionamiento_id);
  else {
    // Resolver por empresa o grupo
    let empresaIds = [];
    if (s.empresa_id) empresaIds = [s.empresa_id];
    else if (s.grupo_id) {
      const { data: em } = await supabase.from('empresas').select('empresa_id').eq('grupo_id', s.grupo_id);
      empresaIds = (em ?? []).map(x => x.empresa_id);
    }
    if (empresaIds.length) {
      const { data: sucs } = await supabase.from('sucursales').select('sucursal_id').in('empresa_id', empresaIds);
      q = q.in('sucursal_id', (sucs ?? []).map(x => x.sucursal_id));
    }
  }
  const { data } = await q.order('nombre');
  return data ?? [];
}

// Renderiza el selector de 3 niveles en un contenedor.
export async function renderScopeSelector(container) {
  const s = getScope();
  const { data: grupos } = await supabase.from('grupos_empresariales')
    .select('grupo_id, codigo, nombre').order('nombre');

  container.innerHTML = `
    <div class="flex flex-wrap items-center gap-2 text-xs">
      <span class="text-white/70 hidden sm:inline uppercase tracking-wider text-[10px]">Ámbito:</span>
      <select id="scope-grp" class="bg-white/10 hover:bg-white/20 text-white rounded px-2 py-1 outline-none border border-white/20 min-w-[130px]">
        <option value="">Todos los grupos</option>
        ${(grupos??[]).map(g => `<option value="${g.grupo_id}" ${s.grupo_id===g.grupo_id?'selected':''}>${g.nombre}</option>`).join('')}
      </select>
      <span class="text-white/40">›</span>
      <select id="scope-emp" class="bg-white/10 hover:bg-white/20 text-white rounded px-2 py-1 outline-none border border-white/20 min-w-[170px]">
        <option value="">Todas las empresas</option>
      </select>
      <span class="text-white/40">›</span>
      <select id="scope-est" class="bg-white/10 hover:bg-white/20 text-white rounded px-2 py-1 outline-none border border-white/20 min-w-[170px]">
        <option value="">Todos los estacionamientos</option>
      </select>
      <button id="scope-reset" class="ml-1 text-white/60 hover:text-white text-[11px] underline">reset</button>
    </div>`;

  const selGrp = container.querySelector('#scope-grp');
  const selEmp = container.querySelector('#scope-emp');
  const selEst = container.querySelector('#scope-est');
  const btnReset = container.querySelector('#scope-reset');

  async function reloadEmpresas(preserveEmp) {
    const grpId = selGrp.value || null;
    let q = supabase.from('empresas').select('empresa_id, razon_social, codigo, grupo_id');
    if (grpId) q = q.eq('grupo_id', grpId);
    const { data } = await q.order('razon_social');
    selEmp.innerHTML = `<option value="">Todas las empresas</option>` +
      (data ?? []).map(x => `<option value="${x.empresa_id}" ${preserveEmp===x.empresa_id?'selected':''}>${x.razon_social}</option>`).join('');
  }

  async function reloadEstacionamientos(preserveEst) {
    const grpId = selGrp.value || null;
    const empId = selEmp.value || null;
    let empresaIds = [];
    if (empId) empresaIds = [empId];
    else if (grpId) {
      const { data: em } = await supabase.from('empresas').select('empresa_id').eq('grupo_id', grpId);
      empresaIds = (em ?? []).map(x => x.empresa_id);
    }
    let q = supabase.from('estacionamientos').select('estacionamiento_id, nombre, codigo, sucursal_id');
    if (empresaIds.length) {
      const { data: sucs } = await supabase.from('sucursales').select('sucursal_id').in('empresa_id', empresaIds);
      q = q.in('sucursal_id', (sucs ?? []).map(x => x.sucursal_id));
    }
    const { data } = await q.order('nombre');
    selEst.innerHTML = `<option value="">Todos los estacionamientos</option>` +
      (data ?? []).map(x => `<option value="${x.estacionamiento_id}" ${preserveEst===x.estacionamiento_id?'selected':''}>${x.nombre} · ${x.codigo}</option>`).join('');
  }

  await reloadEmpresas(s.empresa_id);
  await reloadEstacionamientos(s.estacionamiento_id);

  selGrp.addEventListener('change', async () => {
    setScope(selGrp.value || null, null, null);
    await reloadEmpresas(null);
    await reloadEstacionamientos(null);
  });
  selEmp.addEventListener('change', async () => {
    setScope(selGrp.value || null, selEmp.value || null, null);
    await reloadEstacionamientos(null);
  });
  selEst.addEventListener('change', () => {
    setScope(selGrp.value || null, selEmp.value || null, selEst.value || null);
  });
  btnReset.addEventListener('click', async () => {
    setScope(null, null, null);
    selGrp.value = ''; selEmp.value = ''; selEst.value = '';
    await reloadEmpresas(null);
    await reloadEstacionamientos(null);
  });
}

// Devuelve etiqueta descriptiva del ámbito actual.
export async function scopeLabel() {
  const s = getScope();
  if (!s.grupo_id && !s.empresa_id && !s.estacionamiento_id) return 'Corporativo · todos los grupos';
  const [grupos, empresas, estac] = await Promise.all([scopedGrupos(), scopedEmpresas(), scopedEstacionamientos()]);
  if (s.estacionamiento_id) return `${grupos[0]?.nombre ?? '—'} › ${empresas[0]?.razon_social ?? '—'} › ${estac[0]?.nombre ?? '—'}`;
  if (s.empresa_id) return `${grupos[0]?.nombre ?? '—'} › ${empresas[0]?.razon_social ?? '—'} · todas las plazas`;
  return `${grupos[0]?.nombre ?? '—'} · toda la cadena`;
}
