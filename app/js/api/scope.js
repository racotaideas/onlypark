// Selector de ámbito operativo (dev mode).
// Simula el filtrado que en producción vendría del rol del usuario logueado.
// - Empresa "todas" + Estacionamiento "todos" = ámbito corporativo (todo)
// - Empresa X + Estacionamiento "todos" = admin de empresa (toda la empresa)
// - Empresa X + Estacionamiento Y = admin de plaza (solo ese estac)
//
// Persiste en localStorage y publica un evento 'op-scope-change' para que
// las vistas se re-rendereen cuando cambia.
import { supabase } from '../supabase.js';

const K_EMP = 'op_scope_empresa_id';
const K_EST = 'op_scope_estacionamiento_id';

export function getScope() {
  return {
    empresa_id:          localStorage.getItem(K_EMP) || null,
    estacionamiento_id:  localStorage.getItem(K_EST) || null,
  };
}
export function setScope(empresa_id, estacionamiento_id) {
  if (empresa_id) localStorage.setItem(K_EMP, empresa_id); else localStorage.removeItem(K_EMP);
  if (estacionamiento_id) localStorage.setItem(K_EST, estacionamiento_id); else localStorage.removeItem(K_EST);
  window.dispatchEvent(new CustomEvent('op-scope-change', { detail: getScope() }));
}

// Devuelve la lista de estacionamiento_ids que caen dentro del ámbito actual.
export async function scopedEstacionamientos() {
  const s = getScope();
  let q = supabase.from('estacionamientos').select('estacionamiento_id, codigo, nombre, capacidad_total, sucursal_id');
  if (s.estacionamiento_id) q = q.eq('estacionamiento_id', s.estacionamiento_id);
  else if (s.empresa_id) {
    const { data: sucs } = await supabase.from('sucursales').select('sucursal_id').eq('empresa_id', s.empresa_id);
    q = q.in('sucursal_id', (sucs ?? []).map(x => x.sucursal_id));
  }
  const { data } = await q.order('nombre');
  return data ?? [];
}

export async function scopedEmpresas() {
  const s = getScope();
  let q = supabase.from('empresas').select('empresa_id, codigo, razon_social, grupo_id');
  if (s.empresa_id) q = q.eq('empresa_id', s.empresa_id);
  const { data } = await q.order('razon_social');
  return data ?? [];
}

// Aplica el filtro de ámbito a un query builder de supabase-js sobre una tabla
// que tenga columna estacionamiento_id.
export async function applyScope(query) {
  const s = getScope();
  if (s.estacionamiento_id) return query.eq('estacionamiento_id', s.estacionamiento_id);
  if (s.empresa_id) {
    const est = await scopedEstacionamientos();
    return query.in('estacionamiento_id', est.map(x => x.estacionamiento_id));
  }
  return query;
}

// Renderiza el selector Empresa → Estacionamiento en un contenedor.
// Emite 'op-scope-change' cuando el usuario cambia una de las dos.
export async function renderScopeSelector(container) {
  const s = getScope();
  const { data: emps } = await supabase.from('empresas')
    .select('empresa_id, codigo, razon_social').order('razon_social');
  container.innerHTML = `
    <div class="flex flex-wrap items-center gap-2 text-sm">
      <span class="text-white/70 hidden sm:inline">Ámbito:</span>
      <select id="scope-emp" class="bg-white/10 hover:bg-white/20 text-white rounded px-2 py-1 outline-none border border-white/20 text-xs">
        <option value="">Todas las empresas (corporativo)</option>
        ${(emps??[]).map(e => `<option value="${e.empresa_id}" ${s.empresa_id===e.empresa_id?'selected':''}>${e.razon_social}</option>`).join('')}
      </select>
      <select id="scope-est" class="bg-white/10 hover:bg-white/20 text-white rounded px-2 py-1 outline-none border border-white/20 text-xs">
        <option value="">Todos los estacionamientos</option>
      </select>
    </div>`;
  const selEmp = container.querySelector('#scope-emp');
  const selEst = container.querySelector('#scope-est');

  async function reloadEstacionamientos(preserve) {
    const empId = selEmp.value || null;
    let q = supabase.from('estacionamientos').select('estacionamiento_id, nombre, codigo, sucursal_id');
    if (empId) {
      const { data: sucs } = await supabase.from('sucursales').select('sucursal_id').eq('empresa_id', empId);
      q = q.in('sucursal_id', (sucs ?? []).map(x => x.sucursal_id));
    }
    const { data } = await q.order('nombre');
    selEst.innerHTML = `<option value="">Todos los estacionamientos</option>` +
      (data ?? []).map(x => `<option value="${x.estacionamiento_id}" ${preserve===x.estacionamiento_id?'selected':''}>${x.nombre} (${x.codigo})</option>`).join('');
  }

  await reloadEstacionamientos(s.estacionamiento_id);

  selEmp.addEventListener('change', async () => {
    setScope(selEmp.value || null, null);
    await reloadEstacionamientos(null);
  });
  selEst.addEventListener('change', () => {
    setScope(selEmp.value || null, selEst.value || null);
  });
}
