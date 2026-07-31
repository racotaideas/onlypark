-- ══════════════════════════════════════════
-- ONLYPARK · 020 · Semillas de tenants de prueba
-- ══════════════════════════════════════════
-- Crea 3 tenants ficticios para validar RLS y jerarquía end-to-end.
-- Idempotente. Requiere 002-019.
--
-- Tenants:
--   1. GRUPO_IWOL_LEGADO / Alcedines del Norte / Plaza IWOL / Estacionamiento Principal
--   2. GRUPO_CARSO / Plaza Satélite / [Sucursal Norte + Sur] / [Estac Norte + Sur]
--   3. GRUPO_HOSPITALARIO / Hospital ABC / [Santa Fe + Observatorio] / 1 estac cada uno

-- ══════════════════════════════════════════
-- 1. GRUPO IWOL (referencia legado)
-- ══════════════════════════════════════════
INSERT INTO grupos_empresariales (codigo, nombre) VALUES
  ('GRUPO_IWOL_LEGADO','Inmobiliaria Alcedines del Norte')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO empresas (grupo_id, pais_id, moneda_id, codigo, razon_social, nombre_comercial, rfc)
SELECT (SELECT grupo_id FROM grupos_empresariales WHERE codigo='GRUPO_IWOL_LEGADO'),
       (SELECT pais_id FROM cat_pais WHERE codigo_iso2='MX'),
       (SELECT moneda_id FROM cat_moneda WHERE codigo_iso='MXN'),
       'IWOL','Inmobiliaria Alcedines del Norte','IWOL Park','IAN2009238UA'
WHERE NOT EXISTS (
  SELECT 1 FROM empresas e
  JOIN grupos_empresariales g ON g.grupo_id = e.grupo_id
  WHERE g.codigo='GRUPO_IWOL_LEGADO' AND e.codigo='IWOL'
);

INSERT INTO sucursales (empresa_id, codigo, nombre, direccion)
SELECT e.empresa_id, 'PLAZA_IWOL','Plaza IWOL','Metepec, Estado de México'
FROM empresas e JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id
WHERE g.codigo='GRUPO_IWOL_LEGADO' AND e.codigo='IWOL'
  AND NOT EXISTS (SELECT 1 FROM sucursales s WHERE s.empresa_id=e.empresa_id AND s.codigo='PLAZA_IWOL');

INSERT INTO estacionamientos (sucursal_id, pais_id, timezone_id, codigo, nombre, capacidad_total, direccion)
SELECT s.sucursal_id,
       (SELECT pais_id FROM cat_pais WHERE codigo_iso2='MX'),
       (SELECT timezone_id FROM cat_timezone WHERE codigo='America/Mexico_City'),
       'PRINCIPAL','Estacionamiento Principal', 68, 'Plaza IWOL, Metepec'
FROM sucursales s JOIN empresas e ON e.empresa_id=s.empresa_id
JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id
WHERE g.codigo='GRUPO_IWOL_LEGADO' AND s.codigo='PLAZA_IWOL'
  AND NOT EXISTS (SELECT 1 FROM estacionamientos ee WHERE ee.sucursal_id=s.sucursal_id AND ee.codigo='PRINCIPAL');

-- ══════════════════════════════════════════
-- 2. GRUPO CARSO (plaza comercial con múltiples estacionamientos)
-- ══════════════════════════════════════════
INSERT INTO grupos_empresariales (codigo, nombre) VALUES ('GRUPO_CARSO','Grupo Carso')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO empresas (grupo_id, pais_id, moneda_id, codigo, razon_social, nombre_comercial)
SELECT (SELECT grupo_id FROM grupos_empresariales WHERE codigo='GRUPO_CARSO'),
       (SELECT pais_id FROM cat_pais WHERE codigo_iso2='MX'),
       (SELECT moneda_id FROM cat_moneda WHERE codigo_iso='MXN'),
       'CARSO_INMOB','Carso Inmobiliaria S.A. de C.V.','Plaza Satélite'
WHERE NOT EXISTS (SELECT 1 FROM empresas e JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id
  WHERE g.codigo='GRUPO_CARSO' AND e.codigo='CARSO_INMOB');

