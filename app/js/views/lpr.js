import { supabase } from '../supabase.js';
import { renderScopeSelector, scopedEstacionamientos, scopeLabel } from '../api/scope.js';
import { bindLogout } from './reportes.js';

// Simulador LPR: entrada + salida.
// En producción: la lectura de placa la hace un servicio residente (Python + OpenCV
// o proveedor tipo Genetec/Milestone). Aquí lo simulamos con inputs para probar
// el flujo end-to-end sin cámaras físicas.
export async function renderLpr(root) {
  root.innerHTML = shell();
  bindLogout(root);
  await renderScopeSelector(root.querySelector('#scope-selector'));
  root.querySelector('#scope-label').textContent = await scopeLabel();

  await refresh(root);
  window.addEventListener('op-scope-change', async () => {
    root.querySelector('#scope-label').textContent = await scopeLabel();
    await refresh(root);
  });

  root.querySelector('#f-entrada').addEventListener('submit', async e => {
    e.preventDefault();
    const fd = new FormData(e.target);
    const placa = String(fd.get('placa')).trim();
    const est   = fd.get('estacionamiento_id');
    if (!placa || !est) return;
    const { data, error } = await supabase.rpc('fn_registrar_entrada_lpr', {
      p_placa_numero: placa,
      p_estacionamiento: est,
      p_tipo_codigo: 'normal'
    });
    const msg = root.querySelector('#msg-ent');
    if (error) { msg.innerHTML = `<span class="text-red-600">${error.message}</span>`; return; }
    const t = Array.isArray(data) ? data[0] : data;
    mostrarBoleto(root, t, est);
    e.target.reset();
    setTimeout(() => refresh(root), 800);
  });

  root.querySelector('#f-salida').addEventListener('submit', async e => {
    e.preventDefault();
    const fd = new FormData(e.target);
    const placa = String(fd.get('placa')).trim();
    const est   = fd.get('estacionamiento_id');
    const { data, error } = await supabase.rpc('fn_verificar_salida_lpr', {
      p_placa_numero: placa,
      p_estacionamiento: est
    });
    const msg = root.querySelector('#msg-sal');
    if (error) { msg.innerHTML = `<span class="text-red-600">${error.message}</span>`; return; }
    const r = Array.isArray(data) ? data[0] : data;
    if (!r) { msg.innerHTML = '<span class="text-slate-500">Sin respuesta</span>'; return; }
    if (r.resultado === 'autorizado') {
      msg.innerHTML = `<div class="p-4 rounded bg-barrera/10 border border-barrera/30 text-center">
        <div class="text-4xl mb-1">🚦</div>
        <div class="text-xl font-bold text-barrera-700">PLUMA AUTORIZADA</div>
        <div class="text-sm text-slate-600 mt-1">Folio ${r.folio} · ${r.minutos} min · $${Number(r.importe).toLocaleString()}</div>
        <div class="text-xs text-slate-500 mt-2">Salida registrada. Cliente puede pasar.</div>
      </div>`;
    } else if (r.resultado === 'requiere_pago') {
      const payUrl = location.origin + '/pay.html?token=' + r.link_token;
      msg.innerHTML = `<div class="p-4 rounded bg-yellow-50 border border-yellow-300 text-center">
        <div class="text-4xl mb-1">🛑</div>
        <div class="text-xl font-bold text-yellow-800">PAGO PENDIENTE</div>
        <div class="text-sm mt-1">Folio ${r.folio} · ${r.minutos} min · <span class="font-bold text-red-600">$${Number(r.importe).toLocaleString()}</span></div>
        <a href="${payUrl}" target="_blank" class="inline-block mt-3 bg-marino text-white text-sm rounded px-4 py-2">
          Abrir link de pago →
        </a>
        <div class="text-xs text-slate-500 mt-2 break-all">${payUrl}</div>
      </div>`;
    } else {
      msg.innerHTML = `<div class="p-4 rounded bg-red-50 border border-red-300 text-center">
        <div class="text-4xl mb-1">❌</div>
        <div class="text-xl font-bold text-red-700">PLACA NO ENCONTRADA</div>
        <div class="text-sm text-slate-600 mt-1">No hay sesión abierta con esa placa en la plaza seleccionada.</div>
      </div>`;
    }
    e.target.reset();
    setTimeout(() => refresh(root), 800);
  });
}

