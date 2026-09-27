# ServiLift – Base de datos

MariaDB 10.4+ (XAMPP) o MySQL 8+.

```bash
mysql -u root -p --default-character-set=utf8mb4 < 01_schema.sql
mysql -u root -p --default-character-set=utf8mb4 < 02_seed.sql
mysql -u root -p --default-character-set=utf8mb4 < 03_datos_iniciales.sql
```

`03_datos_iniciales.sql` crea los usuarios de prueba (admin, asesor, programacion, inspector, director,
certificados y cliente @gmail.com, contraseña `123456`) y el cliente con Edificio 1 (4 ascensores) y
Edificio 2 (2 ascensores). Solo el administrador crea usuarios (menú Usuarios de la app).

Crea la base `servilift_db` (no toca `liftsafe_db`).

## Flujo y estados por equipo (`cotizacion_equipo.estado`)

| Estado | Quién lo produce |
|---|---|
| PENDIENTE_APROBACION | Asesor envía la cotización al cliente |
| APROBADO_CLIENTE | Cliente aprueba |
| POR_PROGRAMAR | Asesor acepta y envía a programación |
| PROGRAMADO | Programación asigna fecha, hora e inspector |
| EN_INSPECCION | Inspector abre el informe en el celular |
| EN_REVISION | Inspector finaliza (checklist, fotos, 3 firmas) |
| NO_CONFORME | Director aprueba el informe con hallazgos: visible al cliente, certificado bloqueado, pasa a programación para la 2ª visita |
| INFORME_APROBADO | Informe conforme (sin hallazgos o todos corregidos en la 2ª visita): pasa a certificados |
| CERTIFICADO_LISTO | Certificados emite y envía el certificado |
| RECHAZADO / ANULADO | Cliente rechaza / se anula |

Todo se filtra por `numero_cotizacion` con la vista `v_seguimiento_equipo`.

## Checklist NTC 5926-1

- 169 ítems tomados de la plantilla de ejemplo, redactados como defecto
  (se marca NO CUMPLE si se presenta), con calificación LEVE / GRAVE / MUY_GRAVE.
- 30 ítems con obligación de medida (`requiere_medicion`).
- Agrupados en 11 zonas para navegar en el celular (propuesta, editable).
- Variantes que el inspector elige al abrir el informe: accionamiento, enhebrado,
  máquina, tracción por, cuarto de máquinas, buffer, limitadores, cuarto de poleas,
  puerta de socorro, tipo de puerta y mirilla.
- `checklist_item_variante` + vista `v_inspeccion_item_aplica` precargan como
  NO APLICA los ítems que no corresponden a esas variantes (el inspector puede cambiarlos).

## Tablas

- Seguridad: `rol`, `usuario`
- Clientes: `cliente`, `edificio`, `equipo`
- Variantes: `variante_tipo`, `variante_opcion`, `equipo_variante`
- Comercial: `consecutivo`, `cotizacion`, `cotizacion_equipo`, `historial_estado`
- Programación: `programacion` (primera visita o segunda visita de cierre), `programacion_equipo`
- Checklist: `checklist_categoria`, `checklist_item`, `checklist_item_variante`
- Inspección: `inspeccion`, `inspeccion_variante`, `inspeccion_resultado`, `inspeccion_foto`,
  `inspeccion_firma` (por visita), `instrumento_medicion`, `inspeccion_instrumento`, `inspeccion_medicion`
- Cierre: `informe` (con resumen L/G/MG/NA), `certificado`
- Soporte: `parametro`, `notificacion`, `auditoria`
