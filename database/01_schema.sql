-- =====================================================================
-- ServiLift - Esquema de base de datos
-- Gestión de certificación de ascensores (NTC 5926-1)
-- Motor: MariaDB 10.4+ / MySQL 8+  (InnoDB, utf8mb4)
--
-- Flujo principal:
--   Asesor crea cliente -> edificios -> equipos
--   Asesor crea cotización (un edificio, equipos elegidos uno a uno, valor por equipo)
--   Cliente aprueba -> Asesor acepta y envía a Programación
--   Programación asigna fecha, hora e inspector (notificación)
--   Inspector (móvil) selecciona variantes, llena checklist, fotos, firmas, finaliza
--   Director técnico revisa, atesta, firma, genera PDF del informe
--     -> el informe queda visible al cliente y pasa a Certificados
--   Certificados emite el certificado y lo envía al cliente
--
-- La llave de seguimiento es cotizacion.numero_cotizacion (COT-AAAA-NNNN);
-- cada equipo cotizado tiene cotizacion_equipo.codigo_servicio (COT-AAAA-NNNN-NN).
-- =====================================================================

CREATE DATABASE IF NOT EXISTS servilift_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE servilift_db;

SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- 1. Seguridad: roles y usuarios
-- ---------------------------------------------------------------------
CREATE TABLE rol (
  id_rol          INT AUTO_INCREMENT PRIMARY KEY,
  codigo          VARCHAR(30)  NOT NULL UNIQUE COMMENT 'ADMIN, ASESOR, CLIENTE, PROGRAMACION, INSPECTOR, DIRECTOR_TECNICO, CERTIFICADOS',
  nombre          VARCHAR(60)  NOT NULL,
  descripcion     VARCHAR(255) NULL,
  fecha_creacion  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE usuario (
  id_usuario        INT AUTO_INCREMENT PRIMARY KEY,
  id_rol            INT NOT NULL,
  id_cliente        INT NULL COMMENT 'Solo para usuarios con rol CLIENTE: empresa a la que pertenecen',
  nombre_completo   VARCHAR(150) NOT NULL,
  correo            VARCHAR(120) NOT NULL UNIQUE,
  contrasena_hash   VARCHAR(255) NOT NULL COMMENT 'bcrypt',
  tipo_documento    ENUM('CC','CE','NIT','PPT','PAS') NULL,
  documento         VARCHAR(30)  NULL,
  telefono          VARCHAR(30)  NULL,
  cargo             VARCHAR(100) NULL,
  matricula_profesional VARCHAR(60) NULL COMMENT 'Inspector / director técnico',
  ruta_firma        VARCHAR(500) NULL COMMENT 'Firma registrada (director técnico, inspector)',
  estado            ENUM('ACTIVO','INACTIVO','BLOQUEADO') NOT NULL DEFAULT 'ACTIVO',
  ultima_sesion     DATETIME NULL,
  fecha_registro    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_modificacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_usuario_rol     FOREIGN KEY (id_rol)     REFERENCES rol(id_rol),
  CONSTRAINT fk_usuario_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente) ON DELETE SET NULL,
  INDEX ix_usuario_rol (id_rol),
  INDEX ix_usuario_cliente (id_cliente)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. Clientes, edificios y equipos
-- ---------------------------------------------------------------------
CREATE TABLE cliente (
  id_cliente        INT AUTO_INCREMENT PRIMARY KEY,
  id_asesor         INT NOT NULL COMMENT 'Asesor que registró / atiende al cliente',
  tipo_documento    ENUM('NIT','CC','CE','PPT','PAS') NOT NULL DEFAULT 'NIT',
  numero_documento  VARCHAR(30)  NOT NULL,
  razon_social      VARCHAR(200) NOT NULL,
  tipo_cliente      ENUM('PROPIEDAD_HORIZONTAL','EMPRESA','PERSONA_NATURAL','ENTIDAD_PUBLICA') NOT NULL DEFAULT 'PROPIEDAD_HORIZONTAL',
  contacto_nombre   VARCHAR(150) NULL,
  contacto_cargo    VARCHAR(100) NULL,
  contacto_correo   VARCHAR(120) NULL,
  contacto_telefono VARCHAR(30)  NULL,
  direccion         VARCHAR(250) NULL,
  ciudad            VARCHAR(100) NULL,
  estado            ENUM('ACTIVO','INACTIVO') NOT NULL DEFAULT 'ACTIVO',
  fecha_registro    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_modificacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_cliente_documento (tipo_documento, numero_documento),
  CONSTRAINT fk_cliente_asesor FOREIGN KEY (id_asesor) REFERENCES usuario(id_usuario),
  INDEX ix_cliente_asesor (id_asesor)
) ENGINE=InnoDB;

CREATE TABLE edificio (
  id_edificio            INT AUTO_INCREMENT PRIMARY KEY,
  id_cliente             INT NOT NULL,
  nombre                 VARCHAR(150) NOT NULL COMMENT 'Ej: Edificio Torres del Parque - Torre A',
  direccion              VARCHAR(250) NOT NULL,
  barrio                 VARCHAR(100) NULL,
  ciudad                 VARCHAR(100) NOT NULL,
  departamento           VARCHAR(100) NULL,
  numero_pisos           INT NULL,
  numero_equipos         INT NOT NULL DEFAULT 0 COMMENT 'Cantidad de ascensores declarada por el cliente',
  administrador_nombre   VARCHAR(150) NULL COMMENT 'Representante del edificio',
  administrador_telefono VARCHAR(30)  NULL,
  administrador_correo   VARCHAR(120) NULL,
  empresa_mantenimiento  VARCHAR(150) NULL,
  latitud                DECIMAL(10,8) NULL,
  longitud               DECIMAL(11,8) NULL,
  estado                 ENUM('ACTIVO','INACTIVO') NOT NULL DEFAULT 'ACTIVO',
  fecha_registro         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_edificio_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente),
  INDEX ix_edificio_cliente (id_cliente)
) ENGINE=InnoDB;

