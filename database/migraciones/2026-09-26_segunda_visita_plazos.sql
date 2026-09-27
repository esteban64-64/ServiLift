-- ServiLift - Migración 2026-09-26: solicitud de segunda visita y plazos de corrección
USE servilift_db;
ALTER TABLE cotizacion_equipo MODIFY estado ENUM('PENDIENTE_APROBACION','APROBADO_CLIENTE','POR_PROGRAMAR','PROGRAMADO',
  'EN_INSPECCION','EN_REVISION','NO_CONFORME','SEGUNDA_VISITA_SOLICITADA','INFORME_APROBADO','CERTIFICADO_LISTO',
  'RECHAZADO','ANULADO') NOT NULL DEFAULT 'PENDIENTE_APROBACION';
ALTER TABLE cotizacion_equipo
  ADD COLUMN plazo_dias INT NULL AFTER fecha_estado,
  ADD COLUMN fecha_limite_correccion DATE NULL AFTER plazo_dias,
  ADD COLUMN fecha_solicitud_visita2 DATETIME NULL AFTER fecha_limite_correccion,
  ADD COLUMN id_usuario_solicitud_visita2 INT NULL AFTER fecha_solicitud_visita2,
  ADD CONSTRAINT fk_coteq_solicita FOREIGN KEY (id_usuario_solicitud_visita2) REFERENCES usuario(id_usuario);
ALTER TABLE checklist_item ADD COLUMN plazo_dias INT NULL AFTER requiere_foto_medicion;
ALTER TABLE informe
  ADD COLUMN plazo_dias INT NULL AFTER fecha_aprobacion_visita1,
  ADD COLUMN fecha_limite_correccion DATE NULL AFTER plazo_dias;
INSERT IGNORE INTO parametro (clave, valor, descripcion) VALUES
  ('PLAZO_DIAS_LEVE', '90', 'Días para corregir un defecto LEVE antes de la 2ª visita'),
  ('PLAZO_DIAS_GRAVE', '30', 'Días para corregir un defecto GRAVE antes de la 2ª visita'),
  ('PLAZO_DIAS_MUY_GRAVE', '15', 'Días para corregir un defecto MUY GRAVE antes de la 2ª visita');
-- recrear vista
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
