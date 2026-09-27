# ServiLift

Sistema para gestionar de principio a fin una empresa de **certificación de ascensores bajo la norma
NTC 5926-1:2012**: desde que el asesor registra al cliente y le hace la cotización (con un **número de
cotización único** que sirve para rastrear todo) hasta que el cliente descarga el certificado.

- Los **inspectores** trabajan en el **celular** (app Android).
- El **director técnico, asesores, programación, certificados y el administrador** trabajan en el
  **computador** (la misma app en el navegador o en Windows).
- El **cliente** tiene su propio portal para aprobar cotizaciones y descargar informes y certificados.

---

## Contenido

1. [Arquitectura general](#1-arquitectura-general)
2. [Flujo del negocio y estados](#2-flujo-del-negocio-y-estados)
3. [Base de datos (MariaDB / MySQL)](#3-base-de-datos-mariadb--mysql)
4. [Backend (Python + FastAPI)](#4-backend-python--fastapi)
5. [Frontend (Flutter)](#5-frontend-flutter)
6. [Informes PDF y certificados](#6-informes-pdf-y-certificados)
7. [Seguridad](#7-seguridad)
8. [Cómo ejecutarlo](#8-cómo-ejecutarlo)
9. [Pruebas](#9-pruebas)
10. [Estructura de carpetas](#10-estructura-de-carpetas)

---

## 1. Arquitectura general

```
┌─────────────────────────────┐        HTTP / JSON (JWT)        ┌──────────────────────────┐       SQL        ┌───────────────────┐
│  App Flutter (servilift_app)│  ─────────────────────────────▶ │ API FastAPI              │ ───────────────▶ │ MariaDB / MySQL   │
│  · Web / Windows: oficina   │ ◀─────────────────────────────  │ (servilift-backend)      │ ◀─────────────── │ servilift_db      │
│  · Android: inspectores     │   fotos (multipart), PDF        │ · reglas de negocio      │                  │                   │
└─────────────────────────────┘                                 │ · PDF (reportlab)        │                  └───────────────────┘
                                                                │ · archivos en storage/   │
                                                                └──────────────────────────┘
```

| Capa | Tecnología | Para qué |
|---|---|---|
| Base de datos | **MariaDB 10.4** (XAMPP) / compatible con **MySQL 8** | Datos del negocio, catálogo del checklist, historial |
| Backend | **Python 3.13**, **FastAPI**, **SQLAlchemy 2**, **PyMySQL**, **Pydantic 2** | API REST, reglas de negocio, estados, notificaciones |
| Seguridad | **JWT** (python-jose), **bcrypt** | Inicio de sesión y permisos por rol |
| PDF | **ReportLab** (+ **Pillow** para las fotos) | Informe de 1ª y 2ª visita, certificado con **código QR** |
| Frontend | **Flutter 3** (Dart 3), **Material 3** | Una sola app para todos los roles (web, Windows, Android) |

---

## 2. Flujo del negocio y estados

```
Asesor ──▶ Cliente ──▶ Asesor ──▶ Programación ──▶ Inspector ──▶ Director técnico ──▶ Certificados ──▶ Cliente
registra   aprueba     envía a    asigna fecha,    checklist,     revisa, atesta,      emite el          descarga
cliente,   la          programa-  hora e           fotos,         firma y genera       certificado       informes y
edificios, cotización  ción       inspector        firmas         el PDF               con QR            certificado
equipos y
cotiza
```

Cada **equipo cotizado** tiene su propio estado (tabla `cotizacion_equipo`), que es lo que ve el cliente:

| Estado | Qué significa | Quién lo cambia |
|---|---|---|
| `PENDIENTE_APROBACION` | Cotización enviada al cliente | Asesor |
| `APROBADO_CLIENTE` | El cliente aprobó | Cliente |
| `POR_PROGRAMAR` | En la bandeja de programación | Asesor (acepta y envía) |
| `PROGRAMADO` | Tiene fecha, hora e inspector | Programación |
| `EN_INSPECCION` | El inspector abrió el informe | Inspector |
| `EN_REVISION` | Inspección finalizada, la revisa el director | Inspector |
| `NO_CONFORME` | Informe aprobado con hallazgos: hay que corregir | Director técnico |
| `SEGUNDA_VISITA_SOLICITADA` | El cliente o el asesor pidió la visita de cierre | Cliente / Asesor |
| `INFORME_APROBADO` | Informe conforme, pasa a certificados | Director técnico |
| `CERTIFICADO_LISTO` | Certificado disponible para el cliente | Certificados |
| `RECHAZADO` / `ANULADO` | Cotización rechazada o anulada | Cliente / Asesor |

**Segunda visita (cierre de hallazgos):** si el informe queda *No conforme*, el certificado queda
bloqueado. El sistema calcula el plazo para corregir (el menor entre los hallazgos: **leve 180 días,
grave 30 días, muy grave inmediato**, configurable), el cliente o el asesor solicitan la segunda visita,
el inspector marca cada hallazgo como *corregido / no corregido* con foto, y el director aprueba el
**informe de 2ª visita**. Solo con concepto **conforme** se puede emitir el certificado.

Todo cambio queda en `historial_estado`, que cualquier rol relacionado puede consultar como línea de tiempo.

---

## 3. Base de datos (MariaDB / MySQL)

Carpeta `database/`:

| Archivo | Contenido |
|---|---|
| `01_schema.sql` | Crea `servilift_db`: 30 tablas, llaves foráneas, índices y 2 vistas |
| `02_seed.sql` | Roles, variantes de equipo, parámetros y el **checklist NTC 5926-1 de 169 ítems** con su calificación (Leve / Grave / Muy grave) |
| `03_datos_iniciales.sql` | Usuarios de prueba (un usuario por rol) y un cliente con 2 edificios |
| `migraciones/*.sql` | Cambios para actualizar una base ya creada |

### Tablas principales

| Grupo | Tablas |
|---|---|
| Seguridad | `rol`, `usuario` |
| Clientes | `cliente`, `edificio`, `equipo` |
| Variantes del equipo | `variante_tipo`, `variante_opcion`, `equipo_variante` (tracción/hidráulico, enhebrado, máquina, buffer, etc.) |
| Comercial | `consecutivo` (numeración COT/INS/INF/CER), `cotizacion`, `cotizacion_equipo`, `historial_estado` |
| Programación | `programacion` (1ª o 2ª visita), `programacion_equipo` |
| Checklist | `checklist_categoria`, `checklist_item`, `checklist_item_variante` (qué ítems aplican según las variantes) |
| Inspección | `inspeccion`, `inspeccion_variante`, `inspeccion_resultado`, `inspeccion_foto`, `inspeccion_firma`, `instrumento_medicion`, `inspeccion_instrumento`, `inspeccion_medicion` |
| Cierre | `informe` (1ª y 2ª visita, atestación, firma del director), `certificado` (código de verificación) |
| Soporte | `parametro` (plazos, textos del informe), `notificacion`, `auditoria` |

### Vistas

- `v_seguimiento_equipo`: una fila por equipo cotizado con cotización, cliente, edificio, programación,
  inspección, informe y certificado. Es la que permite **filtrar todo por número de cotización**.
- `v_inspeccion_item_aplica`: dice qué ítems del checklist aplican a cada inspección según las variantes
  elegidas; los demás se precargan como *No aplica*.

### Numeración

`COT-2026-0001` (cotización), `COT-2026-0001-01` (cada equipo de la cotización), `INS-…` (inspección),
`INF-…` (informe) y `CER-…` (certificado). Los consecutivos se generan con bloqueo de fila
(`SELECT … FOR UPDATE`) para que nunca se repitan.

---

## 4. Backend (Python + FastAPI)

Carpeta `servilift-backend/`.

### Librerías

| Librería | Uso |
|---|---|
| `fastapi` + `uvicorn` | Servidor web y API REST (documentación automática en `/docs`) |
| `SQLAlchemy 2` + `PyMySQL` | ORM y conexión a MariaDB/MySQL |
| `pydantic` / `pydantic-settings` | Validación de datos de entrada y lectura del `.env` |
| `python-jose` | Tokens JWT de sesión y enlaces temporales de descarga |
| `bcrypt` | Cifrado de contraseñas |
| `python-multipart` | Subida de fotos (varias a la vez) |
| `Pillow` | Normaliza las fotos (máx. 1920 px) y crea miniaturas |
| `reportlab` | Genera los PDF del informe y del certificado, incluido el código QR |
| `email-validator`, `httpx` | Validación de correos y pruebas automáticas |

### Organización del código

```
servilift-backend/app/
├── main.py            # Crea la app, CORS, registra las rutas, sirve fotos y firmas
├── config.py          # Configuración leída del .env (base de datos, clave JWT, carpeta de archivos)
├── database.py        # Conexión SQLAlchemy y sesión por petición
├── models.py          # Modelos ORM de todas las tablas
├── security.py        # Contraseñas, JWT, permisos por rol, enlaces temporales de descarga
├── routes/            # Endpoints (uno por módulo)
│   ├── auth.py            login, usuario actual, cambiar contraseña
│   ├── usuarios.py        usuarios y roles (solo administrador)
│   ├── clientes.py        clientes, edificios y equipos
│   ├── cotizaciones.py    crear/editar, enviar al cliente, aprobar/rechazar, enviar a programación
│   ├── programacion.py    bandeja por programar (1ª y 2ª visita), calendario, reprogramar, cancelar
│   ├── inspecciones.py    agenda, abrir informe, variantes, datos del ascensor, checklist, fotos, firmas, finalizar, 2ª visita
│   ├── informes.py        revisión del director: vista previa, devolver, aprobar, PDF de 1ª y 2ª visita
│   ├── certificados.py    emitir, enviar, anular, PDF, verificación pública del QR
│   ├── seguimiento.py     estado por equipo, historial, solicitar 2ª visita
│   ├── dashboard.py       página de inicio con indicadores y gráficas según el rol
│   ├── catalogos.py       variantes, checklist, parámetros, instrumentos, notificaciones
│   └── serializers.py     conversión de modelos a JSON
└── services/
    ├── flujo.py       máquina de estados por equipo, consecutivos, notificaciones, historial
    ├── checklist.py   ítems que aplican, resumen de hallazgos, validaciones para finalizar, plazos
    ├── archivos.py    guardado de fotos y firmas, hash SHA-256 de los PDF
    └── pdf.py         informe (1ª / 2ª visita) y certificado con QR
```

### Reglas de negocio destacadas

- **Permisos por rol** en cada endpoint (`require_roles`); el administrador tiene acceso total y es el
  único que crea usuarios.
- **Máquina de estados**: un equipo solo puede pasar a los estados permitidos; cada cambio se registra.
- **Finalizar inspección** exige: variantes elegidas, los 169 ítems calificados, medidas en los ítems con
  obligación de medida, **foto de evidencia en cada No cumple** y las 3 firmas (inspector, técnico de
  mantenimiento y representante del edificio).
- **Certificado bloqueado** mientras el informe no sea conforme.
- **Guardado idempotente** (identificador `uuid_offline`) para que el celular pueda reintentar sin duplicar.

---

## 5. Frontend (Flutter)

Carpeta `servilift_app/`. Una sola app para todos los roles; el menú cambia según quién inicia sesión.

### Librerías

| Paquete | Uso |
|---|---|
| `http` | Llamadas a la API |
| `provider` | Estado de la sesión |
| `shared_preferences` / `web` | Guardar la sesión (en el navegador, una sesión por pestaña) |
| `flutter_dotenv` | URL del backend (`assets/.env`) |
| `intl` + `flutter_localizations` | Fechas y moneda en español (Colombia) |
| `signature` | Captura de firmas en pantalla |
| `image_picker` | Fotos con la cámara o varias desde la galería |
| `url_launcher` | Abrir PDF y mapas |
| `uuid` | Identificadores para reintentos sin duplicar |

### Organización del código

```
servilift_app/lib/
├── main.dart                 # Arranque, tema, idioma, sesión
├── core/
│   ├── api.dart              # Cliente HTTP, manejo de errores, subida de fotos, apertura de PDF
│   ├── auth.dart             # Sesión y roles
│   ├── tema.dart             # Colores, etiquetas y colores de cada estado, formatos
│   └── almacen/              # Dónde se guarda la sesión (celular/PC vs. pestaña del navegador)
├── widgets/                  # Componentes reutilizables: cargador con actualización automática,
│                             #   formularios, firma, fecha con opción NI, historial, plazo de corrección
└── screens/
    ├── login.dart, shell.dart            # Ingreso y menú por rol
    ├── comun/                            # Inicio (indicadores y gráficas), seguimiento, cotizaciones, notificaciones
    ├── admin/                            # Usuarios y parámetros
    ├── asesor/                           # Clientes, edificios, equipos y formulario de cotización
    ├── programacion/                     # Por programar y calendario
    ├── inspector/                        # Agenda e inspección: datos, checklist, fotos, firmas
    ├── director/                         # Bandeja y revisión de informes
    └── certificados/                     # Por elaborar y certificados emitidos
```

### Qué ve cada rol

| Rol | Pantallas |
|---|---|
| Administrador | Inicio, usuarios, parámetros y todos los módulos |
| Asesor | Inicio, seguimiento, clientes (edificios y equipos), cotizaciones |
| Cliente | Inicio, mis equipos (estado, informes 1ª/2ª visita, certificados), cotizaciones por aprobar |
| Programación | Inicio, por programar (1ª y 2ª visita con plazos), calendario |
| Inspector | Inicio, mi agenda, inspección (celular), seguimiento |
| Director técnico | Inicio, informes por revisar y aprobados (resumen, hallazgos con fotos, borrador PDF) |
| Certificados | Inicio, certificados por elaborar y emitidos |

Otras funciones: las listas se actualizan solas, notificaciones que abren directamente lo que avisan,
historial de cada equipo desde cualquier módulo y guardado automático del checklist con reintento.

---

## 6. Informes PDF y certificados

- **Informe de 1ª visita** y **de 2ª visita** por separado. El de 1ª se conserva tal cual; el de 2ª reutiliza
  el mismo formato con las columnas *corregido / no corregido*, la foto de la corrección y las firmas de la
  segunda visita.
- Contenido: datos del cliente y del equipo, mantenimiento, características técnicas, resumen con tiempos
  de solución, atestación, **hallazgos con su foto en la fila**, evidencia de equipos de medición, firmas
  de ambas visitas, lista de ítems que no aplican y anexo fotográfico.
- El director puede ver un **borrador** (marca de agua) antes de aprobar.
- **Certificado** con número consecutivo, vigencia y **código QR** que lleva a `/verificar/{codigo}`.
- Los PDF guardan su huella **SHA-256** y se descargan con **enlaces temporales** (10 minutos).

---

## 7. Seguridad

- Contraseñas cifradas con **bcrypt**; sesión con **JWT** de 12 horas.
- Cada endpoint valida el rol; el cliente solo ve sus propios datos y solo informes aprobados.
- Los secretos van en `servilift-backend/.env` (no se sube al repositorio; ver `.env.example`).
- Las fotos y PDF se guardan en `servilift-backend/storage/` (tampoco se sube).

---

## 8. Cómo ejecutarlo

La guía paso a paso está en [GUIA_EJECUCION.md](GUIA_EJECUCION.md). En resumen:

```bash
# 1. Base de datos (XAMPP → MySQL → Start)
mysql -u root < database/01_schema.sql
mysql -u root < database/02_seed.sql
mysql -u root < database/03_datos_iniciales.sql

# 2. Backend
cd servilift-backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env          # y poner una SECRET_KEY propia
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# 3. App
cd servilift_app
flutter pub get
flutter run -d chrome             # oficina
flutter build apk --release       # celular de los inspectores (poner la IP del PC en assets/.env)
```

Usuarios de prueba (contraseña `123456`): `admin@gmail.com`, `asesor@gmail.com`, `programacion@gmail.com`,
`inspector@gmail.com`, `director@gmail.com`, `certificados@gmail.com`, `cliente@gmail.com`.
Cámbielos antes de usar el sistema en producción.

---

## 9. Pruebas

- **Backend** (`servilift-backend/tests/test_flujo.py`): recorre el flujo completo contra una base recién
  creada: cotización de 2 de 3 equipos, aprobación, programación, inspección de 169 ítems con fotos y
  firmas, devolución del director, informe no conforme, solicitud y segunda visita, informes de 1ª y 2ª
  visita, certificado, verificación del QR, historial y página de inicio de los 7 roles.
  ```bash
  python -m tests.test_flujo
  ```
- **App**: `flutter analyze` y `flutter test`.

---

## 10. Estructura de carpetas

```
ServiLift/
├── README.md                 # Este documento
├── GUIA_EJECUCION.md         # Paso a paso para ejecutar el proyecto
├── database/                 # Scripts SQL y migraciones
├── servilift-backend/        # API FastAPI (Python)
└── servilift_app/            # App Flutter (web, Windows, Android)
```