INSERT INTO sucursales (empresa_id, codigo, nombre, direccion)
SELECT e.empresa_id, s.codigo, s.nombre, s.direccion
FROM empresas e JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id,
     (VALUES
       ('SAT_NORTE','Plaza Satélite Norte','Naucalpan, EdoMex — ala norte'),
       ('SAT_SUR','Plaza Satélite Sur','Naucalpan, EdoMex — ala sur')
     ) AS s(codigo, nombre, direccion)
WHERE g.codigo='GRUPO_CARSO' AND e.codigo='CARSO_INMOB'
  AND NOT EXISTS (SELECT 1 FROM sucursales ss WHERE ss.empresa_id=e.empresa_id AND ss.codigo=s.codigo);

INSERT INTO estacionamientos (sucursal_id, pais_id, timezone_id, codigo, nombre, capacidad_total, direccion)
SELECT s.sucursal_id,
       (SELECT pais_id FROM cat_pais WHERE codigo_iso2='MX'),
       (SELECT timezone_id FROM cat_timezone WHERE codigo='America/Mexico_City'),
       est.codigo, est.nombre, est.cap, est.dir
FROM sucursales s JOIN empresas e ON e.empresa_id=s.empresa_id
JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id,
     (VALUES
       ('SAT_NORTE','P1','Nivel P1 Norte', 250, 'Nivel P1'),
       ('SAT_NORTE','P2','Nivel P2 Norte', 300, 'Nivel P2'),
       ('SAT_SUR','P1','Nivel P1 Sur', 240, 'Nivel P1')
     ) AS est(sucursal_codigo, codigo, nombre, cap, dir)
WHERE g.codigo='GRUPO_CARSO' AND s.codigo = est.sucursal_codigo
  AND NOT EXISTS (SELECT 1 FROM estacionamientos ee WHERE ee.sucursal_id=s.sucursal_id AND ee.codigo=est.codigo);

-- ══════════════════════════════════════════
-- 3. GRUPO HOSPITALARIO (multi-sucursal médica)
-- ══════════════════════════════════════════
INSERT INTO grupos_empresariales (codigo, nombre) VALUES ('GRUPO_HOSPITALARIO','Grupo Hospitalario ABC')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO empresas (grupo_id, pais_id, moneda_id, codigo, razon_social)
SELECT (SELECT grupo_id FROM grupos_empresariales WHERE codigo='GRUPO_HOSPITALARIO'),
       (SELECT pais_id FROM cat_pais WHERE codigo_iso2='MX'),
       (SELECT moneda_id FROM cat_moneda WHERE codigo_iso='MXN'),
       'HOSPITAL_ABC','Hospital ABC S.A. de C.V.'
WHERE NOT EXISTS (SELECT 1 FROM empresas e JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id
  WHERE g.codigo='GRUPO_HOSPITALARIO' AND e.codigo='HOSPITAL_ABC');

INSERT INTO sucursales (empresa_id, codigo, nombre, direccion)
SELECT e.empresa_id, s.codigo, s.nombre, s.direccion
FROM empresas e JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id,
     (VALUES
       ('SANTA_FE','Hospital ABC Santa Fe','CDMX — Santa Fe'),
       ('OBSERVATORIO','Hospital ABC Observatorio','CDMX — Observatorio')
     ) AS s(codigo, nombre, direccion)
WHERE g.codigo='GRUPO_HOSPITALARIO'
  AND NOT EXISTS (SELECT 1 FROM sucursales ss WHERE ss.empresa_id=e.empresa_id AND ss.codigo=s.codigo);

INSERT INTO estacionamientos (sucursal_id, pais_id, timezone_id, codigo, nombre, capacidad_total)
SELECT s.sucursal_id,
       (SELECT pais_id FROM cat_pais WHERE codigo_iso2='MX'),
       (SELECT timezone_id FROM cat_timezone WHERE codigo='America/Mexico_City'),
       'PRINCIPAL','Estacionamiento Principal', 150
FROM sucursales s JOIN empresas e ON e.empresa_id=s.empresa_id
JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id
WHERE g.codigo='GRUPO_HOSPITALARIO'
  AND NOT EXISTS (SELECT 1 FROM estacionamientos ee WHERE ee.sucursal_id=s.sucursal_id AND ee.codigo='PRINCIPAL');

