# ServiLift

Gestión de certificación de ascensores bajo la NTC 5926-1: desde que el asesor registra al cliente y cotiza
(número de cotización único para hacer seguimiento) hasta la entrega del certificado.

| Carpeta | Contenido |
|---|---|
| `database/` | Esquema MariaDB/MySQL (`01_schema.sql`), catálogo y checklist de 169 ítems (`02_seed.sql`), usuarios de prueba (`03_datos_iniciales.sql`) y migraciones |
| `servilift-backend/` | API FastAPI (Python): cotizaciones, programación, inspección, informes PDF (1ª y 2ª visita), certificados con QR |
| `servilift_app/` | App Flutter: web/Windows para oficina y Android para inspectores; menú por rol |

Cómo ejecutarlo paso a paso: [GUIA_EJECUCION.md](GUIA_EJECUCION.md).

Roles: administrador, asesor, cliente, programación, inspector, director técnico y certificados.
