-- ══════════════════════════════════════════
-- ONLYPARK · 003 · Semillas de catálogos globales
-- ══════════════════════════════════════════
-- Idempotente vía ON CONFLICT (codigo) DO NOTHING.
-- Requiere 002.

-- ── Países (LATAM prioritario) ────────────
INSERT INTO cat_pais (codigo_iso2, codigo_iso3, nombre) VALUES
  ('MX','MEX','México'),
  ('CO','COL','Colombia'),
  ('CL','CHL','Chile'),
  ('PE','PER','Perú'),
  ('AR','ARG','Argentina'),
  ('US','USA','Estados Unidos'),
  ('ES','ESP','España')
ON CONFLICT (codigo_iso2) DO NOTHING;

-- ── Monedas ───────────────────────────────
INSERT INTO cat_moneda (codigo_iso, nombre, simbolo, decimales) VALUES
  ('MXN','Peso Mexicano','$',2),
  ('USD','Dólar Estadounidense','US$',2),
  ('COP','Peso Colombiano','$',0),
  ('CLP','Peso Chileno','$',0),
  ('PEN','Sol Peruano','S/',2),
  ('ARS','Peso Argentino','$',2),
  ('EUR','Euro','€',2)
ON CONFLICT (codigo_iso) DO NOTHING;

-- ── Zonas horarias LATAM ──────────────────
INSERT INTO cat_timezone (codigo, nombre, offset_min) VALUES
  ('America/Mexico_City','México (CDMX)', -360),
  ('America/Tijuana','México (Tijuana)', -480),
  ('America/Cancun','México (Cancún)', -300),
  ('America/Bogota','Colombia', -300),
  ('America/Santiago','Chile', -240),
  ('America/Lima','Perú', -300),
  ('America/Argentina/Buenos_Aires','Argentina', -180),
  ('America/New_York','EEUU (Este)', -300),
  ('Europe/Madrid','España', 60)
ON CONFLICT (codigo) DO NOTHING;

-- ── Módulos comercializables ──────────────
INSERT INTO cat_modulo (codigo, nombre, descripcion) VALUES
  ('caseta','Caseta de cobro','Operación en caja: entradas, salidas, cobros, cortes'),
  ('dashboard_admin','Dashboard Administrativo','KPIs, drill-down, gestión operativa'),
  ('dashboard_corporativo','Dashboard Corporativo','Vista consolidada multi-estacionamiento'),
  ('pensiones','Pensiones','Gestión de clientes con mensualidad fija'),
  ('promociones','ONLYPROMO','Motor de promociones y publicidad en tickets'),
  ('onlywallet','ONLYWALLET','Monedero electrónico basado en placa'),
  ('lpr','LPR / Cámaras','Lectura automática de placas'),
  ('pagos_electronicos','Pagos electrónicos','Tarjeta, QR, links, wallets'),
  ('bi','Business Intelligence','Reportes analíticos sobre DWH'),
  ('analisis_demanda','Análisis de Demanda','Patrones de uso por hora/día/franja'),
  ('rendimiento_cajeros','Rendimiento de Cajeros','Comparativos de desempeño'),
  ('bitacoras','Bitácoras','Auditoría configurable'),
  ('api','API pública','Acceso programático de terceros')
ON CONFLICT (codigo) DO NOTHING;

-- ── Roles del sistema (jerarquía top-down) ─
INSERT INTO cat_rol (codigo, nombre, descripcion, nivel) VALUES
  ('super_admin','Super Administrador','RANNIX — control total del producto', 1),
  ('admin_grupo','Administrador de Grupo','Todo un grupo empresarial', 2),
  ('admin_empresa','Administrador de Empresa','Todas las sucursales/estacionamientos de una empresa', 3),
  ('admin_sucursal','Administrador de Sucursal','Todos los estacionamientos de una sucursal', 4),
  ('admin_estacionamiento','Administrador de Estacionamiento','Un estacionamiento específico', 5),
  ('supervisor','Supervisor','Supervisión de caseta y turnos', 6),
  ('cajero','Cajero','Operación de caseta', 7),
  ('consulta','Consulta','Solo lectura', 8)
ON CONFLICT (codigo) DO NOTHING;

-- ── Tipos de límite ───────────────────────
INSERT INTO cat_tipo_limite (codigo, nombre) VALUES
  ('cajones','Máximo de cajones'),
  ('usuarios','Máximo de usuarios'),
  ('sucursales','Máximo de sucursales'),
  ('estacionamientos','Máximo de estacionamientos'),
  ('empresas','Máximo de empresas en el grupo'),
  ('transacciones_mes','Máximo de transacciones por mes')
ON CONFLICT (codigo) DO NOTHING;

