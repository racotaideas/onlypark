# ONLYPARK · Migraciones OLTP

Scripts SQL numerados que instancian el modelo operacional descrito en `../../../Versiones/ONLYPARK_diseno_OLTP_v1.md`.

## Orden de ejecución

Los scripts están numerados con el orden **estricto** de dependencias. Ejecutar de menor a mayor. Todos son **idempotentes** — pueden re-ejecutarse sin efecto adverso (usan `IF NOT EXISTS`, `ON CONFLICT DO NOTHING`, `CREATE OR REPLACE`).

| # | Script | Contenido |
|---|---|---|
| 001 | `001_extensions.sql` | Extensiones Postgres (pgcrypto, citext, pg_trgm, btree_gist, uuid-ossp). |
| 002 | `002_cat_globales.sql` | Catálogos globales del sistema (país, moneda, timezone, roles, permisos, módulos, planes, tipos_limite, métodos de pago, tipos de vehículo, tipos de bitácora, estados por dominio, tipos de movimiento de monedero). |
| 003 | `003_semillas_cat_globales.sql` | Semillas de contenido para catálogos globales (MX/CO/CL, MXN/USD/COP, roles, etc.). |
| 004 | `004_jerarquia.sql` | grupos_empresariales, empresas, sucursales, estacionamientos + vista `v_jerarquia_estacionamientos`. |
| 005 | `005_perfiles_seguridad.sql` | perfiles_usuario, asignaciones_rol, funciones `fn_perfil_actual`, `fn_estacionamientos_visibles`, `fn_mis_estacionamientos`, `fn_tiene_permiso`. |
| 006 | `006_cat_por_tenant.sql` | Catálogos parametrizables por empresa/estacionamiento (tipo sesión, tipo tarifa, tipo cortesía, tipo descuento, tipo cliente, turno, franja, tipo pensión, tipo promoción, tipo regla impresión). |
| 007 | `007_placas_vehiculos_clientes.sql` | Placas, vehículos, clientes, vinculos_placa_vehiculo + vista `v_placa_vehiculo_vigente`. |
| 008 | `008_sesiones_lpr.sql` | camaras, cortes_caja, sesiones, capturas_lpr, sync_queue. |
| 009 | `009_tarifas.sql` | politicas_tarifarias, reglas_tarifarias, tarifas_historico, stub `fn_calcular_importe_sesion`. |
| 010 | `010_pagos.sql` | pagos (unificado sesión/pensión/recarga monedero). |
| 011 | `011_monedero.sql` | monederos, monedero_placas, movimientos_monedero, `fn_aplicar_movimiento_monedero`. |
| 012 | `012_pensiones.sql` | cat_tipo_pension, pensiones, pagos_pension. |
| 013 | `013_promociones.sql` | locales_anunciantes, campanas y tablas asociadas (M2M + reglas + impresiones + conversiones). |
| 014 | `014_bitacoras.sql` | cfg_bitacora, log_evento particionada por mes, `fn_log`. |
| 015 | `015_licenciamiento.sql` | plan_modulos, plan_limites, licencias, licencia_modulo_overrides, vista `v_empresa_modulos_habilitados`, `fn_modulo_habilitado`. |
| 016 | `016_cfg_estacionamiento.sql` | cfg_estacionamiento (feature flags + parámetros operativos). |
| 017 | `017_versiones_avisos.sql` | versiones_app, avisos_operador. |
| 018 | `018_triggers_updated_at.sql` | Función `tr_set_updated_at` y triggers en todas las tablas con `updated_at`. |
| 019 | `019_rls_policies.sql` | Políticas RLS estándar para todas las tablas operativas. |
| 020 | `020_seeds_tenants_prueba.sql` | 2-3 tenants ficticios (Grupo Carso, Hospital ABC, GRUPO_IWOL_LEGADO) para validar RLS y jerarquía. |

## Cómo ejecutar

**Opción A — MCP de Supabase (recomendada)** — desde una sesión de Claude Code con el MCP conectado:
```
Ejecuta 001_extensions.sql via mcp__supabase__execute_sql
```
El agente lo hace por ti, valida el resultado, y continúa con el siguiente.

**Opción B — psql** — con el connection string de Supabase (Dashboard → Settings → Database → URI):
```bash
for f in db/migrations/*.sql; do
  echo "→ $f"
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$f" || break
done
```

**Opción C — SQL Editor de Supabase** — copia y pega cada script en orden desde el Dashboard. Confirma "success" antes de pasar al siguiente.

## Reversión

**No hay scripts DOWN**. Estamos en desarrollo temprano; la estrategia es re-crear la DB (`DROP SCHEMA public CASCADE; CREATE SCHEMA public;`) y correr desde 001. Cuando lleguemos a producción, se agregarán migraciones incrementales versionadas con timestamps (`YYYYMMDDHHMM_descripcion.sql`).

## Convenciones (recordatorio)

- Nombres en español, snake_case, sin acentos.
- PKs UUID (`gen_random_uuid()`).
- Todas las tablas: `created_at`/`updated_at`. Operativas relevantes: `created_by`/`updated_by`.
- Soft delete via `activo BOOLEAN`. `DELETE` prohibido salvo super_admin.
- Enums prohibidos: tipos son catálogos con FK.
- Prefijos: `cat_` catálogos, `cfg_` config, `log_` bitácoras, `v_` vistas, `fn_` funciones, `tr_` triggers.
- Moneda: `NUMERIC(14,4)`. Timestamps: `TIMESTAMPTZ`.

Ver diseño completo: `../../../Versiones/ONLYPARK_diseno_OLTP_v1.md`.
