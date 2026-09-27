# ServiLift – Backend (FastAPI)

API para la gestión de certificación de ascensores NTC 5926-1, desde que el asesor registra el cliente
hasta que el cliente descarga el certificado. Misma base tecnológica de LiftSafe (FastAPI + SQLAlchemy +
MySQL/MariaDB + JWT + reportlab), reescrita para el flujo de ServiLift.

## Puesta en marcha

```bash
# 1. Base de datos (una vez)
mysql -u root -p --default-character-set=utf8mb4 < ../database/01_schema.sql
mysql -u root -p --default-character-set=utf8mb4 < ../database/02_seed.sql

# 2. Entorno
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env        # y ajuste SECRET_KEY / DB_PASSWORD

# 3. Usuarios iniciales: ya vienen en ../database/03_datos_iniciales.sql
#    (para otro administrador: python -m scripts.crear_admin)
python -m scripts.crear_admin "Nombre Apellido" admin@empresa.com

# 4. Servidor (0.0.0.0 para que los celulares de la red lo alcancen)
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Documentación interactiva: http://localhost:8000/docs

## Flujo y endpoints principales

| Paso | Rol | Endpoint |
|---|---|---|
| Registrar cliente, edificios y equipos | ASESOR | `POST /clientes`, `POST /clientes/{id}/edificios`, `POST /edificios/{id}/equipos` (o `/equipos/generar`) |
| Crear acceso al portal del cliente | ASESOR | `POST /clientes/{id}/usuarios` |
| Cotizar (edificio + equipos uno a uno con valor) | ASESOR | `POST /cotizaciones` → número `COT-AAAA-NNNN` |
| Enviar al cliente | ASESOR | `POST /cotizaciones/{id}/enviar-cliente` |
| Aprobar / rechazar | CLIENTE | `POST /cotizaciones/{id}/responder` |
| Aceptar y enviar a programación | ASESOR | `POST /cotizaciones/{id}/enviar-programacion` |
| Asignar fecha, hora e inspector (notifica) | PROGRAMACION | `GET /programacion/pendientes`, `POST /programacion` |
| Agenda y abrir informe precargado | INSPECTOR | `GET /inspecciones/agenda`, `POST /inspecciones/iniciar` |
| Variantes (tracción/hidráulico, enhebrado…) | INSPECTOR | `PUT /inspecciones/{id}/variantes` (precarga los "No aplica") |
| Checklist NTC 5926-1 (169 ítems) | INSPECTOR | `GET /inspecciones/{id}/checklist`, `PUT /inspecciones/{id}/resultados` |
| Álbum de fotos | INSPECTOR | `POST /inspecciones/{id}/fotos` (varias a la vez) |
| Firmas: inspector, técnico, representante | INSPECTOR | `POST /inspecciones/{id}/firmas` |
| Finalizar (valida pendientes) | INSPECTOR | `GET /inspecciones/{id}/validar`, `POST /inspecciones/{id}/finalizar` |
| Revisar, devolver o aprobar y firmar (genera PDF) | DIRECTOR_TECNICO | `POST /informes/{id}/devolver`, `POST /informes/{id}/aprobar` |
| Segunda visita si el informe es no conforme | PROGRAMACION / INSPECTOR | `POST /programacion` con `tipo_visita=SEGUNDA`, `PUT /inspecciones/{id}/segunda-visita` |
| Elaborar y enviar certificado (QR), solo si es conforme | CERTIFICADOS | `GET /certificados/pendientes`, `POST /certificados`, `POST /certificados/{id}/enviar` |
| Estado por equipo, informes y certificados | CLIENTE | `GET /seguimiento`, `GET /informes/{id}/pdf`, `GET /certificados/{id}/pdf` |
| Buscar todo por número de cotización | Todos | `GET /seguimiento?numero_cotizacion=COT-2026-0001` |
| Verificación pública del QR | Público | `GET /verificar/{codigo}` |

Otros: `/auth/login`, `/auth/me`, `/usuarios`, `/catalogos/variantes`, `/catalogos/checklist`,
`/catalogos/parametros`, `/instrumentos`, `/notificaciones`, `/dashboard/resumen`,
`/seguimiento/equipo/{id}/historial`.

## Estados por equipo

`PENDIENTE_APROBACION → APROBADO_CLIENTE → POR_PROGRAMAR → PROGRAMADO → EN_INSPECCION → EN_REVISION →
INFORME_APROBADO → CERTIFICADO_LISTO` (más `RECHAZADO` y `ANULADO`). Si el informe es no conforme:
`EN_REVISION → NO_CONFORME → PROGRAMADO (2ª visita) → EN_INSPECCION → EN_REVISION → INFORME_APROBADO`;
el certificado solo se emite con concepto CONFORME. Si el director devuelve el informe,
el equipo vuelve a `EN_INSPECCION`. Cada cambio queda en `historial_estado`.

## Archivos

Fotos (se normalizan a JPG de máx. 1920 px y se crea miniatura), firmas y PDF se guardan en `STORAGE_DIR`.
Los PDF solo se descargan por los endpoints con permisos; el cliente solo ve informes aprobados y
certificados enviados.

## Prueba de punta a punta

Contra una base `servilift_db` recién creada:

```bash
python -m tests.test_flujo
```

Recorre todo el flujo (cotización de 2 de 3 equipos, programación, inspección con 169 ítems, fotos,
firmas, devolución y aprobación del director, certificado y portal del cliente) y deja los PDF de
ejemplo en `tests/salida/`.
