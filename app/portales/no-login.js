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
})();