-- ══════════════════════════════════════════
-- Turnos y franjas por defecto para cada estacionamiento sembrado
-- ══════════════════════════════════════════
INSERT INTO cat_turno (estacionamiento_id, codigo, nombre, hora_inicio, hora_fin)
SELECT e.estacionamiento_id, t.codigo, t.nombre, t.hi::time, t.hf::time
FROM estacionamientos e,
     (VALUES
       ('MATUTINO','Matutino','06:00','14:00'),
       ('VESPERTINO','Vespertino','14:00','22:00'),
       ('NOCTURNO','Nocturno','22:00','06:00')
     ) AS t(codigo, nombre, hi, hf)
WHERE NOT EXISTS (SELECT 1 FROM cat_turno ct
  WHERE ct.estacionamiento_id=e.estacionamiento_id AND ct.codigo=t.codigo);

INSERT INTO cat_franja (estacionamiento_id, codigo, nombre, hora_inicio, hora_fin, color_hex)
SELECT e.estacionamiento_id, f.codigo, f.nombre, f.hi::time, f.hf::time, f.color
FROM estacionamientos e,
     (VALUES
       ('MADRUGADA','Madrugada','00:00','06:00','#4A4A4A'),
       ('MATUTINO','Matutino','06:00','12:00','#0D9457'),
       ('MEDIODIA','Mediodía','12:00','17:00','#F5A623'),
       ('VESPERTINO','Vespertino-Nocturno','17:00','23:59','#7B5EA7')
     ) AS f(codigo, nombre, hi, hf, color)
WHERE NOT EXISTS (SELECT 1 FROM cat_franja cf
  WHERE cf.estacionamiento_id=e.estacionamiento_id AND cf.codigo=f.codigo);

-- ══════════════════════════════════════════
-- Configuración inicial de cada estacionamiento
-- ══════════════════════════════════════════
INSERT INTO cfg_estacionamiento (estacionamiento_id)
SELECT e.estacionamiento_id
FROM estacionamientos e
WHERE NOT EXISTS (SELECT 1 FROM cfg_estacionamiento c WHERE c.estacionamiento_id=e.estacionamiento_id);

-- ══════════════════════════════════════════
-- Configuración de bitácoras: habilitar todas al 100% en tenants de prueba
-- ══════════════════════════════════════════
INSERT INTO cfg_bitacora (estacionamiento_id, tipo_bitacora_id, habilitada, muestreo_pct)
SELECT e.estacionamiento_id, tb.tipo_bitacora_id, true, 100
FROM estacionamientos e, cat_tipo_bitacora tb
WHERE NOT EXISTS (
  SELECT 1 FROM cfg_bitacora cb
  WHERE cb.estacionamiento_id=e.estacionamiento_id AND cb.tipo_bitacora_id=tb.tipo_bitacora_id
);

-- ══════════════════════════════════════════
-- Licencia ENTERPRISE para IWOL, PROFESSIONAL para Carso y HOSPITAL_ABC
-- ══════════════════════════════════════════
INSERT INTO licencias (empresa_id, plan_id, estado_licencia_id, vigencia_desde, vigencia_hasta, precio_pactado, moneda_id, referencia_venta)
SELECT e.empresa_id,
       (SELECT plan_id FROM cat_plan WHERE codigo=cfg.plan),
       (SELECT estado_licencia_id FROM cat_estado_licencia WHERE codigo='activa'),
       DATE '2026-01-01', DATE '2027-12-31',
       cfg.precio,
       (SELECT moneda_id FROM cat_moneda WHERE codigo_iso='MXN'),
       'SEED-'||e.codigo
FROM empresas e,
     (VALUES
       ('IWOL','enterprise', 7990.00),
       ('CARSO_INMOB','professional', 2990.00),
       ('HOSPITAL_ABC','professional', 2990.00)
     ) AS cfg(codigo, plan, precio)
WHERE e.codigo = cfg.codigo
  AND NOT EXISTS (SELECT 1 FROM licencias l WHERE l.empresa_id=e.empresa_id);

