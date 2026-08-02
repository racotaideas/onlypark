// ============================================================================
// no-login.js — DEV MODE: desactiva completamente el login de los portales IWOL.
// Se inyecta AL INICIO del <head> antes que el resto del JS del portal.
//
// Comportamiento:
//   1. Toma el nombre del operador del localStorage['op_actor'] (el que el user
//      capturo en el panel principal). Si no existe, pide uno con prompt() la
//      primera vez y lo guarda.
//   2. Construye un USUARIO_ACTUAL dummy con rol 'super_admin' y lo guarda en
//      sessionStorage['onlypark_usuario'] (donde el portal lo lee).
//   3. Reemplaza requerirLogin() y solicitarLoginEntrante() para que devuelvan
//      inmediatamente ese usuario, sin mostrar overlay.
//   4. Oculta el overlay de login por CSS (por si alguna llamada residual lo
//      abre).
// ============================================================================
(function () {
  var nombre = localStorage.getItem('op_actor');
  if (!nombre || nombre.trim().length < 2) {
    nombre = (prompt('Nombre del operador (para bitacora):') || 'Operador').trim();
    if (nombre.length < 2) nombre = 'Operador';
    localStorage.setItem('op_actor', nombre);
  }

  var usuarioFake = {
    cajero_id: '00000000-0000-0000-0000-000000000001',
    usuario:   nombre.toLowerCase().replace(/\s+/g, '_'),
    nombre:    nombre,
    rol:       'super_admin',
    plaza_id:  null,
    activo:    true
  };

  // Guardar en el mismo slot que el portal lee
  try { sessionStorage.setItem('onlypark_usuario', JSON.stringify(usuarioFake)); } catch (e) {}

  // Cuando el resto del JS del portal se ejecute, sobrescribimos las funciones
  // de login (definidas mas abajo en el HTML del portal). Esto se hace al DOMContentLoaded
  // porque las funciones se declaran despues en el <script> del propio HTML.
  document.addEventListener('DOMContentLoaded', function () {
    // Sobrescribir requerirLogin: devuelve directo el usuario fake
    if (typeof window.requerirLogin === 'function' || true) {
      window.requerirLogin = function (rolesPermitidos, nombreApp) {
        return Promise.resolve(usuarioFake);
      };
    }
    if (typeof window.solicitarLoginEntrante === 'function' || true) {
      window.solicitarLoginEntrante = function (rolesPermitidos, nombreApp) {
        return Promise.resolve(usuarioFake);
      };
    }
    if (typeof window.opUsuarioActual === 'function' || true) {
      window.opUsuarioActual = function () { return usuarioFake; };
    }

    // Ocultar el overlay de login por si algo lo destapa
    var css = document.createElement('style');
    css.textContent = '#op-login-overlay { display: none !important; }';
    document.head.appendChild(css);

    var ov = document.getElementById('op-login-overlay');
    if (ov) ov.classList.add('hidden');
  });

  // Exponer para debug
  window.__OP_USUARIO_FAKE__ = usuarioFake;

  // ─────────────────────────────────────────────────────────────────────────
  // Interceptar fetch: normalizar el body que el IWOL manda a /tickets, /cortes,
  // /bitacora y /avisos_operador para que caiga bien en nuestras shim views.
  //
  // El IWOL manda:
  //   - plaza (string) en vez de plaza_id (uuid)
  //   - turno_id como string local ('T1785...') que no es UUID valido
  //   - campos que no son columnas (franja, dia_semana, mes, anio, penalizacion)
  // Aqui limpiamos todo eso para que el trigger INSTEAD OF acepte.
  // ─────────────────────────────────────────────────────────────────────────
  var UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  var FIELDS_TO_STRIP = ['franja','dia_semana','mes','anio','penalizacion','plaza','fecha_op','horas_cobradas','tarifa','minutos_estancia'];

  // Puente entre panel principal y portal:
  // Lee el ámbito de la URL (?est=, ?e=, ?g=, ?actor=). Si viene con params,
  // los guarda en localStorage sobrescribiendo cualquier valor previo — así el
  // portal recibe el "login context" que el user eligió en el panel.
  // Fallback: si no hay params, usa lo que ya haya en localStorage.
  var qs = new URLSearchParams(location.search);
  if (qs.get('actor')) { nombre = qs.get('actor').trim(); localStorage.setItem('op_actor', nombre); usuarioFake.nombre = nombre; usuarioFake.usuario = nombre.toLowerCase().replace(/\s+/g,'_'); try { sessionStorage.setItem('onlypark_usuario', JSON.stringify(usuarioFake)); } catch(e){} }
  var qEst = qs.get('est'); var qEmp = qs.get('e'); var qGrp = qs.get('g');
  if (qGrp && UUID_RE.test(qGrp)) localStorage.setItem('op_scope_grupo_id', qGrp);
  if (qEmp && UUID_RE.test(qEmp)) localStorage.setItem('op_scope_empresa_id', qEmp);
  if (qEst && UUID_RE.test(qEst)) localStorage.setItem('op_scope_estacionamiento_id', qEst);

  var scopeEst = localStorage.getItem('op_scope_estacionamiento_id');
  if (scopeEst && UUID_RE.test(scopeEst)) {
    window.__OP_SCOPE_PLAZA_ID__ = scopeEst;
    window.PLAZA_ID = scopeEst;
  }

  // Banner de ámbito arriba del portal con SELECTOR interactivo:
  // permite cambiar Grupo/Empresa/Estac sin salir. Al cambiar, recarga la
  // página con los nuevos params — el portal re-carga con el nuevo contexto.
  document.addEventListener('DOMContentLoaded', function () {
    var banner = document.createElement('div');
    banner.style.cssText = 'position:fixed;top:0;left:0;right:0;background:#0d2340;color:#fff;font-size:11px;padding:5px 12px;z-index:99998;letter-spacing:.3px;display:flex;align-items:center;gap:8px;flex-wrap:wrap;box-shadow:0 2px 6px rgba(0,0,0,.2);';
    banner.innerHTML = ''
      + '<span style="opacity:.8">👤 <b>' + nombre + '</b></span>'
      + '<span style="opacity:.5">|</span>'
      + '<span style="opacity:.7">Ámbito:</span>'
      + '<select id="op-scope-grp" style="background:rgba(255,255,255,.1);color:#fff;border:1px solid rgba(255,255,255,.2);border-radius:3px;padding:2px 6px;font-size:11px;min-width:150px"><option value="">Todos los grupos</option></select>'
      + '<span style="opacity:.4">›</span>'
      + '<select id="op-scope-emp" style="background:rgba(255,255,255,.1);color:#fff;border:1px solid rgba(255,255,255,.2);border-radius:3px;padding:2px 6px;font-size:11px;min-width:170px"><option value="">Todas las empresas</option></select>'
      + '<span style="opacity:.4">›</span>'
      + '<select id="op-scope-est" style="background:rgba(255,255,255,.1);color:#fff;border:1px solid rgba(255,255,255,.2);border-radius:3px;padding:2px 6px;font-size:11px;min-width:180px"><option value="">Todos los estacionamientos</option></select>'
      + '<span style="flex:1"></span>'
      + '<a href="/" style="color:#3aa757;text-decoration:underline">← Panel</a>';
    document.body.appendChild(banner);
    document.body.style.paddingTop = '30px';

    // Cargar opciones desde Supabase REST.
    // ANON no puede leer catalogos (RLS). Autenticamos como usuario compartido
    // dev (operador@onlypark.local) para obtener JWT con permisos super_admin.
    var apikey = (typeof SUPABASE_KEY !== 'undefined') ? SUPABASE_KEY : window.SUPABASE_KEY;
    var url    = (typeof SUPABASE_URL !== 'undefined') ? SUPABASE_URL : window.SUPABASE_URL;
    if (!apikey || !url) return;
    var H = { apikey: apikey, Authorization: 'Bearer ' + apikey };

    // Sign in silencioso — usa origFetch para bypass del shim
    origFetch(url + '/auth/v1/token?grant_type=password', {
      method: 'POST',
      headers: { apikey: apikey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'operador@onlypark.local', password: 'op-dev-2026' })
    }).then(function(r){ return r.json(); }).then(function(t){
      if (t && t.access_token) H.Authorization = 'Bearer ' + t.access_token;
      cargarCombos();
    }).catch(function(){ cargarCombos(); });

    function cargarCombos() {

    var selGrp = document.getElementById('op-scope-grp');
    var selEmp = document.getElementById('op-scope-emp');
    var selEst = document.getElementById('op-scope-est');

    function opt(v,t,sel){var o=document.createElement('option');o.value=v;o.text=t;if(sel)o.selected=true;return o;}

    origFetch(url+'/rest/v1/grupos_empresariales?select=grupo_id,nombre&order=nombre.asc', {headers:H})
      .then(function(r){return r.json();}).then(function(gs){
        if (!Array.isArray(gs)) return;
        gs.forEach(function(g){ selGrp.appendChild(opt(g.grupo_id, g.nombre, g.grupo_id===localStorage.getItem('op_scope_grupo_id'))); });
        return loadEmps(localStorage.getItem('op_scope_grupo_id'), localStorage.getItem('op_scope_empresa_id'));
      }).then(function(){ return loadEsts(localStorage.getItem('op_scope_empresa_id'), localStorage.getItem('op_scope_estacionamiento_id')); });
    } // fin cargarCombos

    function loadEmps(grpId, preserve) {
      var q = '?select=empresa_id,razon_social,grupo_id&order=razon_social.asc' + (grpId ? '&grupo_id=eq.'+grpId : '');
      return origFetch(url+'/rest/v1/empresas'+q, {headers:H}).then(function(r){return r.json();}).then(function(es){
        selEmp.length = 1;
        es.forEach(function(e){ selEmp.appendChild(opt(e.empresa_id, e.razon_social, e.empresa_id===preserve)); });
      });
    }
    function loadEsts(empId, preserve) {
      if (!empId) { selEst.length = 1; return Promise.resolve(); }
      return origFetch(url+'/rest/v1/sucursales?empresa_id=eq.'+empId+'&select=sucursal_id', {headers:H})
        .then(function(r){return r.json();}).then(function(sucs){
          if (!sucs.length) { selEst.length=1; return; }
          var sIds = sucs.map(function(s){return s.sucursal_id;}).join(',');
          return origFetch(url+'/rest/v1/estacionamientos?sucursal_id=in.('+sIds+')&select=estacionamiento_id,nombre,codigo&order=nombre.asc', {headers:H})
            .then(function(r){return r.json();}).then(function(es){
              selEst.length = 1;
              es.forEach(function(e){ selEst.appendChild(opt(e.estacionamiento_id, e.nombre+' · '+e.codigo, e.estacionamiento_id===preserve)); });
            });
        });
    }

    function reloadWithScope() {
      var p = new URLSearchParams();
      if (selGrp.value) p.set('g', selGrp.value);
      if (selEmp.value) p.set('e', selEmp.value);
      if (selEst.value) p.set('est', selEst.value);
      p.set('actor', nombre);
      // Limpia localStorage para que URL params tomen precedencia
      localStorage.removeItem('op_scope_grupo_id');
      localStorage.removeItem('op_scope_empresa_id');
      localStorage.removeItem('op_scope_estacionamiento_id');
      location.href = location.pathname + '?' + p.toString();
    }

    selGrp.addEventListener('change', function(){ selEmp.value=''; selEst.value=''; loadEmps(selGrp.value, null).then(function(){ selEst.length=1; }); });
    selEmp.addEventListener('change', function(){ selEst.value=''; loadEsts(selEmp.value, null); });
    selEst.addEventListener('change', reloadWithScope);
    // Al cambiar grupo/empresa sin elegir estac, tambien recarga (para filtrar por empresa)
    selGrp.addEventListener('change', function(){ setTimeout(reloadWithScope, 300); });
    selEmp.addEventListener('change', function(){ setTimeout(reloadWithScope, 300); });
  });

  var origFetch = window.fetch;

  window.fetch = function (url, opts) {
    try {
      // Intercepta el GET a dim_plaza: si hay scope forzado, filtramos por ese plaza_id
      // para que cargarParametrosPlaza() lea la plaza correcta y no la primera.
      if (typeof url === 'string' && window.__OP_SCOPE_PLAZA_ID__ &&
          url.indexOf('/rest/v1/dim_plaza') > 0 && url.indexOf('plaza_id=eq') < 0) {
        var sep = url.indexOf('?') >= 0 ? '&' : '?';
        url = url + sep + 'plaza_id=eq.' + window.__OP_SCOPE_PLAZA_ID__;
      }

      if (opts && typeof opts.body === 'string' && typeof url === 'string' &&
          (url.indexOf('/rest/v1/tickets') > 0 ||
           url.indexOf('/rest/v1/cortes') > 0 ||
           url.indexOf('/rest/v1/bitacora') > 0 ||
           url.indexOf('/rest/v1/avisos_operador') > 0)) {
        var body;
        try { body = JSON.parse(opts.body); } catch (e) { body = null; }
        if (body && typeof body === 'object' && !Array.isArray(body)) {
          // Rellenar plaza_id desde PLAZA_ID global si falta
          if (!body.plaza_id && typeof window.PLAZA_ID === 'string' && UUID_RE.test(window.PLAZA_ID)) {
            body.plaza_id = window.PLAZA_ID;
          }
          // turno_id no-UUID -> null (por ahora ignoramos el vinculo a cortes_caja)
          if (body.turno_id && !UUID_RE.test(String(body.turno_id))) {
            body.turno_id = null;
          }
          if (body.turno_entrada && !UUID_RE.test(String(body.turno_entrada))) {
            body.turno_entrada = null;
          }
          // Quitar campos que no son columnas
          FIELDS_TO_STRIP.forEach(function (k) { delete body[k]; });
          // Empleado_id / pension_id: si no son UUID, ponlos null
          if (body.empleado_id && !UUID_RE.test(String(body.empleado_id))) body.empleado_id = null;
          if (body.pension_id && !UUID_RE.test(String(body.pension_id))) body.pension_id = null;

          opts = Object.assign({}, opts, { body: JSON.stringify(body) });
        }
      }
    } catch (e) { console.warn('[no-login fetch shim]', e); }
    return origFetch.call(this, url, opts);
  };
})();
