import { supabase } from '../supabase.js';

// DEV MODE: sin validacion. Solo capturamos el nombre y entramos.
// En segundo plano intentamos autenticarnos con el usuario compartido para que
// las policies RLS dejen leer/escribir datos. Si falla, el usuario entra igual.
const SHARED_EMAIL    = 'operador@onlypark.local';
const SHARED_PASSWORD = 'op-dev-2026';

export function renderLogin(root) {
  root.innerHTML = `
    <div class="flex-1 flex items-center justify-center px-4 py-12 bg-gradient-to-br from-marino via-marino-700 to-slate-900">
      <div class="w-full max-w-md">
        <div class="flex flex-col items-center mb-8">
          <div class="w-20 h-20 rounded-2xl bg-white/10 backdrop-blur flex items-center justify-center mb-3 shadow-xl ring-1 ring-white/10">
            <span class="text-white font-black text-4xl">P</span>
          </div>
          <h1 class="text-white text-3xl font-bold tracking-wide">ONLYPARK</h1>
          <p class="text-white/60 text-sm mt-1">Administracion inteligente de estacionamientos</p>
        </div>

        <div class="bg-white rounded-2xl shadow-2xl p-8">
          <div class="mb-6">
            <h2 class="text-marino text-lg font-semibold">Iniciar operacion</h2>
            <p class="text-slate-500 text-sm mt-1">Escribe tu nombre para que quede en la bitacora.</p>
          </div>

          <form id="op-form-login" class="space-y-4" autocomplete="off">
            <label class="block">
              <span class="text-sm text-slate-600 font-medium">Nombre del operador</span>
              <input
                class="op-input mt-1"
                type="text"
                name="operador"
                required
                autofocus
                minlength="2"
                maxlength="80"
                placeholder="Ej. Roberto Aguilar"
                value="${localStorage.getItem('op_actor') ?? ''}"
              />
            </label>

            <button type="submit" class="op-btn-primary w-full mt-2 flex items-center justify-center gap-2">
              <span>Entrar</span>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-5 h-5"><path d="M5 12h14M13 5l7 7-7 7"/></svg>
            </button>
          </form>

          <div class="mt-6 pt-4 border-t border-slate-100 text-center">
            <p class="text-xs text-slate-400">v0.1 - dev mode - sesion compartida</p>
          </div>
        </div>

        <p class="text-center text-white/40 text-xs mt-6">(c) RANNIX - ONLYPARK</p>
      </div>
    </div>`;

  root.querySelector('#op-form-login').addEventListener('submit', (e) => {
    e.preventDefault();
    const operador = new FormData(e.target).get('operador').trim();
    if (!operador) return;
    localStorage.setItem('op_actor', operador);
    // Intento background — no bloquea la entrada
    supabase.auth.signInWithPassword({ email: SHARED_EMAIL, password: SHARED_PASSWORD })
      .catch((err) => console.warn('[ONLYPARK] shared signin failed (dev):', err));
    window.location.hash = '/';
  });
}
