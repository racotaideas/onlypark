# ONLYPARK

Plataforma SaaS de administración inteligente de estacionamientos, desarrollada por RANNIX.

Evolución comercial del MVP **IWOL PARK** (ver `../Versiones/Ver001/`).

## Estado actual

- ✅ Diseño OLTP v1 aplicado a Supabase (87 tablas, 12 funciones, 169 policies RLS, 3 tenants sembrados).
- ✅ **Fix crítico** en helpers de identidad (`fn_perfil_actual` y familia) — reconvertidos a `SECURITY DEFINER` para evitar recursión con RLS. Migración `021_fix_helpers_secdef.sql`.
- ✅ DWH v1 aplicado — schema `dwh`, dimensiones, facts (tickets, pagos, ocupación), tablas de control ETL, funciones incrementales y vista de monitoreo. Migraciones `022`–`024`.
- ✅ Scaffold PWA (HTML + Tailwind + Supabase JS + service worker) — carpeta `app/`.
- ⏳ Módulo funcional de catálogos jerárquicos (Grupos → Empresas → Sucursales → Estacionamientos).
- ⏳ Implementación real de `fn_calcular_importe_sesion` (hoy es stub).
- ⏳ Módulos LPR / cobro / pensiones / promociones / dashboards.

## Estructura del repo

```
OnlyPark/
├── README.md
├── .gitignore
├── .env.example
├── netlify.toml
├── app/                    # PWA estática (Netlify publish dir)
│   ├── index.html
│   ├── manifest.webmanifest
│   ├── sw.js
│   ├── assets/logo.svg
│   ├── css/app.css
│   └── js/
│       ├── env.js
│       ├── supabase.js
│       ├── main.js
│       └── views/{login,home,notfound}.js
└── db/
    └── migrations/         # 001..024 SQL numeradas
```

## Infraestructura

- **Supabase QA:** proyecto `ixumzgorhuhftasgrmhg` (URL `https://ixumzgorhuhftasgrmhg.supabase.co`).
- **Deploy:** Netlify — `https://onlypark.netlify.app`.
- **Repo remoto:** `https://github.com/racotaideas/onlypark`.

Credenciales locales en `../Paso/OnlyPark.txt` (NUNCA commitear). El `service_role` sólo va en env vars de Netlify o Edge Functions — jamás en el bundle del frontend.

## Ejecutar migraciones

Contra Supabase QA, con `SUPABASE_PAT` y `SUPABASE_REF` como variables de entorno:

```bash
python scripts/run_migration.py db/migrations/021_fix_helpers_secdef.sql
```

(El helper está en `../Versiones/Ver001/` scratchpad; se moverá al repo en cuanto se estabilice.)

## Principios rectores

- Producto SaaS multiempresa, multi-estacionamiento, multiusuario, parametrizable.
- Base de datos en 3NF. OLTP y OLAP **separados**: dashboards leen `dwh.*`, jamás `public.*`.
- Placa como entidad estratégica. Sesión como concepto central.
- Bitácoras CORE desde v1. Licenciamiento por planes con módulos activables.
- Auth dual (email+password y Google OAuth) con RLS jerárquica por Grupo→Empresa→Sucursal→Estacionamiento.
