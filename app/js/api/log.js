import { supabase } from '../supabase.js';

// Wrapper del fn_log(p_tipo_codigo, p_subtipo, p_estacionamiento_id, p_payload, p_descripcion, p_sesion_id).
// El tipo debe existir en cat_tipo_bitacora. Si no está habilitado el tipo o el estacionamiento
// no lo tiene configurado, la función retorna sin insertar (por diseño).
export async function log(tipoCodigo, subtipo, estacionamientoId, payload, descripcion) {
  const { error } = await supabase.rpc('fn_log', {
    p_tipo_codigo:       tipoCodigo,
    p_subtipo:           subtipo,
    p_estacionamiento_id: estacionamientoId,
    p_payload:           payload ?? null,
    p_descripcion:       descripcion ?? null,
    p_sesion_id:         null,
  });
  if (error) console.warn('[ONLYPARK] fn_log error:', error);
}
