// Cliente Supabase (importado como ES module desde CDN — sin bundler).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { ENV } from './env.js';

if (!ENV.SUPABASE_ANON_KEY) {
  console.warn('[ONLYPARK] SUPABASE_ANON_KEY vacío — configúralo en /js/env.local.js o window.OP_ENV');
}

export const supabase = createClient(ENV.SUPABASE_URL, ENV.SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
});

export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

export async function getPerfil() {
  const s = await getSession();
  if (!s) return null;
  const { data, error } = await supabase.rpc('fn_perfil_actual');
  if (error) { console.error('[ONLYPARK] fn_perfil_actual:', error); return null; }
  return data;
}
