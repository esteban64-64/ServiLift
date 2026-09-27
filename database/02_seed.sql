-- =====================================================================
-- ServiLift - Datos iniciales
-- Checklist: 169 ítems del informe de inspección NTC 5926-1:2012
-- (tomados de la plantilla de ejemplo; calificación L / G / MG).
-- La agrupación por zonas y las reglas de 'no aplica' por variante son
-- propuestas de ServiLift y se pueden ajustar desde el catálogo.
-- =====================================================================
USE servilift_db;
SET NAMES utf8mb4;

INSERT INTO rol (codigo,nombre,descripcion) VALUES
('ADMIN','Administrador','Usuarios, catálogos, tarifas y auditoría'),
('ASESOR','Asesor','Registra clientes, edificios y equipos; crea y envía cotizaciones'),
('CLIENTE','Cliente','Aprueba cotizaciones y consulta estado, informes y certificados'),
('PROGRAMACION','Programación','Asigna fecha, hora e inspector a los equipos aprobados'),
('INSPECTOR','Inspector','Ejecuta la inspección en campo desde el celular'),
('DIRECTOR_TECNICO','Director técnico','Revisa, atesta, firma y aprueba informes'),
('CERTIFICADOS','Certificados','Elabora y envía certificados al cliente');

INSERT INTO consecutivo (prefijo,anio,ultimo_numero) VALUES ('COT',2026,0),('INS',2026,0),('INF',2026,0),('CER',2026,0);

INSERT INTO parametro (clave,valor,descripcion) VALUES
('EMPRESA_NOMBRE','ServiLift','Nombre que aparece en informes y certificados'),
('EMPRESA_NIT','','NIT de la empresa certificadora'),
('INFORME_TITULO','INFORME DE INSPECCIÓN DE ASCENSORES NTC 5926-1:2012',NULL),
('INFORME_CODIGO_FORMATO','','Código del formato en el sistema de calidad'),
('INFORME_VERSION_FORMATO','1',NULL),
('TEXTO_ATESTACION','El informe final refleja la declaración emitida por la dirección técnica, garantizando el cumplimiento de los requisitos del numeral 6, "Lista de defectos y su calificación", de la norma NTC 5926-1. La supervisión y atestación de los resultados puede incluir variaciones por hallazgos adicionales identificados en los registros fotográficos o en las listas de chequeo aportadas por los inspectores. Si se identifican, se incluyen en el informe final antes de su emisión o, de ser necesario, se reprograma una nueva inspección.','Texto de atestación del informe'),
('CONVENCION_RESULTADOS','C = Cumple · NC = No cumple · NA = No aplica',NULL),
('CERTIFICADO_VIGENCIA_MESES','12',NULL),
('PLAZO_DIAS_LEVE','180','Días para corregir un defecto LEVE antes de la 2ª visita'),
('PLAZO_DIAS_GRAVE','30','Días para corregir un defecto GRAVE antes de la 2ª visita'),
('PLAZO_DIAS_MUY_GRAVE','0','Días para corregir un defecto MUY GRAVE (0 = corrección inmediata)'),
('FOTOS_MAX_POR_EQUIPO','150',NULL);

INSERT INTO variante_tipo (id_variante_tipo,codigo,nombre,obligatoria,orden) VALUES
(1,'ACCIONAMIENTO','Tipo de accionamiento',1,1),
(2,'ENHEBRADO','Enhebrado',1,2),
(3,'MAQUINA','Tipo de máquina',1,3),
(4,'TRACCION_POR','Tracción por',1,4),
(5,'CUARTO_MAQUINAS','Cuarto de máquinas',1,5),
(6,'TIPO_BUFFER','Tipo de buffer',1,6),
(7,'LIMITADOR_CABINA','Limitador de cabina',1,7),
(8,'LIMITADOR_CONTRAPESO','Limitador de contrapeso',1,8),
(9,'CUARTO_POLEAS','Cuarto de poleas',1,9),
(10,'PUERTA_SOCORRO','Puerta escotilla o de socorro',1,10),
(11,'TIPO_PUERTA','Tipo de puerta de piso',1,11),
(12,'MIRILLA_PUERTAS','Mirilla de puertas',1,12);
INSERT INTO variante_opcion (id_variante_tipo,codigo,nombre,orden) VALUES
(1,'ELECTRICO','Eléctrico',1),
(1,'HIDRAULICO_DIRECTO','Hidráulico directo',2),
(1,'HIDRAULICO_INDIRECTO','Hidráulico indirecto',3),
(2,'1_1','1:1',1),
(2,'2_1','2:1',2),
(2,'4_1','4:1',3),
(2,'6_1','6:1',4),
(2,'NO_APLICA','No aplica / NI',5),
(3,'GEARLESS','Gearless (sin reductor)',1),
(3,'CON_REDUCTOR','Con reductor',2),
(3,'HIDRAULICO','Hidráulico',3),
(3,'NO_APLICA','No aplica / NI',4),
(4,'CABLE','Cable',1),
(4,'CINTA','Cinta',2),
(4,'NO_APLICA','No aplica / NI',3),
(5,'CON_CUARTO','Con cuarto',1),
(5,'SIN_CUARTO','Sin cuarto',2),
(5,'NO_APLICA','No aplica / NI',3),
(6,'HIDRAULICO','Hidráulico',1),
(6,'RESORTE_CAUCHO','Resorte o caucho',2),
(6,'MIXTO','Mixto',3),
(6,'NO_APLICA','No aplica / NI',4),
(7,'SI','Sí',1),
(7,'NO','No',2),
(8,'SI','Sí',1),
(8,'NO','No',2),
(9,'SI','Sí',1),
(9,'NO','No',2),
(10,'SI','Sí',1),
(10,'NO','No',2),
(11,'AUTOMATICA','Automática',1),
(11,'BATIENTE','Batiente',2),
(11,'PLEGABLE','Plegable / tijera',3),
(11,'NO_APLICA','No aplica / NI',4),
(12,'SI','Sí',1),
(12,'NO','No',2);

