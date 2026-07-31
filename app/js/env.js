// Config del cliente. En producción, Netlify inyecta estos via `window.OP_ENV`
// desde un snippet o edge function. En desarrollo local, se lee de /js/env.local.js
// si existe (no commiteado). Nunca poner service_role aquí.
export const ENV = Object.assign(
  {
    SUPABASE_URL: 'https://ixumzgorhuhftasgrmhg.supabase.co',
    SUPABASE_ANON_KEY: '',
  },
  (typeof window !== 'undefined' && window.OP_ENV) || {}
);