function mostrarBoleto(root, t, estId) {
  const payUrl = location.origin + '/pay.html?token=' + t.link_token;
  const dlg = document.createElement('div');
  dlg.className = 'fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4';
  dlg.innerHTML = `
    <div class="bg-white rounded-2xl shadow-2xl max-w-sm w-full overflow-hidden">
      <div class="bg-marino text-white text-center py-3">
        <div class="text-xs uppercase tracking-wider opacity-80">Boleto de entrada</div>
        <div class="font-mono text-2xl font-bold mt-1">${t.folio_entrada}</div>
      </div>
      <div class="p-6 text-center">
        <div class="text-xs text-slate-500 uppercase">Placa</div>
        <div class="text-3xl font-bold text-marino tracking-widest">${t.placa_numero}</div>
        <div class="text-xs text-slate-500 mt-3">${new Date(t.entrada_at).toLocaleString()}</div>

        <div class="my-4 flex justify-center">
          <div id="qr-box" class="p-2 bg-white border border-slate-200 rounded"></div>
        </div>
        <div class="text-[10px] text-slate-500 break-all px-2">${payUrl}</div>

        <p class="text-xs text-slate-500 mt-4">Escanea el código para pagar desde tu celular antes de salir.</p>
        <button data-close class="mt-4 op-btn-primary w-full">Cerrar</button>
      </div>
    </div>`;
  document.body.appendChild(dlg);
  dlg.querySelector('[data-close]').addEventListener('click', () => dlg.remove());
  dlg.addEventListener('click', (e) => { if (e.target === dlg) dlg.remove(); });

  // Cargar QR (via CDN lib) y renderizarlo
  import('https://esm.sh/qrcode@1.5.4').then(({ default: QRCode }) => {
    QRCode.toCanvas(payUrl, { width: 180, margin: 1 }, (err, canvas) => {
      if (!err) dlg.querySelector('#qr-box').appendChild(canvas);
      else dlg.querySelector('#qr-box').innerHTML = `<a href="${payUrl}" target="_blank" class="text-marino underline text-xs">Abrir link</a>`;
    });
  }).catch(() => {
    dlg.querySelector('#qr-box').innerHTML = `<a href="${payUrl}" target="_blank" class="text-marino underline text-xs">Abrir link (sin QR)</a>`;
  });
}

async function refresh(root) {
  const ests = await scopedEstacionamientos();
  const selEnt = root.querySelector('#f-entrada select[name="estacionamiento_id"]');
  const selSal = root.querySelector('#f-salida  select[name="estacionamiento_id"]');
  const opts = '<option value="">— elegir plaza —</option>' +
    ests.map(e => `<option value="${e.estacionamiento_id}">${e.nombre} · ${e.codigo}</option>`).join('');
  selEnt.innerHTML = opts;
  selSal.innerHTML = opts;

  // Últimas 10 entradas de todas las plazas del ámbito
  const estIds = ests.length ? ests.map(x=>x.estacionamiento_id) : ['00000000-0000-0000-0000-000000000000'];
  const { data: recientes } = await supabase.from('sesiones')
    .select('sesion_id, folio_entrada, entrada_at, salida_at, importe_total, pagado_at, link_token, placa_id, estacionamiento_id, placas(numero), estacionamientos(nombre)')
    .in('estacionamiento_id', estIds)
    .not('link_token', 'is', null)
    .order('entrada_at', { ascending:false }).limit(15);
  const tbody = root.querySelector('#tbody-lpr');
  tbody.innerHTML = (recientes ?? []).map(r => {
    const estatus = r.salida_at ? 'salida' : (r.pagado_at ? 'pagado' : 'dentro');
    const badge = { dentro: 'bg-yellow-100 text-yellow-800', pagado: 'bg-barrera/10 text-barrera-700', salida: 'bg-slate-200 text-slate-600' }[estatus];
    return `<tr class="border-t hover:bg-slate-50">
      <td class="px-2 py-1.5 font-mono text-xs">${r.folio_entrada}</td>
      <td class="px-2 py-1.5 font-bold tracking-widest text-marino">${r.placas?.numero ?? '—'}</td>
      <td class="px-2 py-1.5 text-xs">${r.estacionamientos?.nombre ?? '—'}</td>
      <td class="px-2 py-1.5 text-xs">${new Date(r.entrada_at).toLocaleTimeString()}</td>
      <td class="px-2 py-1.5"><span class="inline-block px-2 py-0.5 rounded text-xs ${badge}">${estatus}</span></td>
      <td class="px-2 py-1.5 text-right">${r.importe_total ? '$'+r.importe_total : '—'}</td>
      <td class="px-2 py-1.5 text-right"><a href="/pay.html?token=${r.link_token}" target="_blank" class="text-marino underline text-xs">link</a></td>
    </tr>`;
  }).join('') || '<tr><td colspan="7" class="text-center text-slate-400 py-3">Sin entradas recientes</td></tr>';
}