-- ══════════════════════════════════════════
-- Política tarifaria default para IWOL (tarifas rescatadas del baseline)
-- ══════════════════════════════════════════
INSERT INTO politicas_tarifarias (estacionamiento_id, tipo_sesion_id, nombre, vigente_desde, motivo_cambio)
SELECT e.estacionamiento_id, NULL, 'Política default IWOL', DATE '2026-01-01', 'Semilla inicial'
FROM estacionamientos e
JOIN sucursales s ON s.sucursal_id=e.sucursal_id
JOIN empresas em ON em.empresa_id=s.empresa_id
JOIN grupos_empresariales g ON g.grupo_id=em.grupo_id
WHERE g.codigo='GRUPO_IWOL_LEGADO' AND e.codigo='PRINCIPAL'
  AND NOT EXISTS (
    SELECT 1 FROM politicas_tarifarias p
    WHERE p.estacionamiento_id=e.estacionamiento_id AND p.tipo_sesion_id IS NULL
  );

-- Reglas iniciales (tarifas base de IWOL)
INSERT INTO reglas_tarifarias (politica_id, tipo_tarifa_id, monto, fraccion_min, tolerancia_min, prioridad)
SELECT p.politica_id,
       (SELECT tipo_tarifa_id FROM cat_tipo_tarifa WHERE codigo=r.tipo AND empresa_id IS NULL),
       r.monto, r.frac, r.tol, r.pri
FROM politicas_tarifarias p
JOIN estacionamientos e ON e.estacionamiento_id=p.estacionamiento_id
JOIN sucursales s ON s.sucursal_id=e.sucursal_id
JOIN empresas em ON em.empresa_id=s.empresa_id
JOIN grupos_empresariales g ON g.grupo_id=em.grupo_id,
(VALUES
  ('tolerancia', 0.00, NULL, 15, 10),
  ('hora', 15.00, 60, NULL, 20),
  ('minima', 15.00, NULL, NULL, 30)
) AS r(tipo, monto, frac, tol, pri)
WHERE g.codigo='GRUPO_IWOL_LEGADO' AND p.nombre='Política default IWOL'
  AND NOT EXISTS (
    SELECT 1 FROM reglas_tarifarias rr
    WHERE rr.politica_id=p.politica_id
      AND rr.tipo_tarifa_id = (SELECT tipo_tarifa_id FROM cat_tipo_tarifa WHERE codigo=r.tipo AND empresa_id IS NULL)
  );

-- ══════════════════════════════════════════
-- Cámara simulada para IWOL (para probar módulo LPR)
-- ══════════════════════════════════════════
INSERT INTO camaras (estacionamiento_id, codigo, nombre, proposito, es_simulada)
SELECT e.estacionamiento_id, c.codigo, c.nombre, c.prop, true
FROM estacionamientos e
JOIN sucursales s ON s.sucursal_id=e.sucursal_id
JOIN empresas em ON em.empresa_id=s.empresa_id
JOIN grupos_empresariales g ON g.grupo_id=em.grupo_id,
(VALUES
  ('CAM_ENTRADA','Cámara Entrada Principal','entrada'),
  ('CAM_SALIDA','Cámara Salida Principal','salida')
) AS c(codigo, nombre, prop)
WHERE g.codigo='GRUPO_IWOL_LEGADO' AND e.codigo='PRINCIPAL'
  AND NOT EXISTS (
    SELECT 1 FROM camaras cc
    WHERE cc.estacionamiento_id=e.estacionamiento_id AND cc.codigo=c.codigo
  );

-- ══════════════════════════════════════════
-- Reporte final
-- ══════════════════════════════════════════
DO $$
DECLARE
  n_grupos INT; n_empresas INT; n_sucursales INT; n_estac INT;
  n_pol INT; n_reglas INT; n_camaras INT; n_lic INT;
BEGIN
  SELECT COUNT(*) INTO n_grupos FROM grupos_empresariales;
  SELECT COUNT(*) INTO n_empresas FROM empresas;
  SELECT COUNT(*) INTO n_sucursales FROM sucursales;
  SELECT COUNT(*) INTO n_estac FROM estacionamientos;
  SELECT COUNT(*) INTO n_pol FROM politicas_tarifarias;
  SELECT COUNT(*) INTO n_reglas FROM reglas_tarifarias;
  SELECT COUNT(*) INTO n_camaras FROM camaras;
  SELECT COUNT(*) INTO n_lic FROM licencias;
  RAISE NOTICE 'Tenants sembrados — grupos:% empresas:% sucursales:% estacionamientos:% políticas:% reglas:% cámaras:% licencias:%',
    n_grupos, n_empresas, n_sucursales, n_estac, n_pol, n_reglas, n_camaras, n_lic;
END $$;
