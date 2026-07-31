// Config del cliente. El anon key es PÚBLICO por diseño (Supabase lo publica
// para uso en el navegador; queda protegido por Row Level Security).
// El service_role NUNCA va aquí — solo en env vars de Netlify o Edge Functions.
//
// Para overridear en dev/staging, crea /js/env.local.js (gitignored) con:
//   window.OP_ENV = { SUPABASE_URL: '...', SUPABASE_ANON_KEY: '...' };
// y cárgalo antes de este módulo. Si window.OP_ENV existe, prevalece.
const DEFAULTS = {
  SUPABASE_URL: 'https://ixumzgorhuhftasgrmhg.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml4dW16Z29yaHVoZnRhc2dybWhnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU0NjY2NDQsImV4cCI6MjEwMTA0MjY0NH0.Zmz8nqDqanNdjLN5UrG0zPlc6THDWHeZkddS7ztO1GA',
};

export const ENV = Object.assign(
  {},
  DEFAULTS,
  (typeof window !== 'undefined' && window.OP_ENV) || {}
);
