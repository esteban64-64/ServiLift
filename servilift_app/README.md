# ServiLift – App Flutter

Una sola app para todos los roles: los inspectores la usan en el celular (Android) y el resto del equipo
en el computador (web o Windows). El menú cambia según el rol del usuario.

| Rol | Pantallas |
|---|---|
| Asesor | Seguimiento, Clientes (edificios y ascensores, usuario del portal), Cotizaciones (crear, enviar al cliente, enviar a programación) |
| Cliente | Mis equipos (estado por equipo, descarga de informes y certificados), Cotizaciones (aprobar / rechazar) |
| Programación | Por programar (1ª y 2ª visita), Calendario (reprogramar / cancelar) |
| Inspector | Mi agenda → informe: Datos y variantes, Checklist NTC 5926-1, Fotos, Firmas, Finalizar |
| Director técnico | Informes por revisar (resumen, checklist, fotos), Devolver, Aprobar con firma (genera PDF) |
| Certificados | Por elaborar (solo informes conformes), Certificados (ver, enviar al cliente) |

## Configuración

`assets/.env` define la URL del backend:

```
API_URL=http://localhost:8000        # Chrome / Windows en el mismo PC
API_URL=http://10.0.2.2:8000         # emulador Android
API_URL=http://192.168.X.X:8000      # celular en la misma Wi-Fi (IP del PC con el backend)
```

## Ejecutar y compilar

```bash
flutter pub get
flutter run -d chrome            # oficina
flutter run -d <celular>         # inspector
flutter build apk --release      # APK para los celulares
flutter build web --release      # versión web para el equipo
```

Los usuarios de prueba se crean con `database/03_datos_iniciales.sql`. Solo el administrador crea
usuarios y restablece contraseñas (menú Usuarios); cada uno puede cambiar la suya en "Cambiar contraseña".

## Notas

- El checklist se guarda solo cada 2 segundos; si no hay señal, conserva los cambios y reintenta.
- Las fotos se suben en lotes de 5 (se pueden elegir varias de la galería o tomarlas con la cámara).
- El APK de release queda firmado con la llave de depuración; para publicarlo hay que configurar una llave propia.
