import { supabase } from '../supabase.js';
import { log } from './log.js';

// ---------- Grupos ----------
export async function listGrupos() {
  return supabase.from('grupos_empresariales')
    .select('grupo_id, codigo, nombre, activo, created_at')
    .order('nombre');
}

export async function upsertGrupo(row) {
  const previo = row.grupo_id
    ? (await supabase.from('grupos_empresariales').select('*').eq('grupo_id', row.grupo_id).single()).data
    : null;
  const res = await supabase.from('grupos_empresariales').upsert(row).select().single();
  if (!res.error) {
    await log('seguridad', row.grupo_id ? 'grupo_update' : 'grupo_insert', null,
      { previo, nuevo: res.data }, `grupo ${res.data.codigo}`);
  }
  return res;
}

// ---------- Empresas ----------
export async function listEmpresas() {
  return supabase.from('empresas')
    .select('empresa_id, grupo_id, codigo, razon_social, nombre_comercial, rfc, activo, grupos_empresariales(nombre)')
    .order('razon_social');
}

export async function upsertEmpresa(row) {
  const previo = row.empresa_id
    ? (await supabase.from('empresas').select('*').eq('empresa_id', row.empresa_id).single()).data
    : null;
  const res = await supabase.from('empresas').upsert(row).select().single();
  if (!res.error) {
    await log('seguridad', row.empresa_id ? 'empresa_update' : 'empresa_insert', null,
      { previo, nuevo: res.data }, `empresa ${res.data.codigo}`);
  }
  return res;
}

// ---------- Sucursales ----------
export async function listSucursales() {
  return supabase.from('sucursales')
    .select('sucursal_id, empresa_id, codigo, nombre, direccion, telefono, activo, empresas(razon_social)')
    .order('nombre');
}

export async function upsertSucursal(row) {
  const previo = row.sucursal_id
    ? (await supabase.from('sucursales').select('*').eq('sucursal_id', row.sucursal_id).single()).data
    : null;
  const res = await supabase.from('sucursales').upsert(row).select().single();
  if (!res.error) {
    await log('seguridad', row.sucursal_id ? 'sucursal_update' : 'sucursal_insert', null,
      { previo, nuevo: res.data }, `sucursal ${res.data.codigo}`);
  }
  return res;
}

// ---------- Estacionamientos ----------
export async function listEstacionamientos() {
  return supabase.from('estacionamientos')
    .select('estacionamiento_id, sucursal_id, codigo, nombre, capacidad_total, activo, sucursales(nombre, empresas(razon_social))')
    .order('nombre');
}

export async function upsertEstacionamiento(row) {
  const previo = row.estacionamiento_id
    ? (await supabase.from('estacionamientos').select('*').eq('estacionamiento_id', row.estacionamiento_id).single()).data
    : null;
  const res = await supabase.from('estacionamientos').upsert(row).select().single();
  if (!res.error) {
    await log('seguridad', row.estacionamiento_id ? 'estac_update' : 'estac_insert',
      res.data.estacionamiento_id, { previo, nuevo: res.data }, `estac ${res.data.codigo}`);
  }
  return res;
}

// ---------- FKs para dropdowns ----------
export async function optionsGrupos() {
  const { data } = await supabase.from('grupos_empresariales')
    .select('grupo_id, nombre').eq('activo', true).order('nombre');
  return data ?? [];
}
export async function optionsEmpresas(grupoId) {
  let q = supabase.from('empresas').select('empresa_id, razon_social').eq('activo', true);
  if (grupoId) q = q.eq('grupo_id', grupoId);
  const { data } = await q.order('razon_social');
  return data ?? [];
}
export async function optionsSucursales(empresaId) {
  let q = supabase.from('sucursales').select('sucursal_id, nombre').eq('activo', true);
  if (empresaId) q = q.eq('empresa_id', empresaId);
  const { data } = await q.order('nombre');
  return data ?? [];
}
