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

  // Banner de ámbito arriba del portal (muestra que "estás logueado" con ese scope)
  document.addEventListener('DOMContentLoaded', function () {
    if (!scopeEst) return;
    var banner = document.createElement('div');
    banner.style.cssText = 'position:fixed;top:0;left:0;right:0;background:#0d2340;color:#fff;font-size:11px;padding:4px 12px;z-index:99998;text-align:center;letter-spacing:.3px;';
    banner.innerHTML = 'Ámbito operativo: <b>' + nombre + '</b> · plaza ' + scopeEst.slice(0,8) + '… <a href="/" style="color:#3aa757;margin-left:12px;text-decoration:underline">← volver al panel</a>';
    document.body.appendChild(banner);
    document.body.style.paddingTop = '24px';
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
