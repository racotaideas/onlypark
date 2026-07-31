import { supabase } from '../supabase.js';

// Nombre real del operador que escribió en la pantalla de login.
// Se guarda en localStorage y se incluye en el payload JSONB de log_evento
// para dejar registro real de quién hizo qué (dado que la sesión Supabase
// es compartida en modo dev).
export function currentActor() {
  return (typeof localStorage !== 'undefined' && localStorage.getItem('op_actor')) || 'desconocido';
}

// Envoltorio de fn_log(p_tipo_codigo, p_subtipo, p_estacionamiento_id, p_payload, p_descripcion, p_sesion_id).
// Injecta { actor: <nombre_operador> } al payload para audit.
export async function log(tipoCodigo, subtipo, estacionamientoId, payload, descripcion) {
  const enriched = Object.assign(
    { actor: currentActor(), at: new Date().toISOString() },
    payload || {}
  );
  const { error } = await supabase.rpc('fn_log', {
    p_tipo_codigo:       tipoCodigo,
    p_subtipo:           subtipo,
    p_estacionamiento_id: estacionamientoId,
    p_payload:           enriched,
    p_descripcion:       descripcion ?? null,
    p_sesion_id:         null,
  });
  if (error) console.warn('[ONLYPARK] fn_log error:', error);
}