INSERT INTO checklist_categoria (id_categoria,codigo,nombre,norma,orden) VALUES
(1,'GEN','Generalidades, accesos y dispositivos de parada','NTC 5926-1',1),
(2,'FOS','Foso','NTC 5926-1',2),
(3,'CAB','Cabina','NTC 5926-1',3),
(4,'CMA','Cuarto de máquinas, poleas y puertas de socorro','NTC 5926-1',4),
(5,'ELE','Instalación eléctrica y cuadro de maniobra','NTC 5926-1',5),
(6,'TRA','Máquina de tracción y freno','NTC 5926-1',6),
(7,'LIM','Limitador de velocidad y paracaídas','NTC 5926-1',7),
(8,'TEC','Techo de cabina y finales de carrera','NTC 5926-1',8),
(9,'CAC','Cables de tracción, guías y contrapeso','NTC 5926-1',9),
(10,'PUE','Puertas de cabina y de piso','NTC 5926-1',10),
(11,'HUE','Hueco, cabina y equipos hidráulicos','NTC 5926-1',11);

INSERT INTO checklist_item (id_item,id_categoria,numero,codigo,descripcion,criterio_cumplimiento,calificacion,requiere_medicion,requiere_foto_medicion,orden) VALUES
(1,1,1,'IT-001','No existe empresa encargada del mantenimiento ni conservación del aparato, haciéndose constar de un registro de mantenimiento (contrato bitácora, reporte técnico, acta de mantenimiento, etc.).',NULL,'GRAVE',0,0,1),
(2,1,2,'IT-002','No existe llave de apertura en la edificación o no es accesible.',NULL,'GRAVE',0,0,2),
(3,1,3,'IT-003','La puerta de acceso se abre sin llave especial o no puede introducirse',NULL,'GRAVE',0,0,3),
(4,1,4,'IT-004','Cerraduras accesibles desde el exterior sin requerir herramienta para su apertura.',NULL,'MUY_GRAVE',0,0,4),
(5,1,5,'IT-005','Cerraduras se encuentran inoperantes',NULL,'MUY_GRAVE',0,0,5),
(6,1,6,'IT-006','Falta seguridad eléctrica (series) de puertas, o están puenteadas.',NULL,'MUY_GRAVE',0,0,6),
(7,1,7,'IT-007','El ascensor arranca con puerta abierta.',NULL,'MUY_GRAVE',0,0,7),
(8,1,8,'IT-008','Al halar o abrir la puerta, la cabina deberá detenerse.',NULL,'MUY_GRAVE',0,0,8),
(9,1,9,'IT-009','Falta o no funciona un interruptor accesible desde el piso, que permita parar o mantener parado el ascensor durante las operaciones de mantenimiento o inspección en el foso.',NULL,'GRAVE',0,0,9),
(10,1,10,'IT-010','No se puede actuar sobre los dispositivos eléctricos de seguridad de parada de emergencia y/o son accesibles.',NULL,'GRAVE',0,0,10),
(11,1,11,'IT-011','El dispositivo de parada (stop) no se desactiva de forma involuntaria.',NULL,'MUY_GRAVE',0,0,11),
(12,2,12,'IT-012','Foso con profundidad superior o igual a 1.50 mts sinr escalera. En caso de tener escalera, el primer peldaño no debe estar ubicado a más de 50 cm respecto al nivel de piso de la primera parada.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','LEVE',1,0,12),
(13,2,13,'IT-013','Encontrándose la cabina en la última parada (la más alta) el contrapeso se encuentra a una distancia ≤ de 15 cm con respecto al tope de sus amortiguadores (no es de aplicación en ascensores hidráulico o sin contrapeso).','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,13),
(14,2,14,'IT-014','Agua en el foso',NULL,'GRAVE',0,0,14),
(15,2,15,'IT-015','Amortiguadores oxidados, fisurados, sueltos.',NULL,'MUY_GRAVE',0,0,15),
(16,2,16,'IT-016','No existen topes elásticos, de resorte o hidráulicos para la cabina y contrapeso.',NULL,'MUY_GRAVE',0,0,16),
(17,2,17,'IT-017','En ascensores con hueco compartido, existe separación del hueco de cada ascensor en el foso.',NULL,'LEVE',0,0,17),
(18,2,18,'IT-018','En amortiguadores hidráulicos, el nivel de aceite esta por fuera de la marca.',NULL,'GRAVE',0,0,18),
(19,2,19,'IT-019','No tiene o no actúa el dispositivo eléctrico de seguridad en los amortiguadores hidráulicos.',NULL,'LEVE',0,0,19),
(20,2,20,'IT-020','No se recupera el amortiguador hidráulico luego de comprimirse.',NULL,'MUY_GRAVE',0,0,20),
(21,2,21,'IT-021','El dispositivo de parada (stop) funciona en cabinas sin puertas.',NULL,'MUY_GRAVE',0,0,21),
(22,2,22,'IT-022','No existe paracaídas en contrapeso habiendo circulación de personas bajo el foso.',NULL,'LEVE',0,0,22),
(23,2,23,'IT-023','El paracaídas de contrapeso no actúa (cuando aplica).',NULL,'MUY_GRAVE',0,0,23),
(24,3,24,'IT-024','No existen rejillas de ventilación en cabina.',NULL,'GRAVE',0,0,24),
(25,3,25,'IT-025','Paredes de la cabina rígidas. Para ascensores con cabina de construcción en madera, se presentan zonas podridas, mal fijadas o con síntomas de defecto.',NULL,'GRAVE',0,0,25),
(26,3,26,'IT-026','No lleva puertas en cabina (equipos antiguos que no tengan puerta en cabina, deben estar provistos de un Sensor de proximidad).',NULL,'GRAVE',0,0,26),
(27,3,27,'IT-027','Puertas de cabina retroceden frente a un obstáculo por contacto o proximidad.',NULL,'GRAVE',0,0,27),
(28,3,28,'IT-028','Guardaescoba o zócalo en mal estado(oxidado, suelto, deteriorado, roto)',NULL,'LEVE',0,0,28),
(29,3,29,'IT-029','No existe o no funciona el pulsador de apertura de puertas automáticas en botonera de cabina.',NULL,'GRAVE',0,0,29),
(30,3,30,'IT-030','Existe señalización de piso en cabina.',NULL,'LEVE',0,0,30),
(31,3,31,'IT-031','No existe placa que indique capacidad máxima de carga en cabina (kg y/o pasajeros).',NULL,'LEVE',0,0,31),
(32,3,32,'IT-032','No está independiente la acometida del ascensor y la acometida del alumbrado.',NULL,'LEVE',0,0,32),
(33,3,33,'IT-033','El equipo de alarma no es autónomo (es decir sin batería), inaudible o no funciona',NULL,'GRAVE',0,0,33),
(34,3,34,'IT-034','No existe o no funciona el intercomunicador.',NULL,'GRAVE',0,0,34),
(35,3,35,'IT-035','No funciona el sistema de re apertura (banda retráctil, foto celda, micro obstáculo, ultrasónico, etc.) de las puertas acceso.',NULL,'GRAVE',0,0,35),
(36,4,36,'IT-036','No tiene acceso al cuarto de máquinas, y/o incumplimiento la normatividad de trabajo en altura.',NULL,'GRAVE',0,0,36),
(37,4,37,'IT-037','No existe inscripción de acceso prohibido.',NULL,'LEVE',0,0,37),
(38,4,38,'IT-038','Puerta del cuarto de máquinas sin cerradura.',NULL,'GRAVE',0,0,38),
(39,4,39,'IT-039','El cuarto de máquinas es utilizado como bodega o para fines diferentes al funcionamiento del ascensor.',NULL,'GRAVE',0,0,39),
(40,4,40,'IT-040','Polea desgastada o tallada por asentamiento de los cables de tracción, mayor a un factor de deslizamiento de uno (1) (Véase Anexo E de la NTC 5926-1:2012)','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,40),
(41,4,41,'IT-041','Se encuentran uno o más cables hundidos en la polea a diferente nivel que los demás.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','LEVE',1,0,41),
(42,4,42,'IT-042','Falta protección que impida la salida de cables de tracción y/o cables de compensación.',NULL,'LEVE',0,0,42),
(43,4,43,'IT-043','Puerta de inspección o socorro con apertura hacia el interior.',NULL,'MUY_GRAVE',0,0,43),
(44,4,44,'IT-044','Puerta de inspección o socorro no es metálica y/o de alma llena.',NULL,'LEVE',0,0,44),
(45,4,45,'IT-045','Puerta de inspección o socorro sin cerradura',NULL,'GRAVE',0,0,45),
(46,4,46,'IT-046','Puerta de inspección o socorro no permite el cierre con enclavamiento al no tener la llave.',NULL,'LEVE',0,0,46),
(47,4,47,'IT-047','Puerta de inspección o socorro sin contacto eléctrico de seguridad, o que no funcione.',NULL,'MUY_GRAVE',0,0,47),
(48,4,48,'IT-048','Puerta del cuarto de poleas con cerraduras.',NULL,'GRAVE',0,0,48),
(49,4,49,'IT-049','Existe interruptor de parada en el cuarto de poleas.',NULL,'GRAVE',0,0,49),
(50,5,50,'IT-050','Para ascensores sin variador de velocidad en el motor principal, falta detector de inversión o ausencia de fase.',NULL,'LEVE',0,0,50),
(51,5,51,'IT-051','Existencia de humedad en techo, paredes y suelo de los cuartos de maquinas y poleas, y del foso del ascensor.',NULL,'LEVE',0,0,51),
(52,5,52,'IT-052','No existe interruptor general tripolar de corte de la alimentación',NULL,'MUY_GRAVE',0,0,52),
(53,5,53,'IT-053','Cada interruptor eléctrico (Breaker) no se identifica con el circuito que protege y/o los interruptores de protección no se identifican con su circuito de alimentación.',NULL,'GRAVE',0,0,53),
(54,5,54,'IT-054','Cuadro de maniobra con elementos sueltos o sin fijación (contactores, relevos, tarjetas de control, regletas o borneras, temporizadores).',NULL,'GRAVE',0,0,54),
(55,5,55,'IT-055','Cuadro de maniobra con empalmes sin aislamiento, fusibles puenteados, contactos suplementarios.',NULL,'MUY_GRAVE',0,0,55),
(56,5,56,'IT-056','Cables con aislamiento deteriorado y/o conductores expuestos.',NULL,'GRAVE',0,0,56),
(57,6,57,'IT-057','Para ascensores de tracción : -Con capacidad mayor a 6 pesonas la tracción se realiza con menos de tres cables - Con capacidad menor a 6 pesonas la tracción se realiza con menos de dos cables',NULL,'MUY_GRAVE',0,0,57),
(58,6,58,'IT-058','En casos de cinta de tracción, se presenta almenos una fisura, una grieta y/o un adelgazamiento de la cubierta en 1.5 m de la cinta.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','MUY_GRAVE',1,0,58),
(59,6,59,'IT-059','En el caso de ascensores sin cuarto de máquinas, hay las condiciones de rescate, especificados en el Anexo D de la NTC 5926-1:2012.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,59),
(60,6,60,'IT-060','Limitador en el hueco del ascensor sin posibilidad de maniobrar (des aplicar) desde el exterior.',NULL,'GRAVE',0,0,60),
(61,6,61,'IT-061','Siendo el motor del grupo tractor de corriente continua, el freno se encuentra alimentado por dicho motor',NULL,'GRAVE',0,0,61),
(62,6,62,'IT-062','Faltan pasadores en articulaciones del mecanismo del freno.',NULL,'GRAVE',0,0,62),
(63,6,63,'IT-063','Ejes de freno en mal estado (desgaste en cubos de las articulaciones, grietas o roturas de espiras en resortes o posibilidad de salir de sus asientos).',NULL,'GRAVE',0,0,63),
(64,6,64,'IT-064','Los elementos del freno no son de doble mordaza',NULL,'GRAVE',0,0,64),
(65,6,65,'IT-065','Muelles o resortes de freno deformados, fisurados, partidos u oxidados.',NULL,'GRAVE',0,0,65),
(66,6,66,'IT-066','La presión de frenado no es efectuada con resorte de compresión.',NULL,'LEVE',0,0,66),
(67,6,67,'IT-067','Zapatas de freno con aceite',NULL,'MUY_GRAVE',0,0,67),
(68,6,68,'IT-068','Zapatas de freno desgastadas hasta un 40 %.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','LEVE',1,1,68),
(69,6,69,'IT-069','No es posible acceder o accionar la palanca de freno, o no existe dicha palanca',NULL,'GRAVE',0,0,69),
(70,6,70,'IT-070','Falta o no está identificada la palanca de freno, para mover el elevador hasta llevarlo a un nivel de planta.',NULL,'MUY_GRAVE',0,0,70),
(71,6,71,'IT-071','El freno no detiene la cabina.',NULL,'MUY_GRAVE',0,0,71),
(72,6,72,'IT-072','El freno no funciona en ausencia de corriente eléctrica.',NULL,'MUY_GRAVE',0,0,72),
(73,6,73,'IT-073','La alimentación del freno es la misma que la del grupo tractor.',NULL,'GRAVE',0,0,73),
(74,6,74,'IT-074','Falta indicación de sentido de giro en la máquina de tracción.',NULL,'LEVE',0,0,74),
(75,6,75,'IT-075','Ausencia de marcas en almenos un piso, en cables de tracción y/o gobernador, para identificar la zona de desenclavamiento, para maniobra de evacuación. (Se recomienda que la marca sea en pintura tráfico).',NULL,'GRAVE',0,0,75),
(76,6,76,'IT-076','Las partes móviles del cuarto de maquina (poleas de tracción, de desvió, de limitador de velocidad y volantes de maniobra), están identificadas o tienen marcas distintivas (pintadas de amarillo), al menos parcialmente.',NULL,'GRAVE',0,0,76),
(77,6,77,'IT-077','La holgura entre la corona, el sin fin y/o el acople, supera 90º de giro en el volante sin moverse la polea de tracción.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,1,77),
(78,6,78,'IT-078','El volante tiene la manivela puesta en operación normal.',NULL,'MUY_GRAVE',0,0,78),
(79,4,79,'IT-079','El alumbrado no existe, no funciona, o es inferior a 200 LX a nivel del suelo en el cuarto de máquinas o de 100 luxes en el cuarto de poleas.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,1,79),
(80,7,80,'IT-080','En las zonas circulantes o pasillos alrededor de un pozo parcialmente abierto, existen barreras de protección con altura inferior a 2.5 m, a una distancia inferior a 50 cm de las partes móviles del ascensor. (Esta altura puede reducirse hasta 1.10 m, cuando la distancia a las partes móviles es superior a 2 m)','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,80),
(81,7,81,'IT-081','Para ascensores cuyo contrapeso y cabina estén dentro del mismo pozo, el contrapeso esta guiado mediante cables guía.',NULL,'MUY_GRAVE',0,0,81),
(82,7,82,'IT-082','No actúan las cuñas del paracaídas',NULL,'MUY_GRAVE',0,0,82),
(83,7,83,'IT-083','Cables del limitador inferior a 6 mm de diámetro.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,83),
(84,7,84,'IT-084','Cable de tracción roza con elementos de la instalación del equipo y/o de la obra civil.',NULL,'GRAVE',0,0,84),
(85,7,85,'IT-085','Cable del limitador roza con elementos de la instalación del equipo y/o de la obra civil.',NULL,'GRAVE',0,0,85),
(86,7,86,'IT-086','Cable del limitador deteriorado.',NULL,'MUY_GRAVE',0,0,86),
(87,7,87,'IT-087','Existen empalmes en los cables. (limitador velocidad)',NULL,'MUY_GRAVE',0,0,87),
(88,7,88,'IT-088','Presencia de oxidación en cualquier punto del cable del regulador de velocidad, y/o cables de compensación, tal que exista desprendimiento de material o se evidencie la destrucción paulatina de los hilos constituidos del cable, por acción de agentes externos.',NULL,'GRAVE',0,0,88),
(89,7,89,'IT-089','No se debe presentar oxidación en cualquier punto del cable del regulador de velocidad y/o cables de compensación, tal que: - Perdida de material y/o - Al contacto con el cable se presenta coloración característica del oxido (ejemplo amarilla o roja)',NULL,'LEVE',0,0,89),
(90,7,90,'IT-090','No existe y funciona el contacto eléctrico del limitador.',NULL,'MUY_GRAVE',0,0,90),
(91,7,91,'IT-091','Limitador inaccesible para realizar el mantenimiento e inspección.',NULL,'GRAVE',0,0,91),
(92,7,92,'IT-092','Limitador oxidado, sin lubricación, desplomado y desajustado.,o no esta anclado firmemente en almenos dos puntos de fijación.',NULL,'MUY_GRAVE',0,0,92),
(93,7,93,'IT-093','Ausencia de placa de especificaciones del limitador o regulador de velocidad, (en donde se estipule cual es la velocidad nominal y la velocidad de actuación).',NULL,'LEVE',0,0,93),
(94,7,94,'IT-094','El ascensor cumple la verificación de la prueba de funcionamiento del limitador de velocidad descrito en el anexo C, literal C.1 de la NTC 5926-1.(cabina, contrapeso)','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','MUY_GRAVE',1,1,94),
(95,7,95,'IT-095','El ascensor cumple la verificación de la prueba de funcionamiento del paracaídas descrito en el anexo C, literal C.2.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','MUY_GRAVE',1,0,95),
(96,7,96,'IT-096','Falla el trinquete del limitador funciona al engancharse',NULL,'MUY_GRAVE',0,0,96),
(97,7,97,'IT-097','El desbloqueo del paracaídas requiere la intervención del personal competente.',NULL,'LEVE',0,0,97),
(98,8,98,'IT-098','En hueco parcialmente cerrado, no existe el cerramiento, corral o balaustrada encima de cabina y/o un punto de fijación para arnés.',NULL,'LEVE',0,0,98),
(99,8,99,'IT-099','No existe interruptor de parada encima de cabina.',NULL,'GRAVE',0,0,99),
(100,8,100,'IT-100','No existe o no funciona el conmutador normal/inspección y/o no está plenamente identificado. En caso de que este elemento no se encuentre sobre la cabina, el ascensor debe contar con un dispositivo de parada de emergencia sobre la cabina.',NULL,'GRAVE',0,0,100),
(101,8,101,'IT-101','El techo no soporta sin deformación permanente el peso de dos personas (es decir 150 kg).',NULL,'GRAVE',0,0,101),
(102,8,102,'IT-102','Con el contrapeso sobre sus topes, no hay espacio para contener un paralelepípedo rectangular no menor a 0.5 m x 0.6 m x 0.8 m apoyado sobre una de sus caras encima de cabina. (Para los ascensores con suspensión directa, se incluyen los cables de suspensión y sus amarres en dicho volumen, siempre que ningún cable tenga su eje a una distancia superior a 0.15 m de, al menos, una cara vertical del paralelepípedo.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','LEVE',1,0,102),
(103,8,103,'IT-103','Distancia de actuación del dispositivo eléctrico del final de carrera inferior a 12 cm desde el punto de activación en los pisos superior e inferior.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,103),
(104,8,104,'IT-104','El dispositivo eléctrico de final de carrera no se activa antes de que la cabina y/o el contrapeso hagan contacto con el amortiguador.',NULL,'MUY_GRAVE',0,0,104),
(105,8,105,'IT-105','El interruptor final de carrera no se recupera al bajar o subir la cabina.',NULL,'GRAVE',0,0,105),
(106,8,106,'IT-106','Al estar activado el interruptor de final de carrera se recupera al moverse lateralmente la cabina',NULL,'MUY_GRAVE',0,0,106),
(107,8,107,'IT-107','No existe o no funcionan los dispositivos de final de carrera.',NULL,'MUY_GRAVE',0,0,107),
(108,8,108,'IT-108','Los finales de carrera, no son de apertura mecánica.',NULL,'GRAVE',0,0,108),
(109,9,109,'IT-109','Amarres de cable de tracción en cabina y/o contrapeso desajustado, sueltos, carente de amarres o mal estado (desgaste de pasadores, aprietes, tuerca, contratuerca, pasadores de aletas, corrosión, etc.).(cabina, contrapeso)',NULL,'MUY_GRAVE',0,0,109),
(110,9,110,'IT-110','Mezcla de diferentes tipos de amarres en los cables de tracción en el mismo punto, en cabina y/o en contrapeso.
NOTA: Se considera, aceptable tener un tipo de amarre para la cabina y otro distinto para el contrapeso.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,110),
(111,9,111,'IT-111','Diámetro de los cables de tracción inferior al 10 % de su diámetro nominal (por desgaste o por defecto de fabricación).','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,1,111),
(112,9,112,'IT-112','Cables con alambres rotos según los siguientes criterios:
1. Los hilos rotos superan al 50 % en un mismo paso del total de los hilos que conforman el torón.
2. Existen más de dos hilos rotos por torón en promedio en tramo de un paso del cable.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','MUY_GRAVE',1,0,112),
(113,9,113,'IT-113','Presencia de oxidación en cualquier punto del cable, tal que:
• Aún no se presenta perdida de material y/o
• Al contacto con el cable se presenta una coloración característica de oxido( Ejemplo amarilla o roja).',NULL,'LEVE',0,0,113),
(114,9,114,'IT-114','Presencia de oxidación en cualquier punto del cable, tal que: exista desprendimiento del material o se evidencia la destrucción paulatina de los hilos constitutivos del cable, por acción de agentes externos.',NULL,'GRAVE',0,0,114),
(115,9,115,'IT-115','Existen empalmes en los cables',NULL,'MUY_GRAVE',0,0,115),
(116,9,116,'IT-116','Cables con alambres rotos superior a dos hilos en un metro en el mismo torón. (limitador velocidad)',NULL,'GRAVE',0,0,116),
(117,9,117,'IT-117','Zapata y/o deslizadera de cabina y/o contrapeso en mal estado(rotas, no existentes, rozando partes metálicas, sueltas o con sujeción incompleta)',NULL,'GRAVE',0,0,117),
(118,9,118,'IT-118','La distancia entre órganos móviles y la parte fija cumple con las siguientes dimensiones: Distancia entre cabina y contrapeso ≤ 35 mm.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,118),
(119,9,119,'IT-119','Al soporte le faltan tuercas y pasadores (contrapeso)',NULL,'LEVE',0,0,119),
(120,9,120,'IT-120','Pesas rotas o fracturadas dentro del bastidor, y/o sobresaliendo fuera del bastidor(que incumpla la distancia mínima entre cabina y contrapeso, es decir < 35 mm).','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','MUY_GRAVE',1,0,120),
(121,9,121,'IT-121','No deberá existir posibilidad de movimiento de las pesas por ausencia de mecanismo de acuñamiento.',NULL,'MUY_GRAVE',0,0,121),
(122,9,122,'IT-122','En caso de existir poleas sobre el contrapeso, no disponen de los elementos necesarios para evitar la salida de los cables, (en caso de aflojamiento de estos y la introducción de cuerpos extraños en las gargantas de la misma) y/o estos dispositivos impiden las operaciones de inspección o de mantenimiento.',NULL,'GRAVE',0,0,122),
(123,10,123,'IT-123','Las puertas de la cabina no rígidas',NULL,'GRAVE',0,0,123),
(124,10,124,'IT-124','Arranca con puertas de cabina abiertas o al abrirla no se detiene durante el funcionamiento normal.',NULL,'MUY_GRAVE',0,0,124),
(125,10,125,'IT-125','Es posible abrir una puerta sin estar la cabina en la zona de des enclavamiento, sin una herramienta o el ascensor no se detiene.',NULL,'MUY_GRAVE',0,0,125),
(126,10,126,'IT-126','Las cerraduras no pueden abrirse desde el interior del hueco sin necesidad de llave.',NULL,'GRAVE',0,0,126),
(127,10,127,'IT-127','Oxidación y corrosión en más de un 20 % del área del elemento en las puertas y/o marcos de acceso.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,127),
(128,10,128,'IT-128','Puertas de acceso, paneles, bisagras o marcos estan deformadas y afectan el funcionamiento normal de ascensor.',NULL,'GRAVE',0,0,128),
(129,10,129,'IT-129','Hay solides de la fijación de los marcos a la pared.',NULL,'GRAVE',0,0,129),
(130,10,130,'IT-130','La puerta de acceso deja excesivas holguras. (Esta condición se considera cumplida cuando estas holguras operativas no superan a 6mm. Este valor puede alcanzar 10 mm debido al desgaste de las rozaderas o deslizadoras. Estas holguras deben medirse en el fondo de las hendiduras, si existen).','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,1,130),
(131,10,131,'IT-131','Zona de des enclavamiento superior a 35 cm por encima o por debajo del nivel del piso.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,1,131),
(132,10,132,'IT-132','Distancia entre pisadera ( o quicio) de cabina y pisadera ( o quicio)de piso excede 35 mm.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,132),
(133,10,133,'IT-133','Distancia entre embrague mecánico de puerta de cabina y la pisadera de pasillo es menor a 6 mm.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,1,133),
(134,10,134,'IT-134','Los elementos de enclavamiento no están encajados, al menos 7 mm.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,1,134),
(135,10,135,'IT-135','El enclavamiento mecánico no es controlado eléctricamente.',NULL,'MUY_GRAVE',0,0,135),
(136,10,136,'IT-136','En condiciones normales de funcionamiento, las puertas de acceso no están cerradas y enclavadas sin la presencia de la cabina',NULL,'MUY_GRAVE',0,0,136),
(137,10,137,'IT-137','Contactos eléctricos accesibles desde el exterior (pasillo).',NULL,'GRAVE',0,0,137),
(138,10,138,'IT-138','Bornes o cables eléctricos mal conectados o con defectos de aislamiento en puertas.',NULL,'GRAVE',0,0,138),
(139,10,139,'IT-139','Existencia de elementos cortantes (vidrios sin pulir, aristas vivas, etc.) en puerta de acceso y recorrido sin puertas en cabina.',NULL,'MUY_GRAVE',0,0,139),
(140,10,140,'IT-140','Mirilla de puertas rajada con protección (cristal armado, acrílico, malla)',NULL,'LEVE',0,0,140),
(141,10,141,'IT-141','Mirilla de puerta rota con hueco',NULL,'MUY_GRAVE',0,0,141),
(142,10,142,'IT-142','Mirilla suelta, con mala fijación o desajustada-',NULL,'GRAVE',0,0,142),
(143,10,143,'IT-143','Las hojas de puertas son de vidrio y no llevan marcas identificativas.',NULL,'LEVE',0,0,143),
(144,10,144,'IT-144','Existe piloto de presencia de cabina en puertas ciegas o visibilidad con mirilla.',NULL,'LEVE',0,0,144),
(145,10,145,'IT-145','Las hojas de vidrio,no llevan marcas identificativas.',NULL,'LEVE',0,0,145),
(146,10,146,'IT-146','Para el caso de puertas de rescate, existe piloto, indicador o mirilla para detectar presencia de cabina.',NULL,'LEVE',0,0,146),
(147,10,147,'IT-147','Hay más de 11 m,entre dos paradascontínuas sin apertura de socorro.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','LEVE',1,0,147),
(148,10,148,'IT-148','No existencia de puertas en las aberturas accesibles por las personas al hueco.',NULL,'GRAVE',0,0,148),
(149,11,149,'IT-149','Cable viajero y/o cordón de maniobra en mal estado, (quebrado, partido, conexiones flojas, cables desnudos, empalmados en la parte móvil).',NULL,'GRAVE',0,0,149),
(150,11,150,'IT-150','Las guías de la cabina en todo su recorrido, presentan mal estado de fijación a las paredes del hueco, deformaciones, desalineación y/o falta de paralelismo.',NULL,'LEVE',0,0,150),
(151,11,151,'IT-151','Instalaciones o elementos en pozo o sala de maquinas ajenas a las propias del ascensor (gas, aire acondicionado, acueducto, telecomunicaciones, acometidas hidráulicas o eléctricas, etc.).',NULL,'MUY_GRAVE',0,0,151),
(152,11,152,'IT-152','El hueco se utiliza para ventilación de otras áreas ajenas al ascensor (baños, cocinas, etc.).',NULL,'LEVE',0,0,152),
(153,11,153,'IT-153','Agua en el foso, existiendo instalación eléctrica y/o mecánica, en contacto con ella.',NULL,'MUY_GRAVE',0,0,153),
(154,11,154,'IT-154','No lleva faldón guardapiés en cabina.',NULL,'GRAVE',0,0,154),
(155,11,155,'IT-155','No existe o no funciona el contacto de acuñamiento, de cabina y/o de contrapeso.',NULL,'MUY_GRAVE',0,0,155),
(156,11,156,'IT-156','Falta o no funciona el dispositivo de control de rotura o aflojamiento del cable del limitador.',NULL,'GRAVE',0,0,156),
(157,11,157,'IT-157','Polea tensora del limitador no deberá rozar con la pared y/o el suelo.',NULL,'GRAVE',0,0,157),
(158,11,158,'IT-158','Amarres del cable del limitador al sistema paracaídas desajustado, suelto, carentes de amarres, o en mal estado (desgaste de pasadores, aprietes, tuerca, contratuerca, pasadores de aletas, corrosión, etc.). (limitador)',NULL,'MUY_GRAVE',0,0,158),
(159,11,159,'IT-159','El paracaídas no lleva cuñas.',NULL,'MUY_GRAVE',0,0,159),
(160,11,160,'IT-160','Al bastidor y chasis le faltan tuercas o pasadores que afecten su rigidez',NULL,'MUY_GRAVE',0,0,160),
(161,11,161,'IT-161','Plataforma de cabina hecha madera',NULL,'GRAVE',0,0,161),
(162,11,162,'IT-162','No existe o no funciona el dispositivo de sobrecarga.',NULL,'LEVE',0,0,162),
(163,11,163,'IT-163','En equipos hidráulicos con tracción indirecta que no tengan sistema de paracaídas en cabina, actúa la válvula de paracaídas en vacío en el pistón.',NULL,'MUY_GRAVE',0,0,163),
(164,11,164,'IT-164','Cuando se cierra el pozo, puertas de cabina con malla metálica, las perforaciones superan 10 mm x 6 mm, o están rotas o deterioradas','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','GRAVE',1,0,164),
(165,11,165,'IT-165','En equipos hidráulicos con tracción directa, no actúa la válvula de paracaídas en vacío',NULL,'MUY_GRAVE',0,0,165),
(166,11,166,'IT-166','Ausencia de un dispositivo contra el sobre-calentamiento del fluido hidráulico.',NULL,'GRAVE',0,0,166),
(167,11,167,'IT-167','En hueco parcialmente abierto no existe una barrera de protección encima de cabina. (Protección del personal de mantenimiento).',NULL,'LEVE',0,0,167),
(168,11,168,'IT-168','La iluminación de los accesos es menor a 50 lux a 1 m del piso y 1 m de la puerta de acceso para percibir la presencia de la cabina, si esta no cuenta con luz.','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','LEVE',1,1,168),
(169,11,169,'IT-169','Cuando un ascensor queda entre pisos o en el túnel, la distancia máxima entre la pisadera de cabina y el muro no es mayor a 125mm','Obligación de medida: registrar el valor medido, no se permiten estimaciones.','LEVE',1,0,169);

-- Reglas de 'aplica' por variante (ver comentario en checklist_item_variante)
INSERT INTO checklist_item_variante (id_item,id_variante_opcion)
SELECT r.id_item, o.id_variante_opcion
FROM (
SELECT 18 AS id_item, 'TIPO_BUFFER' AS tipo, 'HIDRAULICO' AS opcion
  UNION ALL SELECT 18 AS id_item, 'TIPO_BUFFER' AS tipo, 'MIXTO' AS opcion
  UNION ALL SELECT 19 AS id_item, 'TIPO_BUFFER' AS tipo, 'HIDRAULICO' AS opcion
  UNION ALL SELECT 19 AS id_item, 'TIPO_BUFFER' AS tipo, 'MIXTO' AS opcion
  UNION ALL SELECT 20 AS id_item, 'TIPO_BUFFER' AS tipo, 'HIDRAULICO' AS opcion
  UNION ALL SELECT 20 AS id_item, 'TIPO_BUFFER' AS tipo, 'MIXTO' AS opcion
  UNION ALL SELECT 23 AS id_item, 'LIMITADOR_CONTRAPESO' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 36 AS id_item, 'CUARTO_MAQUINAS' AS tipo, 'CON_CUARTO' AS opcion
  UNION ALL SELECT 37 AS id_item, 'CUARTO_MAQUINAS' AS tipo, 'CON_CUARTO' AS opcion
  UNION ALL SELECT 38 AS id_item, 'CUARTO_MAQUINAS' AS tipo, 'CON_CUARTO' AS opcion
  UNION ALL SELECT 39 AS id_item, 'CUARTO_MAQUINAS' AS tipo, 'CON_CUARTO' AS opcion
  UNION ALL SELECT 40 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 41 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 42 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 43 AS id_item, 'PUERTA_SOCORRO' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 44 AS id_item, 'PUERTA_SOCORRO' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 45 AS id_item, 'PUERTA_SOCORRO' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 46 AS id_item, 'PUERTA_SOCORRO' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 47 AS id_item, 'PUERTA_SOCORRO' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 48 AS id_item, 'CUARTO_POLEAS' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 49 AS id_item, 'CUARTO_POLEAS' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 57 AS id_item, 'TRACCION_POR' AS tipo, 'CABLE' AS opcion
  UNION ALL SELECT 57 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 58 AS id_item, 'TRACCION_POR' AS tipo, 'CINTA' AS opcion
  UNION ALL SELECT 58 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 59 AS id_item, 'CUARTO_MAQUINAS' AS tipo, 'SIN_CUARTO' AS opcion
  UNION ALL SELECT 59 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 60 AS id_item, 'CUARTO_MAQUINAS' AS tipo, 'SIN_CUARTO' AS opcion
  UNION ALL SELECT 60 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 61 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 62 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 63 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 64 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 65 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 66 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 67 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 68 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 69 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 70 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 71 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 72 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 73 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 74 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 75 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 76 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 77 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 77 AS id_item, 'MAQUINA' AS tipo, 'CON_REDUCTOR' AS opcion
  UNION ALL SELECT 78 AS id_item, 'ACCIONAMIENTO' AS tipo, 'ELECTRICO' AS opcion
  UNION ALL SELECT 78 AS id_item, 'MAQUINA' AS tipo, 'CON_REDUCTOR' AS opcion
  UNION ALL SELECT 83 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 85 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 86 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 87 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 90 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 91 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 92 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 93 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 94 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 96 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 111 AS id_item, 'TRACCION_POR' AS tipo, 'CABLE' AS opcion
  UNION ALL SELECT 112 AS id_item, 'TRACCION_POR' AS tipo, 'CABLE' AS opcion
  UNION ALL SELECT 113 AS id_item, 'TRACCION_POR' AS tipo, 'CABLE' AS opcion
  UNION ALL SELECT 114 AS id_item, 'TRACCION_POR' AS tipo, 'CABLE' AS opcion
  UNION ALL SELECT 115 AS id_item, 'TRACCION_POR' AS tipo, 'CABLE' AS opcion
  UNION ALL SELECT 116 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 140 AS id_item, 'MIRILLA_PUERTAS' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 141 AS id_item, 'MIRILLA_PUERTAS' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 142 AS id_item, 'MIRILLA_PUERTAS' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 146 AS id_item, 'PUERTA_SOCORRO' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 156 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 157 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 158 AS id_item, 'LIMITADOR_CABINA' AS tipo, 'SI' AS opcion
  UNION ALL SELECT 163 AS id_item, 'ACCIONAMIENTO' AS tipo, 'HIDRAULICO_INDIRECTO' AS opcion
  UNION ALL SELECT 165 AS id_item, 'ACCIONAMIENTO' AS tipo, 'HIDRAULICO_DIRECTO' AS opcion
  UNION ALL SELECT 166 AS id_item, 'ACCIONAMIENTO' AS tipo, 'HIDRAULICO_DIRECTO' AS opcion
  UNION ALL SELECT 166 AS id_item, 'ACCIONAMIENTO' AS tipo, 'HIDRAULICO_INDIRECTO' AS opcion
) r
JOIN variante_tipo t ON t.codigo = r.tipo
JOIN variante_opcion o ON o.id_variante_tipo = t.id_variante_tipo AND o.codigo = r.opcion;
