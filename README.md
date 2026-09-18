# Plataforma de la Secretaría de Organización · SITAD

Aplicación web de la Secretaría Nacional de Organización del Sindicato de Trabajadores Digitales de REEDCAM (SITAD): afiliación de punta a punta, Padrón de Afiliados único y nacional, directorio y registro de las Secciones, movimientos, incidencias, constituciones y asambleas.

- **Base de datos, autenticación y buzón de archivos:** Supabase, proyecto `sitad` (organización propia del sindicato).
- **Sitio:** estático (HTML + CSS + JS con `@supabase/supabase-js`), publicado con GitHub Pages desde este repositorio.
- **Correo:** Resend (cuando exista el buzón en sindicatodigital.org).

## Estructura

| Carpeta | Qué contiene |
|---|---|
| `supabase/migrations/` | El plano ejecutable de la base (mismo historial que el proyecto en Supabase). |
| `web/` | El sitio (Módulo 1): puerta pública (`afiliate/?s=[seccion]`, `estado/`, `verificar/`), acceso (`entrar/`), CEN (`cen/`), Secretario General (`sg/`), Sección (`seccion/`) y documentos imprimibles (`documento.html`). Se publica solo con GitHub Pages al hacer push a `main` (`.github/workflows/pages.yml`). |

## Reglas

- Este repositorio es público: **nunca** contiene secretos (solo la llave publicable de Supabase) ni datos de personas.
- Las decisiones, el estado por módulo y la bitácora viven en el vault de Obsidian del sindicato (`Vault SITAD/09-Plataforma/`), no aquí.
- Nada se libera a las Secciones hasta que el estatuto de reforma quede aprobado y depositado.

*Este documento orienta. En caso de duda o diferencia prevalecen la Ley Federal del Trabajo, el Estatuto y las resoluciones válidamente emitidas por los órganos competentes.*
