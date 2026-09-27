-- ServiLift - Migración 2026-09-26 (2): informe de 1ª y 2ª visita por separado y plazos de la plantilla
USE servilift_db;
ALTER TABLE informe
  ADD COLUMN ruta_pdf_visita1 VARCHAR(500) NULL AFTER fecha_aprobacion_visita1,
  ADD COLUMN hash_visita1 CHAR(64) NULL AFTER ruta_pdf_visita1,
  ADD COLUMN ruta_firma_director_v1 VARCHAR(500) NULL AFTER hash_visita1;
-- Informes ya aprobados en 1ª visita: su PDF actual es el de 1ª visita
UPDATE informe SET ruta_pdf_visita1 = ruta_pdf, hash_visita1 = hash_sha256, ruta_firma_director_v1 = ruta_firma_director
 WHERE ruta_pdf IS NOT NULL AND visita_actual = 1;
-- Plazos de la plantilla: leve 180 días, grave 30 días, muy grave inmediato
UPDATE parametro SET valor = '180' WHERE clave = 'PLAZO_DIAS_LEVE';
UPDATE parametro SET valor = '30'  WHERE clave = 'PLAZO_DIAS_GRAVE';
UPDATE parametro SET valor = '0'   WHERE clave = 'PLAZO_DIAS_MUY_GRAVE';
