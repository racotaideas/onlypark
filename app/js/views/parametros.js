import { supabase } from '../supabase.js';
import { renderScopeSelector, scopedEstacionamientos, scopeLabel } from '../api/scope.js';
import { bindLogout } from './reportes.js';
import { currentActor, log } from '../api/log.js';

// ============================================================================
// Módulo Parámetros — matriz editable de tarifas + config por estacionamiento
// Respeta el ámbito (Grupo / Empresa / Estac) seleccionado en el panel.
// ============================================================================
export async function renderParametros(root) {
  root.innerHTML = `
    <header class="bg-marino text-white px-4 py-3 shadow-md">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-3">
          <a href="#/" class="text-2xl">⚙️</a>
          <div class="leading-tight">
            <div class="font-semibold tracking-wide">ONLYPARK / Parámetros</div>
            <div id="scope-label" class="text-xs text-white/60">Cargando ámbito…</div>
          </div>
        </div>
        <div class="flex items-center gap-4">
          <a href="#/" class="text-sm underline text-white/80">← Panel</a>
          <button id="op-logout" class="bg-white/10 hover:bg-white/20 text-sm rounded-md px-3 py-1.5 transition">Salir</button>
        </div>
      </div>
      <div id="scope-selector"></div>
    </header>

    <main class="flex-1 p-6 max-w-7xl mx-auto w-full">
      <div class="mb-4 flex items-baseline justify-between">
        <h1 class="text-2xl font-bold text-marino">Parámetros por estacionamiento</h1>
        <div id="msg" class="text-sm min-h-[1.5rem]"></div>
      </div>
      <p class="text-slate-500 text-sm mb-4">
        Cada estacionamiento tiene sus propias tarifas y configuración. Los cambios
        se aplican inmediatamente y quedan en bitácora.
      </p>
      <div id="cards" class="space-y-4">Cargando…</div>
    </main>`;

  bindLogout(root);
  await renderScopeSelector(root.querySelector('#scope-selector'));
  root.querySelector('#scope-label').textContent = 'Ámbito: ' + await scopeLabel();

  const cont = root.querySelector('#cards');
  await refresh(cont, root.querySelector('#msg'));

  window.addEventListener('op-scope-change', async () => {
    root.querySelector('#scope-label').textContent = 'Ámbito: ' + await scopeLabel();
    await refresh(cont, root.querySelector('#msg'));
  });
}

async function refresh(cont, msgEl) {
  msgEl.textContent = '';
  cont.innerHTML = '<div class="op-card text-slate-400">Cargando parámetros…</div>';

  const ests = await scopedEstacionamientos();
  if (!ests.length) { cont.innerHTML = '<div class="op-card text-slate-400">No hay estacionamientos en el ámbito seleccionado.</div>'; return; }

  const estIds = ests.map(x => x.estacionamiento_id);
  const [politicas, reglas, cfgs, tipoTar] = await Promise.all([
    supabase.from('politicas_tarifarias').select('politica_id, estacionamiento_id, nombre, activo').in('estacionamiento_id', estIds).eq('activo', true),
    supabase.from('reglas_tarifarias').select('regla_id, politica_id, tipo_tarifa_id, monto, fraccion_min, tolerancia_min, prioridad, activa, parametros').eq('activa', true),
    supabase.from('cfg_estacionamiento').select('*').in('estacionamiento_id', estIds),
    supabase.from('cat_tipo_tarifa').select('tipo_tarifa_id, codigo, nombre').eq('activo', true)
  ]);

  const polByEst = Object.fromEntries((politicas.data ?? []).map(p => [p.estacionamiento_id, p]));
  const cfgByEst = Object.fromEntries((cfgs.data ?? []).map(c => [c.estacionamiento_id, c]));
  const tipos = tipoTar.data ?? [];
  const tipoById = Object.fromEntries(tipos.map(t => [t.tipo_tarifa_id, t]));
  const reglasByPol = {};
  (reglas.data ?? []).forEach(r => { (reglasByPol[r.politica_id] = reglasByPol[r.politica_id] || []).push(r); });

  cont.innerHTML = ests.map(e => {
    const p = polByEst[e.estacionamiento_id];
    const c = cfgByEst[e.estacionamiento_id] || {};
    const rs = p ? (reglasByPol[p.politica_id] ?? []) : [];
    return cardEstac(e, p, rs, c, tipos, tipoById);
  }).join('');

  cont.querySelectorAll('form[data-estac]').forEach(f => {
    f.addEventListener('submit', async ev => {
      ev.preventDefault();
      await guardar(f, msgEl);
    });
  });
}