-- ── Planes comerciales base ───────────────
INSERT INTO cat_plan (codigo, nombre, descripcion, precio_base, moneda_id)
SELECT c.codigo, c.nombre, c.descripcion, c.precio_base,
       (SELECT moneda_id FROM cat_moneda WHERE codigo_iso='MXN')
FROM (VALUES
  ('basic','Basic','1 estacionamiento, 5 usuarios, sin BI', 990.00),
  ('professional','Professional','Multi-usuario, dashboards, pensiones, promociones', 2990.00),
  ('enterprise','Enterprise','Multi-sucursal, multi-empresa, API, BI, LPR, monedero', 7990.00)
) AS c(codigo, nombre, descripcion, precio_base)
ON CONFLICT (codigo) DO NOTHING;

-- ── Métodos de pago genéricos ─────────────
INSERT INTO cat_metodo_pago (codigo, nombre, requiere_referencia) VALUES
  ('efectivo','Efectivo', false),
  ('tarjeta_debito','Tarjeta de Débito', true),
  ('tarjeta_credito','Tarjeta de Crédito', true),
  ('transferencia','Transferencia bancaria', true),
  ('deposito','Depósito bancario', true),
  ('monedero','Monedero ONLYWALLET', false),
  ('qr','Pago con QR', true),
  ('link_pago','Link de pago', true),
  ('wallet','Wallet externa (Apple/Google Pay)', true),
  ('cortesia','Cortesía (sin cobro)', false)
ON CONFLICT (codigo) DO NOTHING;

-- ── Tipos de vehículo ─────────────────────
INSERT INTO cat_tipo_vehiculo (codigo, nombre) VALUES
  ('auto','Automóvil'),
  ('moto','Motocicleta'),
  ('camion','Camión / Camioneta'),
  ('bicicleta','Bicicleta'),
  ('discapacitado','Vehículo con placa de discapacitado'),
  ('electrico','Vehículo eléctrico')
ON CONFLICT (codigo) DO NOTHING;

-- ── Tipos de bitácora ─────────────────────
INSERT INTO cat_tipo_bitacora (codigo, nombre, descripcion) VALUES
  ('operativa','Operativa','Login, entradas, salidas, cobros, cancelaciones, cortesías, impresiones'),
  ('seguridad','Seguridad','Cambios de usuarios, roles, permisos, passwords, accesos fallidos'),
  ('click','Click tracking','Pantallas, botones, módulos, tiempo, secuencia de navegación'),
  ('sistema','Sistema','Excepciones, errores, performance, sync, eventos técnicos')
ON CONFLICT (codigo) DO NOTHING;

-- ── Estados por dominio ───────────────────
INSERT INTO cat_estado_sesion (codigo, nombre, es_final, color_hex) VALUES
  ('abierta','Abierta', false, '#0A66C2'),
  ('pagada','Pagada', false, '#0D9457'),
  ('liberada','Liberada (tolerancia salida)', false, '#F5A623'),
  ('cerrada','Cerrada (salida completada)', true, '#6E6E73'),
  ('cancelada','Cancelada', true, '#D93025'),
  ('perdida','Boleto perdido', true, '#D93025')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO cat_estado_pago (codigo, nombre, es_final) VALUES
  ('pendiente','Pendiente', false),
  ('autorizado','Autorizado', false),
  ('capturado','Capturado', false),
  ('conciliado','Conciliado', true),
  ('rechazado','Rechazado', true),
  ('reembolsado','Reembolsado', true),
  ('cancelado','Cancelado', true)
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO cat_estado_pension (codigo, nombre) VALUES
  ('activo','Activo'),
  ('suspendido','Suspendido'),
  ('cancelado','Cancelado'),
  ('vencido','Vencido')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO cat_estado_licencia (codigo, nombre) VALUES
  ('activa','Activa'),
  ('en_gracia','En periodo de gracia'),
  ('vencida','Vencida'),
  ('cancelada','Cancelada'),
  ('suspendida','Suspendida')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO cat_estado_movimiento_monedero (codigo, nombre) VALUES
  ('aplicado','Aplicado'),
  ('reversado','Reversado'),
  ('pendiente','Pendiente'),
  ('rechazado','Rechazado')
ON CONFLICT (codigo) DO NOTHING;

-- ── Tipos de movimiento de monedero (con signo) ─
INSERT INTO cat_tipo_movimiento_monedero (codigo, nombre, signo) VALUES
  ('recarga','Recarga', 1),
  ('pago','Pago de estacionamiento', -1),
  ('reversa_pago','Reversa de pago', 1),
  ('ajuste_positivo','Ajuste manual (crédito)', 1),
  ('ajuste_negativo','Ajuste manual (débito)', -1),
  ('promocion','Bonificación por promoción', 1),
  ('expiracion','Expiración de saldo', -1),
  ('transferencia_entrada','Transferencia recibida', 1),
  ('transferencia_salida','Transferencia enviada', -1)
ON CONFLICT (codigo) DO NOTHING;
