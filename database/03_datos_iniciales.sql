-- =====================================================================
-- ServiLift - Datos iniciales de trabajo (usuarios, cliente, edificios, ascensores)
-- Ejecutar después de 01_schema.sql y 02_seed.sql.
-- USUARIOS DE PRUEBA: todos con contraseña 123456 (cámbielas antes de usar en producción).
-- Nombre, NIT y dirección del cliente y de los edificios se completan desde la app.
-- =====================================================================
USE servilift_db;
SET NAMES utf8mb4;
START TRANSACTION;

INSERT INTO usuario (id_rol, nombre_completo, correo, contrasena_hash) SELECT id_rol, 'Administrador', 'admin@gmail.com', '$2b$12$JdhzGVQaNMr0BxG94uRVGut3H2Er4rHTRUYOihfjIK3x1yigaA7eG' FROM rol WHERE codigo = 'ADMIN';
INSERT INTO usuario (id_rol, nombre_completo, correo, contrasena_hash) SELECT id_rol, 'Asesor', 'asesor@gmail.com', '$2b$12$JdhzGVQaNMr0BxG94uRVGut3H2Er4rHTRUYOihfjIK3x1yigaA7eG' FROM rol WHERE codigo = 'ASESOR';
INSERT INTO usuario (id_rol, nombre_completo, correo, contrasena_hash) SELECT id_rol, 'Programación', 'programacion@gmail.com', '$2b$12$JdhzGVQaNMr0BxG94uRVGut3H2Er4rHTRUYOihfjIK3x1yigaA7eG' FROM rol WHERE codigo = 'PROGRAMACION';
INSERT INTO usuario (id_rol, nombre_completo, correo, contrasena_hash) SELECT id_rol, 'Inspector', 'inspector@gmail.com', '$2b$12$JdhzGVQaNMr0BxG94uRVGut3H2Er4rHTRUYOihfjIK3x1yigaA7eG' FROM rol WHERE codigo = 'INSPECTOR';
INSERT INTO usuario (id_rol, nombre_completo, correo, contrasena_hash) SELECT id_rol, 'Director Técnico', 'director@gmail.com', '$2b$12$JdhzGVQaNMr0BxG94uRVGut3H2Er4rHTRUYOihfjIK3x1yigaA7eG' FROM rol WHERE codigo = 'DIRECTOR_TECNICO';
INSERT INTO usuario (id_rol, nombre_completo, correo, contrasena_hash) SELECT id_rol, 'Certificados', 'certificados@gmail.com', '$2b$12$JdhzGVQaNMr0BxG94uRVGut3H2Er4rHTRUYOihfjIK3x1yigaA7eG' FROM rol WHERE codigo = 'CERTIFICADOS';

-- Cliente (atendido por el asesor)
INSERT INTO cliente (id_asesor, tipo_documento, numero_documento, razon_social, contacto_correo)
SELECT id_usuario, 'NIT', 'POR-DEFINIR', 'Cliente', 'cliente@gmail.com' FROM usuario WHERE correo = 'asesor@gmail.com';
SET @cliente = LAST_INSERT_ID();

INSERT INTO usuario (id_rol, id_cliente, nombre_completo, correo, contrasena_hash) SELECT id_rol, @cliente, 'Cliente', 'cliente@gmail.com', '$2b$12$JdhzGVQaNMr0BxG94uRVGut3H2Er4rHTRUYOihfjIK3x1yigaA7eG' FROM rol WHERE codigo = 'CLIENTE';

-- Edificio 1: 4 ascensores
INSERT INTO edificio (id_cliente, nombre, direccion, ciudad, numero_equipos) VALUES (@cliente, 'Edificio 1', 'Por definir', 'Por definir', 4);
SET @edificio = LAST_INSERT_ID();
INSERT INTO equipo (id_edificio, identificacion) VALUES (@edificio, 'Ascensor 1'), (@edificio, 'Ascensor 2'), (@edificio, 'Ascensor 3'), (@edificio, 'Ascensor 4');

-- Edificio 2: 2 ascensores
INSERT INTO edificio (id_cliente, nombre, direccion, ciudad, numero_equipos) VALUES (@cliente, 'Edificio 2', 'Por definir', 'Por definir', 2);
SET @edificio = LAST_INSERT_ID();
INSERT INTO equipo (id_edificio, identificacion) VALUES (@edificio, 'Ascensor 1'), (@edificio, 'Ascensor 2');

COMMIT;