function cardEstac(e, p, reglas, cfg, tipos, tipoById) {
  const reglasStr = reglas.map(r => {
    const t = tipoById[r.tipo_tarifa_id] || { codigo:'?', nombre:'?' };
    return `<tr class="border-t">
      <td class="px-2 py-1.5 capitalize">${t.nombre}</td>
      <td class="px-2 py-1.5"><input name="monto_${r.regla_id}" type="number" step="0.01" value="${r.monto ?? ''}" class="op-input w-24 text-right" /></td>
      <td class="px-2 py-1.5"><input name="frac_${r.regla_id}" type="number" step="1" value="${r.fraccion_min ?? ''}" placeholder="—" class="op-input w-20 text-right" /></td>
      <td class="px-2 py-1.5"><input name="tol_${r.regla_id}" type="number" step="1" value="${r.tolerancia_min ?? ''}" placeholder="—" class="op-input w-20 text-right" /></td>
      <td class="px-2 py-1.5 text-slate-400 text-xs font-mono">${t.codigo}</td>
    </tr>`;
  }).join('');

  return `
    <form data-estac="${e.estacionamiento_id}" data-politica="${p?.politica_id ?? ''}" class="op-card">
      <div class="flex justify-between items-start mb-3">
        <div>
          <div class="text-lg font-semibold text-marino">${e.nombre}</div>
          <div class="text-xs text-slate-500 mt-0.5">
            <span class="font-mono">${e.codigo}</span> · ${e.capacidad_total ?? 0} cajones
            ${p ? `· política: ${p.nombre}` : '· <span class="text-red-600">sin política</span>'}
          </div>
        </div>
        <button type="submit" class="op-btn-primary text-sm">Guardar</button>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div class="lg:col-span-2">
          <div class="text-sm font-semibold text-marino mb-1">Tarifas</div>
          ${reglas.length === 0 ? '<div class="text-slate-400 text-sm">Sin reglas configuradas</div>' : `
          <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="text-xs text-slate-500 text-left">
              <tr><th class="px-2 py-1">Concepto</th><th class="px-2 py-1 text-right">Monto</th><th class="px-2 py-1 text-right">Fracción (min)</th><th class="px-2 py-1 text-right">Tolerancia (min)</th><th class="px-2 py-1">Código</th></tr>
            </thead>
            <tbody>${reglasStr}</tbody>
          </table>
          </div>`}
        </div>

        <div>
          <div class="text-sm font-semibold text-marino mb-1">Configuración</div>
          <div class="space-y-1.5 text-sm">
            ${cfgCheckbox('cfg_lpr_habilitado', 'LPR habilitado', cfg.lpr_habilitado)}
            ${cfgCheckbox('cfg_pagos_qr_habilitado', 'Cobro por QR', cfg.pagos_qr_habilitado)}
            ${cfgCheckbox('cfg_pagos_link_habilitado', 'Cobro por link', cfg.pagos_link_habilitado)}
            ${cfgCheckbox('cfg_onlywallet_habilitado', 'Monedero ONLYWALLET', cfg.onlywallet_habilitado)}
            ${cfgCheckbox('cfg_promociones_habilitado', 'Promociones', cfg.promociones_habilitado)}
            ${cfgCheckbox('cfg_offline_habilitado', 'Modo offline', cfg.offline_habilitado)}
            ${cfgCheckbox('cfg_usa_pin_operativo', 'PIN operativo', cfg.usa_pin_operativo)}
          </div>
          <div class="mt-3 grid grid-cols-2 gap-2 text-sm">
            <label class="block">
              <span class="text-xs text-slate-500">Tolerancia salida (min)</span>
              <input name="cfg_minutos_tolerancia_salida" type="number" value="${cfg.minutos_tolerancia_salida ?? 15}" class="op-input mt-0.5" />
            </label>
            <label class="block">
              <span class="text-xs text-slate-500">Tolerancia (min)</span>
              <input name="cfg_tolerancia_min" type="number" value="${cfg.tolerancia_min ?? 15}" class="op-input mt-0.5" />
            </label>
          </div>
        </div>
      </div>
    </form>`;
}

