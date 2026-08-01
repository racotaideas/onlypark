import { supabase } from '../supabase.js';
import { bindLogout } from './reportes.js';
import { currentActor, log } from '../api/log.js';
import { getScope } from '../api/scope.js';

// Módulo Cámara: captura foto desde la cámara del dispositivo, la muestra en un
// canvas, permite reintentar o guardarla en la bitácora (log_evento.payload).
// Diseñado mobile-first — botones grandes tipo app nativa.
export async function renderCamara(root) {
  root.innerHTML = `
    <header class="bg-marino text-white px-4 py-3 flex items-center justify-between shadow-md">
      <div class="flex items-center gap-3">
        <a href="#/" class="text-2xl">📸</a>
        <div class="leading-tight">
          <div class="font-semibold tracking-wide">ONLYPARK / Cámara</div>
          <div class="text-xs text-white/60">Captura de fotos</div>
        </div>
      </div>
      <div class="flex items-center gap-4">
        <a href="#/" class="text-sm underline text-white/80">← Panel</a>
        <button id="op-logout" class="bg-white/10 hover:bg-white/20 text-sm rounded-md px-3 py-1.5 transition">Salir</button>
      </div>
    </header>

    <main class="flex-1 p-4 max-w-3xl mx-auto w-full">
      <div class="op-card">
        <div class="flex flex-wrap gap-2 mb-3">
          <button id="btn-start"   class="op-btn-primary flex-1 min-w-[140px]">▶ Iniciar cámara</button>
          <button id="btn-snap"    class="op-btn-accent  flex-1 min-w-[140px]" disabled>📸 Tomar foto</button>
          <button id="btn-switch"  class="bg-slate-100 text-marino px-4 py-3 rounded-lg font-semibold" disabled>🔄</button>
        </div>

        <div class="bg-slate-900 rounded-lg overflow-hidden aspect-video relative">
          <video id="op-cam" autoplay playsinline muted class="w-full h-full object-cover"></video>
          <canvas id="op-canvas" class="absolute inset-0 w-full h-full object-cover hidden"></canvas>
          <div id="op-cam-idle" class="absolute inset-0 flex items-center justify-center text-white/40 text-6xl">📷</div>
        </div>

        <p id="op-cam-msg" class="text-sm mt-3 min-h-[1.5rem]"></p>

        <div id="op-cam-actions" class="hidden mt-3 flex gap-2">
          <button id="btn-retake" class="bg-slate-100 text-marino px-4 py-3 rounded-lg font-semibold flex-1">↻ Retomar</button>
          <button id="btn-save"   class="op-btn-primary flex-1">💾 Guardar en bitácora</button>
        </div>
      </div>

      <div class="op-card mt-4">
        <div class="text-sm font-semibold text-marino mb-2">Últimas fotos guardadas</div>
        <div id="op-fotos-hist" class="text-sm text-slate-400">Cargando…</div>
      </div>
    </main>`;

  bindLogout(root);

  const video = root.querySelector('#op-cam');
  const canvas = root.querySelector('#op-canvas');
  const idle = root.querySelector('#op-cam-idle');
  const msg = root.querySelector('#op-cam-msg');
  const btnStart = root.querySelector('#btn-start');
  const btnSnap  = root.querySelector('#btn-snap');
  const btnSwitch = root.querySelector('#btn-switch');
  const btnRetake = root.querySelector('#btn-retake');
  const btnSave  = root.querySelector('#btn-save');
  const actions = root.querySelector('#op-cam-actions');

  let stream = null;
  let facing = 'environment'; // 'user' = frontal, 'environment' = trasera
  let dataURL = null;

  async function iniciar() {
    if (!navigator.mediaDevices?.getUserMedia) {
      msg.className = 'text-red-600 text-sm mt-3'; msg.textContent = 'Este navegador no soporta acceso a la cámara.'; return;
    }
    try {
      if (stream) stream.getTracks().forEach(t => t.stop());
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: facing } }, audio: false });
      video.srcObject = stream;
      idle.classList.add('hidden');
      canvas.classList.add('hidden');
      video.classList.remove('hidden');
      btnSnap.disabled = false;
      btnSwitch.disabled = false;
      btnStart.textContent = '⏹ Detener';
      msg.className = 'text-slate-500 text-sm mt-3'; msg.textContent = 'Cámara activa · resolución ' + video.videoWidth + '×' + video.videoHeight;
    } catch (e) {
      msg.className = 'text-red-600 text-sm mt-3'; msg.textContent = 'No se pudo acceder a la cámara: ' + e.message;
    }
  }
  function detener() {
    if (stream) stream.getTracks().forEach(t => t.stop());
    stream = null;
    video.srcObject = null;
    video.classList.add('hidden');
    canvas.classList.add('hidden');
    idle.classList.remove('hidden');
    btnSnap.disabled = true;
    btnSwitch.disabled = true;
    btnStart.textContent = '▶ Iniciar cámara';
    actions.classList.add('hidden');
    msg.textContent = '';
  }
  function capturar() {
    const w = video.videoWidth, h = video.videoHeight;
    canvas.width = w; canvas.height = h;
    canvas.getContext('2d').drawImage(video, 0, 0, w, h);
    dataURL = canvas.toDataURL('image/jpeg', 0.75);
    canvas.classList.remove('hidden');
    video.classList.add('hidden');
    actions.classList.remove('hidden');
    msg.className = 'text-barrera-700 text-sm mt-3';
    msg.textContent = 'Foto capturada (' + Math.round(dataURL.length / 1024) + ' KB). Guarda o vuelve a tomar.';
  }
  async function guardar() {
    if (!dataURL) return;
    btnSave.disabled = true; btnSave.textContent = 'Guardando…';
    const scope = getScope();
    await log('operativa', 'foto_camara', scope.estacionamiento_id, {
      actor: currentActor(),
      timestamp: new Date().toISOString(),
      bytes: dataURL.length,
      thumb_data_url: dataURL.slice(0, 200) + '…',  // solo prefijo (sin la imagen completa) por tamaño
      resolution: canvas.width + 'x' + canvas.height
    }, 'Foto capturada desde módulo cámara');
    msg.className = 'text-barrera-700 text-sm mt-3';
    msg.textContent = '✅ Registrada en bitácora. (La imagen completa NO se guarda en log — usaremos Supabase Storage cuando conectemos.)';
    btnSave.disabled = false; btnSave.textContent = '💾 Guardar en bitácora';
    await loadHist();
    setTimeout(() => { actions.classList.add('hidden'); canvas.classList.add('hidden'); video.classList.remove('hidden'); }, 1500);
  }
  async function loadHist() {
    const { data } = await supabase.from('log_evento')
      .select('descripcion, ocurrido_at, payload')
      .eq('subtipo', 'foto_camara')
      .order('ocurrido_at', { ascending: false }).limit(10);
    const el = root.querySelector('#op-fotos-hist');
    if (!data?.length) { el.innerHTML = '<div class="text-slate-400">Sin fotos guardadas</div>'; return; }
    el.innerHTML = '<ul class="divide-y">' + data.map(x => `
      <li class="py-1.5 flex justify-between text-xs">
        <span>${x.payload?.actor ?? '—'} <span class="text-slate-400">${x.payload?.resolution ?? ''}</span></span>
        <span class="text-slate-400">${new Date(x.ocurrido_at).toLocaleString()}</span>
      </li>`).join('') + '</ul>';
  }

  btnStart.addEventListener('click', () => stream ? detener() : iniciar());
  btnSnap.addEventListener('click', capturar);
  btnRetake.addEventListener('click', () => { canvas.classList.add('hidden'); video.classList.remove('hidden'); actions.classList.add('hidden'); dataURL = null; });
  btnSave.addEventListener('click', guardar);
  btnSwitch.addEventListener('click', async () => { facing = (facing === 'environment') ? 'user' : 'environment'; if (stream) await iniciar(); });
  await loadHist();
}