function shell() {
  return `<header class="bg-marino text-white px-4 py-3 shadow-md">
    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center gap-3">
        <a href="#/" class="text-2xl">📸</a>
        <div class="leading-tight">
          <div class="font-semibold tracking-wide">ONLYPARK / LPR + Pago autoservicio</div>
          <div id="scope-label" class="text-xs text-white/60">…</div>
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
    <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">

      <div class="op-card">
        <div class="flex items-center gap-2 mb-3">
          <span class="text-2xl">📥</span>
          <h2 class="text-lg font-semibold text-marino">Cámara de ENTRADA</h2>
        </div>
        <p class="text-xs text-slate-500 mb-3">Simula la lectura de placa entrante. Al enviar, se genera el ticket + link de pago con QR.</p>
        <form id="f-entrada" class="space-y-2">
          <select name="estacionamiento_id" class="op-input" required></select>
          <input name="placa" placeholder="Placa detectada (ej. ABC-1234)" class="op-input text-center text-lg font-mono uppercase tracking-widest" required maxlength="12">
          <button type="submit" class="op-btn-primary w-full">📷 Cámara leyó · Registrar entrada</button>
        </form>
        <p id="msg-ent" class="text-sm mt-3"></p>
      </div>

      <div class="op-card">
        <div class="flex items-center gap-2 mb-3">
          <span class="text-2xl">📤</span>
          <h2 class="text-lg font-semibold text-marino">Cámara de SALIDA</h2>
        </div>
        <p class="text-xs text-slate-500 mb-3">Simula la lectura de placa saliente. Si está pagada, autoriza la pluma. Si no, muestra el link de pago.</p>
        <form id="f-salida" class="space-y-2">
          <select name="estacionamiento_id" class="op-input" required></select>
          <input name="placa" placeholder="Placa detectada" class="op-input text-center text-lg font-mono uppercase tracking-widest" required maxlength="12">
          <button type="submit" class="op-btn-primary w-full">📷 Cámara leyó · Verificar salida</button>
        </form>
        <p id="msg-sal" class="text-sm mt-3"></p>
      </div>
    </div>

    <div class="op-card">
      <div class="text-sm font-semibold text-marino mb-2">Últimas entradas LPR del ámbito</div>
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead><tr class="text-slate-500 text-left">
            <th class="px-2 py-2">Folio</th><th class="px-2 py-2">Placa</th><th class="px-2 py-2">Plaza</th>
            <th class="px-2 py-2">Entrada</th><th class="px-2 py-2">Estatus</th>
            <th class="px-2 py-2 text-right">Importe</th><th></th>
          </tr></thead>
          <tbody id="tbody-lpr"><tr><td colspan="7" class="text-center text-slate-400 py-3">…</td></tr></tbody>
        </table>
      </div>
    </div>
  </main>`;
}