function cfgCheckbox(name, label, checked) {
  return `<label class="flex items-center gap-2 cursor-pointer">
    <input type="checkbox" name="${name}" ${checked ? 'checked' : ''} class="rounded border-slate-300" />
    <span>${label}</span>
  </label>`;
}

async function guardar(form, msgEl) {
  const estId = form.dataset.estac;
  const polId = form.dataset.politica || null;
  const fd = new FormData(form);

  // ── 1) Update reglas ──
  const reglasPorId = {};
  for (const [k, v] of fd.entries()) {
    const m = k.match(/^(monto|frac|tol)_([0-9a-f-]{36})$/);
    if (!m) continue;
    const campo = m[1]; const id = m[2];
    reglasPorId[id] = reglasPorId[id] || {};
    if (v === '' || v === null) reglasPorId[id][{ monto:'monto', frac:'fraccion_min', tol:'tolerancia_min' }[campo]] = null;
    else reglasPorId[id][{ monto:'monto', frac:'fraccion_min', tol:'tolerancia_min' }[campo]] = Number(v);
  }

  const errors = [];
  for (const [id, patch] of Object.entries(reglasPorId)) {
    const { error } = await supabase.from('reglas_tarifarias').update(patch).eq('regla_id', id);
    if (error) errors.push('regla ' + id.slice(0,8) + ': ' + error.message);
  }

  // ── 2) Update cfg_estacionamiento ──
  const cfgPatch = {
    lpr_habilitado:            fd.get('cfg_lpr_habilitado')            === 'on',
    pagos_qr_habilitado:       fd.get('cfg_pagos_qr_habilitado')       === 'on',
    pagos_link_habilitado:     fd.get('cfg_pagos_link_habilitado')     === 'on',
    onlywallet_habilitado:     fd.get('cfg_onlywallet_habilitado')     === 'on',
    promociones_habilitado:    fd.get('cfg_promociones_habilitado')    === 'on',
    offline_habilitado:        fd.get('cfg_offline_habilitado')        === 'on',
    usa_pin_operativo:         fd.get('cfg_usa_pin_operativo')         === 'on',
    minutos_tolerancia_salida: Number(fd.get('cfg_minutos_tolerancia_salida')) || 15,
    tolerancia_min:            Number(fd.get('cfg_tolerancia_min')) || 15
  };
  // Upsert por estacionamiento_id (crea si no existe)
  const { error: cfgErr } = await supabase.from('cfg_estacionamiento')
    .upsert({ estacionamiento_id: estId, ...cfgPatch }, { onConflict: 'estacionamiento_id' });
  if (cfgErr) errors.push('cfg: ' + cfgErr.message);

  // ── 3) Audit ──
  await log('seguridad', 'cambio_parametros', estId,
    { actor: currentActor(), reglas: Object.keys(reglasPorId).length, cfg: cfgPatch },
    `Parámetros actualizados en estacionamiento ${estId.slice(0,8)}`);

  if (errors.length) {
    msgEl.className = 'text-sm text-red-600';
    msgEl.textContent = 'Errores: ' + errors.slice(0,3).join(' · ');
  } else {
    msgEl.className = 'text-sm text-barrera-700';
    msgEl.textContent = '✓ Guardado';
    setTimeout(() => { msgEl.textContent = ''; }, 3000);
  }
}