CREATE TABLE equipo (
  id_equipo          INT AUTO_INCREMENT PRIMARY KEY,
  id_edificio        INT NOT NULL,
  identificacion     VARCHAR(80)  NOT NULL COMMENT 'Como lo llama el edificio: Ascensor 1, Ascensor Torre B, Montacargas',
  tipo_equipo        ENUM('ASCENSOR_PASAJEROS','ASCENSOR_CARGA','MONTACARGAS','MONTACAMILLAS','ASCENSOR_VEHICULAR','OTRO') NOT NULL DEFAULT 'ASCENSOR_PASAJEROS',
  marca              VARCHAR(80)  NULL,
  modelo             VARCHAR(80)  NULL,
  numero_serie       VARCHAR(80)  NULL,
  anio_fabricacion   SMALLINT NULL,
  capacidad_kg       INT NULL,
  capacidad_personas INT NULL,
  numero_paradas     INT NULL,
  recorrido_m        DECIMAL(8,2) NULL,
  velocidad_ms       DECIMAL(5,2) NULL,
  profundidad_foso_mm INT NULL,
  fecha_puesta_marcha DATE NULL,
  estado             ENUM('ACTIVO','FUERA_SERVICIO','INACTIVO') NOT NULL DEFAULT 'ACTIVO',
  fecha_registro     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_modificacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_equipo_edificio (id_edificio, identificacion),
  CONSTRAINT fk_equipo_edificio FOREIGN KEY (id_edificio) REFERENCES edificio(id_edificio),
  INDEX ix_equipo_edificio (id_edificio)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. Variantes del equipo (tracción / hidráulico, enhebrado, máquina...)
--    Catálogo configurable; el inspector las elige al abrir el informe
--    y filtran qué ítems del checklist aplican.
-- ---------------------------------------------------------------------
CREATE TABLE variante_tipo (
  id_variante_tipo INT AUTO_INCREMENT PRIMARY KEY,
  codigo           VARCHAR(40)  NOT NULL UNIQUE COMMENT 'ACCIONAMIENTO, SUSPENSION, MAQUINA, CUARTO_MAQUINAS...',
  nombre           VARCHAR(100) NOT NULL,
  obligatoria      TINYINT(1) NOT NULL DEFAULT 1,
  orden            INT NOT NULL DEFAULT 0,
  activo           TINYINT(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB;

CREATE TABLE variante_opcion (
  id_variante_opcion INT AUTO_INCREMENT PRIMARY KEY,
  id_variante_tipo   INT NOT NULL,
  codigo             VARCHAR(40)  NOT NULL,
  nombre             VARCHAR(100) NOT NULL,
  orden              INT NOT NULL DEFAULT 0,
  activo             TINYINT(1) NOT NULL DEFAULT 1,
  UNIQUE KEY uq_opcion (id_variante_tipo, codigo),
  CONSTRAINT fk_opcion_tipo FOREIGN KEY (id_variante_tipo) REFERENCES variante_tipo(id_variante_tipo)
) ENGINE=InnoDB;

-- Últimas variantes conocidas del equipo (precargan la siguiente inspección)
CREATE TABLE equipo_variante (
  id_equipo          INT NOT NULL,
  id_variante_tipo   INT NOT NULL,
  id_variante_opcion INT NOT NULL,
  PRIMARY KEY (id_equipo, id_variante_tipo),
  CONSTRAINT fk_eqvar_equipo FOREIGN KEY (id_equipo) REFERENCES equipo(id_equipo) ON DELETE CASCADE,
  CONSTRAINT fk_eqvar_tipo   FOREIGN KEY (id_variante_tipo) REFERENCES variante_tipo(id_variante_tipo),
  CONSTRAINT fk_eqvar_opcion FOREIGN KEY (id_variante_opcion) REFERENCES variante_opcion(id_variante_opcion)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. Numeración consecutiva (COT, INS, INF, CER)
-- ---------------------------------------------------------------------
CREATE TABLE consecutivo (
  prefijo       VARCHAR(10) NOT NULL,
  anio          SMALLINT    NOT NULL,
  ultimo_numero INT NOT NULL DEFAULT 0,
  PRIMARY KEY (prefijo, anio)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. Cotizaciones
-- ---------------------------------------------------------------------
CREATE TABLE cotizacion (
  id_cotizacion            INT AUTO_INCREMENT PRIMARY KEY,
  numero_cotizacion        VARCHAR(20) NOT NULL UNIQUE COMMENT 'COT-2026-0001',
  id_cliente               INT NOT NULL,
  id_edificio              INT NOT NULL,
  id_asesor                INT NOT NULL,
  fecha_cotizacion         DATE NOT NULL,
  dias_validez             INT NOT NULL DEFAULT 30,
  subtotal                 DECIMAL(14,2) NOT NULL DEFAULT 0,
  iva_porcentaje           DECIMAL(5,2)  NOT NULL DEFAULT 19.00,
  iva_valor                DECIMAL(14,2) NOT NULL DEFAULT 0,
  total                    DECIMAL(14,2) NOT NULL DEFAULT 0,
  estado                   ENUM('BORRADOR','ENVIADA_CLIENTE','APROBADA_CLIENTE','RECHAZADA_CLIENTE','ENVIADA_PROGRAMACION','EN_EJECUCION','FINALIZADA','ANULADA') NOT NULL DEFAULT 'BORRADOR',
  condiciones              TEXT NULL,
  observaciones            TEXT NULL,
  fecha_envio_cliente      DATETIME NULL,
  fecha_respuesta_cliente  DATETIME NULL,
  id_usuario_respuesta     INT NULL COMMENT 'Usuario cliente que aprobó / rechazó',
  comentario_cliente       TEXT NULL,
  fecha_envio_programacion DATETIME NULL COMMENT 'Asesor acepta y envía a programación',
  ruta_pdf                 VARCHAR(500) NULL,
  fecha_creacion           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_modificacion       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_cot_cliente   FOREIGN KEY (id_cliente)  REFERENCES cliente(id_cliente),
  CONSTRAINT fk_cot_edificio  FOREIGN KEY (id_edificio) REFERENCES edificio(id_edificio),
  CONSTRAINT fk_cot_asesor    FOREIGN KEY (id_asesor)   REFERENCES usuario(id_usuario),
  CONSTRAINT fk_cot_respuesta FOREIGN KEY (id_usuario_respuesta) REFERENCES usuario(id_usuario),
  INDEX ix_cot_cliente (id_cliente),
  INDEX ix_cot_asesor (id_asesor),
  INDEX ix_cot_estado (estado)
) ENGINE=InnoDB;

-- Un renglón por equipo cotizado. Aquí vive el ESTADO POR EQUIPO que ve el cliente.
CREATE TABLE cotizacion_equipo (
  id_cotizacion_equipo INT AUTO_INCREMENT PRIMARY KEY,
  id_cotizacion        INT NOT NULL,
  id_equipo            INT NOT NULL,
  codigo_servicio      VARCHAR(25) NOT NULL UNIQUE COMMENT 'COT-2026-0001-01',
  tipo_servicio        ENUM('INSPECCION_INICIAL','INSPECCION_PERIODICA','REINSPECCION','EXTRAORDINARIA') NOT NULL DEFAULT 'INSPECCION_PERIODICA',
  descripcion          VARCHAR(255) NULL,
  valor                DECIMAL(14,2) NOT NULL,
  estado               ENUM(
                         'PENDIENTE_APROBACION',  -- cotización enviada al cliente
                         'APROBADO_CLIENTE',      -- cliente aprobó, falta que el asesor la pase
                         'POR_PROGRAMAR',         -- en bandeja de programación
                         'PROGRAMADO',            -- fecha, hora e inspector asignados
                         'EN_INSPECCION',         -- inspector abrió el informe
                         'EN_REVISION',           -- inspector finalizó, lo revisa el director técnico
                         'NO_CONFORME',           -- informe aprobado con defectos: el cliente/asesor solicita la 2ª visita
                         'SEGUNDA_VISITA_SOLICITADA', -- solicitada: en bandeja de programación
                         'INFORME_APROBADO',      -- informe conforme, visible al cliente; en certificados
                         'CERTIFICADO_LISTO',     -- certificado disponible para descarga
                         'RECHAZADO',
                         'ANULADO'
                       ) NOT NULL DEFAULT 'PENDIENTE_APROBACION',
  fecha_estado         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  plazo_dias           INT NULL COMMENT 'Días para corregir y hacer la 2ª visita (según hallazgos)',
  fecha_limite_correccion DATE NULL,
  fecha_solicitud_visita2 DATETIME NULL,
  id_usuario_solicitud_visita2 INT NULL,
  UNIQUE KEY uq_cot_equipo (id_cotizacion, id_equipo),
  CONSTRAINT fk_coteq_cotizacion FOREIGN KEY (id_cotizacion) REFERENCES cotizacion(id_cotizacion) ON DELETE CASCADE,
  CONSTRAINT fk_coteq_equipo     FOREIGN KEY (id_equipo)     REFERENCES equipo(id_equipo),
  CONSTRAINT fk_coteq_solicita   FOREIGN KEY (id_usuario_solicitud_visita2) REFERENCES usuario(id_usuario),
  INDEX ix_coteq_estado (estado)
) ENGINE=InnoDB;

-- Línea de tiempo por equipo (trazabilidad completa)
CREATE TABLE historial_estado (
  id_historial         BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_cotizacion_equipo INT NOT NULL,
  estado_anterior      VARCHAR(30) NULL,
  estado_nuevo         VARCHAR(30) NOT NULL,
  id_usuario           INT NULL,
  comentario           VARCHAR(500) NULL,
  fecha                TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_hist_coteq   FOREIGN KEY (id_cotizacion_equipo) REFERENCES cotizacion_equipo(id_cotizacion_equipo) ON DELETE CASCADE,
  CONSTRAINT fk_hist_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE SET NULL,
  INDEX ix_hist_coteq (id_cotizacion_equipo, fecha)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. Programación
-- ---------------------------------------------------------------------
CREATE TABLE programacion (
  id_programacion    INT AUTO_INCREMENT PRIMARY KEY,
  id_cotizacion      INT NOT NULL,
  id_inspector       INT NOT NULL,
  id_programador     INT NOT NULL,
  tipo_visita        ENUM('PRIMERA','SEGUNDA') NOT NULL DEFAULT 'PRIMERA' COMMENT 'SEGUNDA = cierre de hallazgos',
  fecha_programada   DATE NOT NULL,
  hora_inicio        TIME NOT NULL,
  hora_fin_estimada  TIME NULL,
  estado             ENUM('PROGRAMADA','REPROGRAMADA','EN_CURSO','REALIZADA','CANCELADA') NOT NULL DEFAULT 'PROGRAMADA',
  observaciones      VARCHAR(500) NULL,
  motivo_cambio      VARCHAR(255) NULL,
  fecha_creacion     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_modificacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_prog_cotizacion FOREIGN KEY (id_cotizacion)  REFERENCES cotizacion(id_cotizacion),
  CONSTRAINT fk_prog_inspector  FOREIGN KEY (id_inspector)   REFERENCES usuario(id_usuario),
  CONSTRAINT fk_prog_programador FOREIGN KEY (id_programador) REFERENCES usuario(id_usuario),
  INDEX ix_prog_inspector_fecha (id_inspector, fecha_programada),
  INDEX ix_prog_cotizacion (id_cotizacion)
) ENGINE=InnoDB;

-- Equipos que cubre una visita (una visita puede incluir varios equipos del edificio)
CREATE TABLE programacion_equipo (
  id_programacion      INT NOT NULL,
  id_cotizacion_equipo INT NOT NULL,
  PRIMARY KEY (id_programacion, id_cotizacion_equipo),
  CONSTRAINT fk_progeq_prog  FOREIGN KEY (id_programacion)      REFERENCES programacion(id_programacion) ON DELETE CASCADE,
  CONSTRAINT fk_progeq_coteq FOREIGN KEY (id_cotizacion_equipo) REFERENCES cotizacion_equipo(id_cotizacion_equipo)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. Checklist NTC 5926-1 (catálogo)
-- ---------------------------------------------------------------------
CREATE TABLE checklist_categoria (
  id_categoria   INT AUTO_INCREMENT PRIMARY KEY,
  codigo         VARCHAR(20)  NOT NULL UNIQUE,
  nombre         VARCHAR(150) NOT NULL COMMENT 'Cuarto de máquinas, Cabina, Foso, Hueco, Puertas...',
  descripcion    VARCHAR(500) NULL,
  norma          VARCHAR(40)  NOT NULL DEFAULT 'NTC 5926-1',
  numeral_norma  VARCHAR(40)  NULL,
  orden          INT NOT NULL DEFAULT 0,
  activo         TINYINT(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB;

CREATE TABLE checklist_item (
  id_item               INT AUTO_INCREMENT PRIMARY KEY,
  id_categoria          INT NOT NULL,
  numero                INT NOT NULL UNIQUE COMMENT 'Número de ítem en el informe (1..169)',
  codigo                VARCHAR(20) NOT NULL UNIQUE COMMENT 'Ej: IT-001',
  numeral_norma         VARCHAR(40) NULL,
  descripcion           TEXT NOT NULL COMMENT 'Redactado como defecto: se marca NO CUMPLE si se presenta',
  criterio_cumplimiento TEXT NULL,
  calificacion          ENUM('LEVE','GRAVE','MUY_GRAVE') NOT NULL COMMENT 'Calificación del defecto (numeral 6 NTC 5926-1): L, G, MG',
  requiere_medicion     TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Obligación de medida, sin estimaciones',
  requiere_foto_medicion TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Va en la hoja de evidencia fotográfica de equipos de medición',
  plazo_dias            INT NULL COMMENT 'Plazo propio de corrección; si es NULL se usa el de su calificación (parámetros)',
  unidad_medida         VARCHAR(20) NULL COMMENT 'mm, lux, m/s, kg, V...',
  obligatorio           TINYINT(1) NOT NULL DEFAULT 1,
  orden                 INT NOT NULL DEFAULT 0,
  activo                TINYINT(1) NOT NULL DEFAULT 1,
  CONSTRAINT fk_item_categoria FOREIGN KEY (id_categoria) REFERENCES checklist_categoria(id_categoria),
  INDEX ix_item_categoria (id_categoria, orden)
) ENGINE=InnoDB;

-- Reglas de "aplica" por variante. Sin filas = el ítem aplica a todos los equipos.
-- Con filas: para cada tipo de variante presente, la opción elegida en la
-- inspección debe estar entre las opciones listadas (O dentro del mismo tipo,
-- Y entre tipos distintos). Si no se cumple, el ítem se precarga como NO_APLICA;
-- el inspector siempre puede cambiarlo.
CREATE TABLE checklist_item_variante (
  id_item            INT NOT NULL,
  id_variante_opcion INT NOT NULL,
  PRIMARY KEY (id_item, id_variante_opcion),
  CONSTRAINT fk_itemvar_item   FOREIGN KEY (id_item) REFERENCES checklist_item(id_item) ON DELETE CASCADE,
  CONSTRAINT fk_itemvar_opcion FOREIGN KEY (id_variante_opcion) REFERENCES variante_opcion(id_variante_opcion)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 8. Inspección (app móvil del inspector)
-- ---------------------------------------------------------------------
CREATE TABLE inspeccion (
  id_inspeccion        INT AUTO_INCREMENT PRIMARY KEY,
  numero_inspeccion    VARCHAR(20) NOT NULL UNIQUE COMMENT 'INS-2026-0001',
  id_cotizacion_equipo INT NOT NULL,
  id_programacion      INT NOT NULL,
  id_inspector         INT NOT NULL,
  uuid_offline         CHAR(36) NULL UNIQUE COMMENT 'Generado en el celular para sincronizar sin duplicar',
  datos_equipo_json    LONGTEXT NULL COMMENT 'Copia de cliente/edificio/equipo al abrir el informe' CHECK (datos_equipo_json IS NULL OR JSON_VALID(datos_equipo_json)),
  -- Encabezado del informe
  conservacion_informacion ENUM('FISICO','DIGITAL') NOT NULL DEFAULT 'DIGITAL',
  tipo_acrilico        VARCHAR(80)  NULL COMMENT 'Tipo de acrílico de certificación',
  empresa_mantenimiento VARCHAR(150) NULL,
  tecnico_mantenimiento VARCHAR(150) NULL,
  fecha_ultimo_mantenimiento DATE NULL,
  fecha_puesta_marcha  DATE NULL COMMENT 'NI = no informa -> NULL',
  fecha_ultima_inspeccion DATE NULL,
  -- Características técnicas medidas / declaradas en la visita
  capacidad_kg         INT NULL,
  capacidad_personas   INT NULL,
  numero_paradas       INT NULL,
  profundidad_foso_mm  INT NULL,
  recorrido_m          DECIMAL(8,2) NULL,
  -- Primera visita
  fecha_inicio         DATETIME NOT NULL,
  fecha_fin            DATETIME NULL,
  -- Segunda visita (cierre de hallazgos)
  id_programacion_visita2 INT NULL,
  id_inspector_visita2 INT NULL,
  fecha_visita2        DATETIME NULL,
  estado               ENUM('EN_CURSO','FINALIZADA','DEVUELTA','APROBADA','EN_SEGUNDA_VISITA','CERRADA') NOT NULL DEFAULT 'EN_CURSO',
  observaciones_generales TEXT NULL,
  latitud              DECIMAL(10,8) NULL,
  longitud             DECIMAL(11,8) NULL,
  sincronizada         TINYINT(1) NOT NULL DEFAULT 1,
  fecha_sincronizacion DATETIME NULL,
  fecha_creacion       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_modificacion   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_insp_coteq     FOREIGN KEY (id_cotizacion_equipo) REFERENCES cotizacion_equipo(id_cotizacion_equipo),
  CONSTRAINT fk_insp_prog      FOREIGN KEY (id_programacion)      REFERENCES programacion(id_programacion),
  CONSTRAINT fk_insp_inspector FOREIGN KEY (id_inspector)         REFERENCES usuario(id_usuario),
  CONSTRAINT fk_insp_prog2     FOREIGN KEY (id_programacion_visita2) REFERENCES programacion(id_programacion),
  CONSTRAINT fk_insp_inspector2 FOREIGN KEY (id_inspector_visita2)  REFERENCES usuario(id_usuario),
  INDEX ix_insp_coteq (id_cotizacion_equipo),
  INDEX ix_insp_inspector (id_inspector, estado)
) ENGINE=InnoDB;

-- Variantes elegidas por el inspector al abrir el informe
CREATE TABLE inspeccion_variante (
  id_inspeccion      INT NOT NULL,
  id_variante_tipo   INT NOT NULL,
  id_variante_opcion INT NOT NULL,
  PRIMARY KEY (id_inspeccion, id_variante_tipo),
  CONSTRAINT fk_inspvar_insp   FOREIGN KEY (id_inspeccion) REFERENCES inspeccion(id_inspeccion) ON DELETE CASCADE,
  CONSTRAINT fk_inspvar_tipo   FOREIGN KEY (id_variante_tipo) REFERENCES variante_tipo(id_variante_tipo),
  CONSTRAINT fk_inspvar_opcion FOREIGN KEY (id_variante_opcion) REFERENCES variante_opcion(id_variante_opcion)
) ENGINE=InnoDB;

-- Resultado de cada ítem del checklist
CREATE TABLE inspeccion_resultado (
  id_resultado        INT AUTO_INCREMENT PRIMARY KEY,
  id_inspeccion       INT NOT NULL,
  id_item             INT NOT NULL,
  resultado           ENUM('CUMPLE','NO_CUMPLE','NO_APLICA','NO_VERIFICADO') NOT NULL,
  calificacion_defecto ENUM('LEVE','GRAVE','MUY_GRAVE') NULL COMMENT 'Copia de checklist_item.calificacion cuando NO_CUMPLE',
  no_aplica_automatico TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Precargado por las variantes del equipo',
  valor_medido        VARCHAR(50) NULL,
  unidad_medida       VARCHAR(20) NULL,
  observacion         TEXT NULL,
  hallazgo_director   TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Hallazgo adicional identificado en la atestación',
  estado_segunda_visita ENUM('CORREGIDO','NO_CORREGIDO') NULL,
  observacion_segunda_visita TEXT NULL,
  fecha_registro      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_modificacion  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_resultado (id_inspeccion, id_item),
  CONSTRAINT fk_res_insp FOREIGN KEY (id_inspeccion) REFERENCES inspeccion(id_inspeccion) ON DELETE CASCADE,
  CONSTRAINT fk_res_item FOREIGN KEY (id_item)       REFERENCES checklist_item(id_item)
) ENGINE=InnoDB;

-- Álbum de fotos (~100 por equipo). Se guarda la ruta del archivo, no la imagen.
CREATE TABLE inspeccion_foto (
  id_foto         INT AUTO_INCREMENT PRIMARY KEY,
  id_inspeccion   INT NOT NULL,
  id_resultado    INT NULL COMMENT 'Opcional: foto asociada a un hallazgo',
  uuid_offline    CHAR(36) NULL UNIQUE,
  nombre_archivo  VARCHAR(255) NOT NULL,
  ruta_archivo    VARCHAR(500) NOT NULL,
  ruta_miniatura  VARCHAR(500) NULL,
  tamano_kb       INT NULL,
  descripcion     VARCHAR(300) NULL,
  orden           INT NOT NULL DEFAULT 0,
  incluir_en_informe TINYINT(1) NOT NULL DEFAULT 1 COMMENT 'El director puede excluirla del PDF',
  revisada        TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Revisada por el director técnico',
  fecha_captura   DATETIME NULL,
  latitud         DECIMAL(10,8) NULL,
  longitud        DECIMAL(11,8) NULL,
  fecha_subida    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_foto_insp      FOREIGN KEY (id_inspeccion) REFERENCES inspeccion(id_inspeccion) ON DELETE CASCADE,
  CONSTRAINT fk_foto_resultado FOREIGN KEY (id_resultado)  REFERENCES inspeccion_resultado(id_resultado) ON DELETE SET NULL,
  INDEX ix_foto_insp (id_inspeccion, orden)
) ENGINE=InnoDB;

-- Firmas al finalizar: inspector, técnico de mantenimiento y representante del edificio
CREATE TABLE inspeccion_firma (
  id_firma       INT AUTO_INCREMENT PRIMARY KEY,
  id_inspeccion  INT NOT NULL,
  numero_visita  TINYINT NOT NULL DEFAULT 1 COMMENT '1 = primera visita, 2 = cierre de hallazgos',
  tipo_firmante  ENUM('INSPECTOR','TECNICO_MANTENIMIENTO','REPRESENTANTE_EDIFICIO') NOT NULL,
  id_usuario     INT NULL COMMENT 'Si el firmante es usuario del sistema (inspector)',
  nombre         VARCHAR(150) NOT NULL,
  documento      VARCHAR(30)  NULL,
  cargo          VARCHAR(100) NULL,
  empresa        VARCHAR(150) NULL COMMENT 'Empresa de mantenimiento del técnico',
  ruta_firma     VARCHAR(500) NOT NULL COMMENT 'PNG de la firma',
  fecha_firma    DATETIME NOT NULL,
  UNIQUE KEY uq_firma (id_inspeccion, numero_visita, tipo_firmante),
  CONSTRAINT fk_firma_insp    FOREIGN KEY (id_inspeccion) REFERENCES inspeccion(id_inspeccion) ON DELETE CASCADE,
  CONSTRAINT fk_firma_usuario FOREIGN KEY (id_usuario)    REFERENCES usuario(id_usuario) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Instrumentos de medición (luxómetro, tacómetro, flexómetro...) asignados a cada inspector
CREATE TABLE instrumento_medicion (
  id_instrumento    INT AUTO_INCREMENT PRIMARY KEY,
  codigo            VARCHAR(30) NOT NULL UNIQUE COMMENT 'Código interno, ej. LX07',
  tipo              ENUM('LUXOMETRO','TACOMETRO','FLEXOMETRO','ESCALA_PLANA','ESCALA_PUNTA','PIE_DE_REY','MEDIDOR_ANGULO','PINZA_AMPERIMETRICA','DINAMOMETRO','OTRO') NOT NULL,
  marca             VARCHAR(80) NULL,
  serial            VARCHAR(80) NULL,
  id_inspector      INT NULL COMMENT 'Inspector que lo tiene asignado',
  fecha_calibracion DATE NULL,
  vence_calibracion DATE NULL,
  estado            ENUM('ACTIVO','EN_CALIBRACION','INACTIVO') NOT NULL DEFAULT 'ACTIVO',
  CONSTRAINT fk_instr_inspector FOREIGN KEY (id_inspector) REFERENCES usuario(id_usuario) ON DELETE SET NULL,
  INDEX ix_instr_inspector (id_inspector)
) ENGINE=InnoDB;

-- Instrumentos usados en la inspección (se precargan con los del inspector)
CREATE TABLE inspeccion_instrumento (
  id_inspeccion  INT NOT NULL,
  id_instrumento INT NOT NULL,
  PRIMARY KEY (id_inspeccion, id_instrumento),
  CONSTRAINT fk_inspinst_insp  FOREIGN KEY (id_inspeccion)  REFERENCES inspeccion(id_inspeccion) ON DELETE CASCADE,
  CONSTRAINT fk_inspinst_instr FOREIGN KEY (id_instrumento) REFERENCES instrumento_medicion(id_instrumento)
) ENGINE=InnoDB;

-- Mediciones calculadas (ej. factor de deslizamiento con enhebrado y recorrido)
CREATE TABLE inspeccion_medicion (
  id_medicion    INT AUTO_INCREMENT PRIMARY KEY,
  id_inspeccion  INT NOT NULL,
  id_item        INT NULL,
  concepto       VARCHAR(80) NOT NULL COMMENT 'DESLIZAMIENTO, RECORRIDO, DIAMETRO_CABLE, DESGASTE_ZAPATA...',
  valor          DECIMAL(12,4) NULL,
  unidad         VARCHAR(20) NULL,
  resultado      ENUM('CUMPLE','NO_CUMPLE') NULL,
  detalle        VARCHAR(255) NULL,
  CONSTRAINT fk_med_insp FOREIGN KEY (id_inspeccion) REFERENCES inspeccion(id_inspeccion) ON DELETE CASCADE,
  CONSTRAINT fk_med_item FOREIGN KEY (id_item) REFERENCES checklist_item(id_item),
  INDEX ix_med_insp (id_inspeccion)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 9. Informe (revisión y atestación del director técnico)
-- ---------------------------------------------------------------------
CREATE TABLE informe (
  id_informe            INT AUTO_INCREMENT PRIMARY KEY,
  numero_informe        VARCHAR(20) NOT NULL UNIQUE COMMENT 'INF-2026-0001',
  id_inspeccion         INT NOT NULL UNIQUE,
  id_director           INT NULL,
  estado                ENUM('PENDIENTE_REVISION','DEVUELTO','APROBADO','ANULADO') NOT NULL DEFAULT 'PENDIENTE_REVISION',
  concepto              ENUM('CONFORME','NO_CONFORME') NULL,
  atestacion            TEXT NULL COMMENT 'Texto de atestación del director técnico',
  observaciones_revision TEXT NULL COMMENT 'Motivo de devolución o comentarios',
  ruta_firma_director   VARCHAR(500) NULL,
  visita_actual         TINYINT NOT NULL DEFAULT 1 COMMENT '1 = primera visita, 2 = cierre de hallazgos',
  concepto_visita1      ENUM('CONFORME','NO_CONFORME') NULL,
  fecha_aprobacion_visita1 DATETIME NULL,
  ruta_pdf_visita1      VARCHAR(500) NULL COMMENT 'Informe de primera visita (se conserva al emitir el de segunda)',
  hash_visita1          CHAR(64) NULL,
  ruta_firma_director_v1 VARCHAR(500) NULL,
  plazo_dias            INT NULL COMMENT 'Plazo de corrección cuando es NO CONFORME',
  fecha_limite_correccion DATE NULL,
  total_corregidos      INT NOT NULL DEFAULT 0 COMMENT 'Segunda visita',
  total_no_corregidos   INT NOT NULL DEFAULT 0,
  total_leves           INT NOT NULL DEFAULT 0 COMMENT 'Resumen de hallazgos, congelado al aprobar',
  total_graves          INT NOT NULL DEFAULT 0,
  total_muy_graves      INT NOT NULL DEFAULT 0,
  total_no_aplica       INT NOT NULL DEFAULT 0,
  fecha_revision        DATETIME NULL,
  fecha_aprobacion      DATETIME NULL,
  ruta_pdf              VARCHAR(500) NULL,
  hash_sha256           CHAR(64) NULL,
  fecha_envio_cliente   DATETIME NULL,
  fecha_envio_certificados DATETIME NULL,
  fecha_creacion        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_inf_insp     FOREIGN KEY (id_inspeccion) REFERENCES inspeccion(id_inspeccion),
  CONSTRAINT fk_inf_director FOREIGN KEY (id_director)   REFERENCES usuario(id_usuario),
  INDEX ix_inf_estado (estado)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 10. Certificado
-- ---------------------------------------------------------------------
CREATE TABLE certificado (
  id_certificado       INT AUTO_INCREMENT PRIMARY KEY,
  numero_certificado   VARCHAR(20) NOT NULL UNIQUE COMMENT 'CER-2026-0001',
  id_informe           INT NOT NULL UNIQUE,
  id_cotizacion_equipo INT NOT NULL,
  id_emisor            INT NULL COMMENT 'Usuario rol CERTIFICADOS',
  estado               ENUM('EN_ELABORACION','EMITIDO','ENVIADO_CLIENTE','ANULADO') NOT NULL DEFAULT 'EN_ELABORACION',
  fecha_emision        DATE NULL,
  fecha_vencimiento    DATE NULL,
  codigo_verificacion  VARCHAR(40) NULL UNIQUE COMMENT 'Para el QR de verificación',
  ruta_pdf             VARCHAR(500) NULL,
  hash_sha256          CHAR(64) NULL,
  fecha_envio_cliente  DATETIME NULL,
  motivo_anulacion     VARCHAR(255) NULL,
  fecha_creacion       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_cert_informe FOREIGN KEY (id_informe)           REFERENCES informe(id_informe),
  CONSTRAINT fk_cert_coteq   FOREIGN KEY (id_cotizacion_equipo) REFERENCES cotizacion_equipo(id_cotizacion_equipo),
  CONSTRAINT fk_cert_emisor  FOREIGN KEY (id_emisor)            REFERENCES usuario(id_usuario),
  INDEX ix_cert_vencimiento (fecha_vencimiento)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 11. Parámetros de la empresa (nombre, código de formato, texto de atestación...)
-- ---------------------------------------------------------------------
CREATE TABLE parametro (
  clave        VARCHAR(60) PRIMARY KEY,
  valor        TEXT NOT NULL,
  descripcion  VARCHAR(255) NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 12. Notificaciones y auditoría
-- ---------------------------------------------------------------------
CREATE TABLE notificacion (
  id_notificacion   INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario_destino INT NOT NULL,
  titulo            VARCHAR(120) NOT NULL,
  mensaje           VARCHAR(500) NOT NULL,
  tipo              VARCHAR(40)  NULL COMMENT 'COTIZACION, PROGRAMACION, INFORME, CERTIFICADO',
  id_referencia     INT NULL,
  enlace            VARCHAR(255) NULL COMMENT 'Ruta de la app',
  leida             TINYINT(1) NOT NULL DEFAULT 0,
  fecha_creacion    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_notif_usuario FOREIGN KEY (id_usuario_destino) REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  INDEX ix_notif_usuario (id_usuario_destino, leida)
) ENGINE=InnoDB;

CREATE TABLE auditoria (
  id_auditoria     BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_usuario       INT NULL,
  tabla_afectada   VARCHAR(50) NOT NULL,
  operacion        VARCHAR(20) NOT NULL,
  id_registro      INT NULL,
  datos_anteriores LONGTEXT NULL CHECK (datos_anteriores IS NULL OR JSON_VALID(datos_anteriores)),
  datos_nuevos     LONGTEXT NULL CHECK (datos_nuevos IS NULL OR JSON_VALID(datos_nuevos)),
  ip_origen        VARCHAR(45) NULL,
  fecha_evento     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_aud_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE SET NULL,
  INDEX ix_aud_tabla (tabla_afectada, id_registro)
) ENGINE=InnoDB;

SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 13. Vista de seguimiento: filtrar todo por número de cotización
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_seguimiento_equipo AS
SELECT
  c.numero_cotizacion,
  c.estado               AS estado_cotizacion,
  ce.codigo_servicio,
  ce.estado              AS estado_equipo,
  ce.fecha_estado,
  ce.plazo_dias,
  ce.fecha_limite_correccion,
  cl.id_cliente,
  cl.razon_social        AS cliente,
  ed.id_edificio,
  ed.nombre              AS edificio,
  eq.id_equipo,
  eq.identificacion      AS equipo,
  ase.nombre_completo    AS asesor,
  p.tipo_visita,
  p.fecha_programada,
  p.hora_inicio,
  ins.nombre_completo    AS inspector,
  i.numero_inspeccion,
  i.estado               AS estado_inspeccion,
  inf.numero_informe,
  inf.estado             AS estado_informe,
  inf.concepto,
  inf.ruta_pdf           AS pdf_informe,
  cer.numero_certificado,
  cer.estado             AS estado_certificado,
  cer.fecha_vencimiento,
  cer.ruta_pdf           AS pdf_certificado
FROM cotizacion_equipo ce
JOIN cotizacion c   ON c.id_cotizacion = ce.id_cotizacion
JOIN cliente cl     ON cl.id_cliente   = c.id_cliente
JOIN edificio ed    ON ed.id_edificio  = c.id_edificio
JOIN equipo eq      ON eq.id_equipo    = ce.id_equipo
JOIN usuario ase    ON ase.id_usuario  = c.id_asesor
LEFT JOIN inspeccion i ON i.id_inspeccion = (
       SELECT MAX(i2.id_inspeccion) FROM inspeccion i2
       WHERE i2.id_cotizacion_equipo = ce.id_cotizacion_equipo)
LEFT JOIN programacion p ON p.id_programacion = (
       SELECT MAX(pe.id_programacion) FROM programacion_equipo pe
       JOIN programacion p2 ON p2.id_programacion = pe.id_programacion AND p2.estado <> 'CANCELADA'
       WHERE pe.id_cotizacion_equipo = ce.id_cotizacion_equipo)
LEFT JOIN usuario ins    ON ins.id_usuario = p.id_inspector
LEFT JOIN informe inf    ON inf.id_inspeccion = i.id_inspeccion
LEFT JOIN certificado cer ON cer.id_informe = inf.id_informe;

-- ---------------------------------------------------------------------
-- 14. Ítems que aplican a cada inspección según sus variantes
--     aplica = 0 -> se precarga como NO_APLICA (el inspector puede cambiarlo)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_inspeccion_item_aplica AS
SELECT
  ins.id_inspeccion,
  i.id_item,
  i.numero,
  CASE WHEN EXISTS (
    SELECT 1
    FROM checklist_item_variante v
    JOIN variante_opcion o ON o.id_variante_opcion = v.id_variante_opcion
    WHERE v.id_item = i.id_item
      AND NOT EXISTS (
        SELECT 1
        FROM checklist_item_variante v2
        JOIN variante_opcion o2 ON o2.id_variante_opcion = v2.id_variante_opcion
        JOIN inspeccion_variante iv ON iv.id_variante_opcion = v2.id_variante_opcion
                                   AND iv.id_inspeccion = ins.id_inspeccion
        WHERE v2.id_item = i.id_item
          AND o2.id_variante_tipo = o.id_variante_tipo)
  ) THEN 0 ELSE 1 END AS aplica
FROM inspeccion ins
CROSS JOIN checklist_item i
WHERE i.activo = 1;
