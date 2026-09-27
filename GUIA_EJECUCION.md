# ServiLift – Cómo ejecutar el proyecto (paso a paso)

Carpeta del proyecto: `C:\Users\PC\Documents\Sena\LiftSafe\ServiLift`

## 1. Encender la base de datos
1. Abra el **Panel de control de XAMPP**.
2. Pulse **Start** en **MySQL** (queda en verde, puerto 3306).
3. La base `servilift_db` ya existe con los usuarios de prueba. Si algún día la necesita desde cero:
   ```
   cd C:\Users\PC\Documents\Sena\LiftSafe\ServiLift\database
   C:\xampp\mysql\bin\mysql -u root < 01_schema.sql
   C:\xampp\mysql\bin\mysql -u root < 02_seed.sql
   C:\xampp\mysql\bin\mysql -u root < 03_datos_iniciales.sql
   ```
   (o restaure el respaldo: `C:\xampp\mysql\bin\mysql -u root < servilift_db_20260926_1435.sql`)

## 2. Encender el backend (API)
Abra una terminal (PowerShell) — solo la primera vez crea el entorno e instala dependencias:
```
cd C:\Users\PC\Documents\Sena\LiftSafe\ServiLift\servilift-backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
```
Cada vez que vaya a trabajar:
```
cd C:\Users\PC\Documents\Sena\LiftSafe\ServiLift\servilift-backend
venv\Scripts\activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
- Deje esta terminal abierta.
- Compruebe en el navegador: http://localhost:8000 → "ServiLift API funcionando". Documentación: http://localhost:8000/docs
- El archivo `.env` ya está creado (base `servilift_db`, usuario root sin clave).

## 3. Abrir la app en el computador (oficina)
En **otra** terminal:
```
cd C:\Users\PC\Documents\Sena\LiftSafe\ServiLift\servilift_app
flutter pub get
flutter run -d chrome
```
Se abre Chrome con el login de ServiLift.

## 4. Abrir la app en el celular del inspector
1. Averigüe la IP de su PC: en PowerShell `ipconfig` → "Dirección IPv4" (ej. 192.168.1.50).
2. Edite `servilift_app\assets\.env` y ponga `API_URL=http://192.168.1.50:8000` (su IP).
3. Conecte el celular por USB con **depuración USB** activada, o use el emulador de Android Studio
   (en el emulador la URL es `http://10.0.2.2:8000`).
4. Ejecute:
   ```
   flutter devices
   flutter run -d <id del celular>
   ```
   O genere el instalador: `flutter build apk --release` → `build\app\outputs\flutter-apk\app-release.apk`.
5. El celular y el PC deben estar en la misma red Wi‑Fi. Si no conecta, permita el puerto 8000 en el
   Firewall de Windows (Python / uvicorn).

## 5. Usuarios de prueba (contraseña `123456`)
| Rol | Correo |
|---|---|
| Administrador | admin@gmail.com |
| Asesor | asesor@gmail.com |
| Programación | programacion@gmail.com |
| Inspector | inspector@gmail.com |
| Director técnico | director@gmail.com |
| Certificados | certificados@gmail.com |
| Cliente | cliente@gmail.com |

## 6. Recorrido para probar el flujo completo
1. **Asesor**: Clientes → Cliente → Edificio 1 → *Nueva cotización* → marque ascensores y valores → *Enviar al cliente*.
2. **Cliente**: Cotizaciones → abrir → *Aprobar*.
3. **Asesor**: la cotización → *Aceptar y enviar a programación*.
4. **Programación**: Por programar → *Programar* (inspector, fecha, hora).
5. **Inspector** (celular): Mi agenda → *Iniciar* → Datos (variantes) → Checklist → Fotos → Firmas → *Finalizar*.
6. **Director técnico**: Informes por revisar → revisar → *Aprobar, firmar y generar PDF*
   (si es No conforme, vuelve a Programación como segunda visita).
7. **Certificados**: Por elaborar → *Elaborar certificado* → Certificados → *Enviar*.
8. **Cliente**: Mis equipos → descarga informe y certificado.

## Problemas comunes
| Síntoma | Solución |
|---|---|
| Login dice "No hay conexión con el servidor" | El backend (paso 2) no está encendido o la `API_URL` de `assets\.env` es incorrecta |
| Error de conexión a la base en el backend | MySQL no está encendido en XAMPP (paso 1) |
| `uvicorn` no se reconoce | Falta `venv\Scripts\activate` antes de ejecutarlo |
| Cambié `assets\.env` y no toma la IP | Detenga la app y vuelva a ejecutar `flutter run` (el .env se empaqueta al compilar) |
