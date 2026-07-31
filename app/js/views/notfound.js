export function renderNotFound(root, path) {
  root.innerHTML = `
    <main class="flex-1 flex items-center justify-center p-8">
      <div class="op-card text-center">
        <h1 class="text-3xl font-bold text-marino mb-2">404</h1>
        <p class="text-slate-600 mb-4">Ruta no encontrada: <code>${path}</code></p>
        <a href="#/" class="op-btn-primary inline-block">Ir al inicio</a>
      </div>
    </main>`;
}
