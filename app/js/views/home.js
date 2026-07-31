import { supabase, getPerfil } from '../supabase.js';

export async function renderHome(root) {
  root.innerHTML = `
    <header class="bg-marino text-white px-4 py-3 flex items-center justify-between">
      <div class="flex items-center gap-2">
        <div class="w-8 h-8 rounded-md bg-barrera flex items-center justify-center font-bold">P</div>
        <span class="font-semibold tracking-wide">ONLYPARK</span>
      </div>
      <button id="op-logout" class="text-sm underline">Salir</button>
    </header>

    <main class="flex-1 p-6 max-w-5xl mx-auto w-full">
      <h1 class="text-2xl font-bold text-marino mb-4">Panel</h1>
      <nav class="mb-4 flex gap-2">
        <a href="#/catalogos/grupos" class="op-btn-primary text-sm">Catálogos</a>
      </nav>
      <div id="op-perfil" class="op-card mb-4">Cargando perfil…</div>
      <div id="op-empresas" class="op-card mb-4">Cargando empresas visibles…</div>
      <div id="op-estacionamientos" class="op-card">Cargando estacionamientos visibles…</div>
    </main>`;

  root.querySelector('#op-logout').addEventListener('click', async () => {
    await supabase.auth.signOut();
    window.location.hash = '/login';
  });

  const perfilId = await getPerfil();
  root.querySelector('#op-perfil').innerHTML = perfilId
    ? `<div class="text-sm text-slate-500">Perfil</div><div class="font-mono text-marino">${perfilId}</div>`
    : `<div class="text-red-600">No hay perfil asociado a tu usuario en ONLYPARK.</div>`;

  const { data: empresas, error: e1 } = await supabase.from('empresas')
    .select('empresa_id, codigo, razon_social').order('razon_social');
  root.querySelector('#op-empresas').innerHTML = e1
    ? `<div class="text-red-600">Error: ${e1.message}</div>`
    : `<div class="text-sm text-slate-500 mb-1">Empresas visibles (${empresas.length})</div>
       <ul class="divide-y">${empresas.map(x => `<li class="py-1">${x.codigo} — ${x.razon_social}</li>`).join('')}</ul>`;

  const { data: est, error: e2 } = await supabase.from('estacionamientos')
    .select('estacionamiento_id, codigo, nombre, capacidad_total').order('nombre');
  root.querySelector('#op-estacionamientos').innerHTML = e2
    ? `<div class="text-red-600">Error: ${e2.message}</div>`
    : `<div class="text-sm text-slate-500 mb-1">Estacionamientos visibles (${est.length})</div>
       <ul class="divide-y">${est.map(x => `<li class="py-1 flex justify-between"><span>${x.codigo} — ${x.nombre}</span><span class="text-slate-400 text-sm">${x.capacidad_total ?? '-'} cajones</span></li>`).join('')}</ul>`;
}
