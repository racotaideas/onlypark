import { supabase } from '../supabase.js';

export function renderLogin(root) {
  root.innerHTML = `
    <div class="flex-1 flex items-center justify-center px-4 py-12 bg-gradient-to-br from-marino to-marino-700">
      <div class="op-card w-full max-w-md">
        <div class="flex flex-col items-center mb-6">
          <div class="w-14 h-14 rounded-xl bg-marino flex items-center justify-center text-white font-bold text-2xl">P</div>
          <h1 class="mt-3 text-xl font-bold text-marino">ONLYPARK</h1>
          <p class="text-sm text-slate-500">Iniciar sesión</p>
        </div>

        <form id="op-form-login" class="space-y-3">
          <label class="block">
            <span class="text-sm text-slate-600">Correo</span>
            <input class="op-input mt-1" type="email" name="email" required autocomplete="username" />
          </label>
          <label class="block">
            <span class="text-sm text-slate-600">Contraseña</span>
            <input class="op-input mt-1" type="password" name="password" required autocomplete="current-password" />
          </label>
          <button type="submit" class="op-btn-primary w-full mt-2">Entrar</button>
        </form>

        <div class="flex items-center gap-2 my-4 text-slate-400 text-xs">
          <div class="flex-1 h-px bg-slate-200"></div><span>o</span><div class="flex-1 h-px bg-slate-200"></div>
        </div>

        <button id="op-btn-google" class="op-btn-accent w-full">Continuar con Google</button>

        <p id="op-msg" class="text-sm text-red-600 mt-3 min-h-[1.25rem]"></p>
      </div>
    </div>`;

  const msg = root.querySelector('#op-msg');

  root.querySelector('#op-form-login').addEventListener('submit', async (e) => {
    e.preventDefault();
    msg.textContent = '';
    const fd = new FormData(e.target);
    const { error } = await supabase.auth.signInWithPassword({
      email: fd.get('email'), password: fd.get('password'),
    });
    if (error) msg.textContent = error.message;
  });

  root.querySelector('#op-btn-google').addEventListener('click', async () => {
    msg.textContent = '';
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin + '/#/' },
    });
    if (error) msg.textContent = error.message;
  });
}
