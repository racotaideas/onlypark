import { supabase, getPerfil } from '../supabase.js';
import { currentActor } from '../api/log.js';

export async function renderHome(root) {
  const actor = currentActor();
  root.innerHTML = `
    <header class="bg-marino text-white px-4 py-3 flex items-center justify-between shadow-md">
      <div class="flex items-center gap-3">
        <div class="w-9 h-9 rounded-lg bg-barrera flex items-center justify-center font-bold shadow-md">P</div>
        <div class="leading-tight">
          <div class="font-semibold tracking-wide">ONLYPARK</div>
          <div class="text-xs text-white/60">Panel principal</div>
        </div>
      </div>
      <div class="flex items-center gap-4">
        <div class="text-right leading-tight">
          <div class="text-xs text-white/60">Operando como</div>
          <div class="text-sm font-medium">${actor}</div>
        </div>
        <button id="op-logout" class="bg-white/10 hover:bg-white/20 text-sm rounded-md px-3 py-1.5 transition">Salir</button>
      </div>
    </header>

    <main class="flex-1 p-6 max-w-6xl mx-auto w-full">
      <div class="mb-6 flex items-end justify-between">
        <div>
          <h1 class="text-2xl font-bold text-marino">Bienvenido, ${actor}</h1>
          <p class="text-slate-500 text-sm">Elige un módulo para comenzar.</p>
        </div>
        <nav class="flex gap-2">
          <a href="#/catalogos/grupos" class="op-btn-primary text-sm">Catálogos</a>
        </nav>
      </div>

      <!-- KPI cards -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Empresas</div>
          <div id="kpi-empresas" class="text-3xl font-bold text-marino mt-1">—</div>
        </div>
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Estacionamientos</div>
          <div id="kpi-est" class="text-3xl font-bold text-marino mt-1">—</div>
        </div>
        <div class="op-card">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Cajones totales</div>
          <div id="kpi-cajones" class="text-3xl font-bold text-barrera mt-1">—</div>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div id="op-empresas" class="op-card">Cargando empresas visibles…</div>
        <div id="op-estacionamientos" class="op-card">Cargando estacionamientos visibles…</div>
      </div>

      <div id="op-perfil-debug" class="mt-6 text-xs text-slate-400 text-center"></div>
    </main>`;

  root.querySelector('#op-logout').addEventListener('click', async () => {
    localStorage.removeItem('op_actor');
    await supabase.auth.signOut();
    window.location.hash = '/login';
  });

  const perfilId = await getPerfil();
  root.querySelector('#op-perfil-debug').textContent =
    perfilId ? `Sesión compartida · perfil_id ${perfilId.slice(0,8)}…` : 'Sin perfil (sesión inválida)';

  const { data: empresas, error: e1 } = await supabase.from('empresas')
    .select('empresa_id, codigo, razon_social').order('razon_social');
  if (e1) {
    root.querySelector('#op-empresas').innerHTML = `<div class="text-red-600">Error: ${e1.message}</div>`;
  } else {
    root.querySelector('#kpi-empresas').textContent = empresas.length;
    root.querySelector('#op-empresas').innerHTML = `
      <div class="flex justify-between items-baseline mb-2">
        <div class="text-sm font-semibold text-marino">Empresas visibles</div>
        <div class="text-xs text-slate-400">${empresas.length}</div>
      </div>
      <ul class="divide-y">${empresas.map(x => `
        <li class="py-1.5 flex justify-between text-sm"><span>${x.razon_social}</span><span class="text-slate-400 font-mono text-xs">${x.codigo}</span></li>`).join('')}</ul>`;
  }

  const { data: est, error: e2 } = await supabase.from('estacionamientos')
    .select('estacionamiento_id, codigo, nombre, capacidad_total').order('nombre');
  if (e2) {
    root.querySelector('#op-estacionamientos').innerHTML = `<div class="text-red-600">Error: ${e2.message}</div>`;
  } else {
    const totalCajones = est.reduce((a,x)=>a+(x.capacidad_total||0),0);
    root.querySelector('#kpi-est').textContent = est.length;
    root.querySelector('#kpi-cajones').textContent = totalCajones.toLocaleString();
    root.querySelector('#op-estacionamientos').innerHTML = `
      <div class="flex justify-between items-baseline mb-2">
        <div class="text-sm font-semibold text-marino">Estacionamientos visibles</div>
        <div class="text-xs text-slate-400">${est.length}</div>
      </div>
      <ul class="divide-y">${est.map(x => `
        <li class="py-1.5 flex justify-between text-sm">
          <span>${x.nombre} <span class="text-slate-400 font-mono text-xs">${x.codigo}</span></span>
          <span class="text-slate-500">${(x.capacidad_total ?? 0).toLocaleString()} cajones</span>
        </li>`).join('')}</ul>`;
  }
}
