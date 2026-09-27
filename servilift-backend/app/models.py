# app/models.py
# Modelos SQLAlchemy de servilift_db (ver database/01_schema.sql).
# Los ENUM de la base se mapean como String: la base valida los valores.

from sqlalchemy import (
    Column, Integer, BigInteger, SmallInteger, String, Text, Date, DateTime, Time,
    Numeric, Boolean, ForeignKey, func,
)
from sqlalchemy.orm import relationship

from app.database import Base


# ============================================
# SEGURIDAD
# ============================================
class Rol(Base):
    __tablename__ = "rol"
    id_rol = Column(Integer, primary_key=True)
    codigo = Column(String(30), unique=True, nullable=False)
    nombre = Column(String(60), nullable=False)
    descripcion = Column(String(255))
    fecha_creacion = Column(DateTime, server_default=func.now())


class Usuario(Base):
    __tablename__ = "usuario"
    id_usuario = Column(Integer, primary_key=True)
    id_rol = Column(Integer, ForeignKey("rol.id_rol"), nullable=False)
    id_cliente = Column(Integer, ForeignKey("cliente.id_cliente"))
    nombre_completo = Column(String(150), nullable=False)
    correo = Column(String(120), unique=True, nullable=False)
    contrasena_hash = Column(String(255), nullable=False)
    tipo_documento = Column(String(5))
    documento = Column(String(30))
    telefono = Column(String(30))
    cargo = Column(String(100))
    matricula_profesional = Column(String(60))
    ruta_firma = Column(String(500))
    estado = Column(String(20), nullable=False, default="ACTIVO")
    ultima_sesion = Column(DateTime)
    fecha_registro = Column(DateTime, server_default=func.now())

    rol = relationship("Rol", lazy="joined")
    cliente = relationship("Cliente", foreign_keys=[id_cliente])

    @property
    def rol_codigo(self) -> str:
        return self.rol.codigo if self.rol else ""


# ============================================
# CLIENTES, EDIFICIOS Y EQUIPOS
# ============================================
class Cliente(Base):
    __tablename__ = "cliente"
    id_cliente = Column(Integer, primary_key=True)
    id_asesor = Column(Integer, ForeignKey("usuario.id_usuario"), nullable=False)
    tipo_documento = Column(String(5), nullable=False, default="NIT")
    numero_documento = Column(String(30), nullable=False)
    razon_social = Column(String(200), nullable=False)
    tipo_cliente = Column(String(30), nullable=False, default="PROPIEDAD_HORIZONTAL")
    contacto_nombre = Column(String(150))
    contacto_cargo = Column(String(100))
    contacto_correo = Column(String(120))
    contacto_telefono = Column(String(30))
    direccion = Column(String(250))
    ciudad = Column(String(100))
    estado = Column(String(20), nullable=False, default="ACTIVO")
    fecha_registro = Column(DateTime, server_default=func.now())

    asesor = relationship("Usuario", foreign_keys=[id_asesor])
    edificios = relationship("Edificio", back_populates="cliente", order_by="Edificio.nombre")


class Edificio(Base):
    __tablename__ = "edificio"
    id_edificio = Column(Integer, primary_key=True)
    id_cliente = Column(Integer, ForeignKey("cliente.id_cliente"), nullable=False)
    nombre = Column(String(150), nullable=False)
    direccion = Column(String(250), nullable=False)
    barrio = Column(String(100))
    ciudad = Column(String(100), nullable=False)
    departamento = Column(String(100))
    numero_pisos = Column(Integer)
    numero_equipos = Column(Integer, nullable=False, default=0)
    administrador_nombre = Column(String(150))
    administrador_telefono = Column(String(30))
    administrador_correo = Column(String(120))
    empresa_mantenimiento = Column(String(150))
    latitud = Column(Numeric(10, 8))
    longitud = Column(Numeric(11, 8))
    estado = Column(String(20), nullable=False, default="ACTIVO")
    fecha_registro = Column(DateTime, server_default=func.now())

    cliente = relationship("Cliente", back_populates="edificios")
    equipos = relationship("Equipo", back_populates="edificio", order_by="Equipo.identificacion")


class Equipo(Base):
    __tablename__ = "equipo"
    id_equipo = Column(Integer, primary_key=True)
    id_edificio = Column(Integer, ForeignKey("edificio.id_edificio"), nullable=False)
    identificacion = Column(String(80), nullable=False)
    tipo_equipo = Column(String(30), nullable=False, default="ASCENSOR_PASAJEROS")
    marca = Column(String(80))
    modelo = Column(String(80))
    numero_serie = Column(String(80))
    anio_fabricacion = Column(SmallInteger)
    capacidad_kg = Column(Integer)
    capacidad_personas = Column(Integer)
    numero_paradas = Column(Integer)
    recorrido_m = Column(Numeric(8, 2))
    velocidad_ms = Column(Numeric(5, 2))
    profundidad_foso_mm = Column(Integer)
    fecha_puesta_marcha = Column(Date)
    estado = Column(String(20), nullable=False, default="ACTIVO")
    fecha_registro = Column(DateTime, server_default=func.now())

    edificio = relationship("Edificio", back_populates="equipos")
    variantes = relationship("EquipoVariante", cascade="all, delete-orphan")


# ============================================
# VARIANTES
# ============================================
class VarianteTipo(Base):
    __tablename__ = "variante_tipo"
    id_variante_tipo = Column(Integer, primary_key=True)
    codigo = Column(String(40), unique=True, nullable=False)
    nombre = Column(String(100), nullable=False)
    obligatoria = Column(Boolean, nullable=False, default=True)
    orden = Column(Integer, nullable=False, default=0)
    activo = Column(Boolean, nullable=False, default=True)

    opciones = relationship("VarianteOpcion", order_by="VarianteOpcion.orden")


class VarianteOpcion(Base):
    __tablename__ = "variante_opcion"
    id_variante_opcion = Column(Integer, primary_key=True)
    id_variante_tipo = Column(Integer, ForeignKey("variante_tipo.id_variante_tipo"), nullable=False)
    codigo = Column(String(40), nullable=False)
    nombre = Column(String(100), nullable=False)
    orden = Column(Integer, nullable=False, default=0)
    activo = Column(Boolean, nullable=False, default=True)


class EquipoVariante(Base):
    __tablename__ = "equipo_variante"
    id_equipo = Column(Integer, ForeignKey("equipo.id_equipo"), primary_key=True)
    id_variante_tipo = Column(Integer, ForeignKey("variante_tipo.id_variante_tipo"), primary_key=True)
    id_variante_opcion = Column(Integer, ForeignKey("variante_opcion.id_variante_opcion"), nullable=False)


# ============================================
# COMERCIAL
# ============================================
class Consecutivo(Base):
    __tablename__ = "consecutivo"
    prefijo = Column(String(10), primary_key=True)
    anio = Column(SmallInteger, primary_key=True)
    ultimo_numero = Column(Integer, nullable=False, default=0)


class Cotizacion(Base):
    __tablename__ = "cotizacion"
    id_cotizacion = Column(Integer, primary_key=True)
    numero_cotizacion = Column(String(20), unique=True, nullable=False)
    id_cliente = Column(Integer, ForeignKey("cliente.id_cliente"), nullable=False)
    id_edificio = Column(Integer, ForeignKey("edificio.id_edificio"), nullable=False)
    id_asesor = Column(Integer, ForeignKey("usuario.id_usuario"), nullable=False)
    fecha_cotizacion = Column(Date, nullable=False)
    dias_validez = Column(Integer, nullable=False, default=30)
    subtotal = Column(Numeric(14, 2), nullable=False, default=0)
    iva_porcentaje = Column(Numeric(5, 2), nullable=False, default=19)
    iva_valor = Column(Numeric(14, 2), nullable=False, default=0)
    total = Column(Numeric(14, 2), nullable=False, default=0)
    estado = Column(String(30), nullable=False, default="BORRADOR")
    condiciones = Column(Text)
    observaciones = Column(Text)
    fecha_envio_cliente = Column(DateTime)
    fecha_respuesta_cliente = Column(DateTime)
    id_usuario_respuesta = Column(Integer, ForeignKey("usuario.id_usuario"))
    comentario_cliente = Column(Text)
    fecha_envio_programacion = Column(DateTime)
    ruta_pdf = Column(String(500))
    fecha_creacion = Column(DateTime, server_default=func.now())

    cliente = relationship("Cliente")
    edificio = relationship("Edificio")
    asesor = relationship("Usuario", foreign_keys=[id_asesor])
    equipos = relationship("CotizacionEquipo", back_populates="cotizacion",
                           cascade="all, delete-orphan", order_by="CotizacionEquipo.codigo_servicio")


class CotizacionEquipo(Base):
    __tablename__ = "cotizacion_equipo"
    id_cotizacion_equipo = Column(Integer, primary_key=True)
    id_cotizacion = Column(Integer, ForeignKey("cotizacion.id_cotizacion"), nullable=False)
    id_equipo = Column(Integer, ForeignKey("equipo.id_equipo"), nullable=False)
    codigo_servicio = Column(String(25), unique=True, nullable=False)
    tipo_servicio = Column(String(30), nullable=False, default="INSPECCION_PERIODICA")
    descripcion = Column(String(255))
    valor = Column(Numeric(14, 2), nullable=False)
    estado = Column(String(30), nullable=False, default="PENDIENTE_APROBACION")
    fecha_estado = Column(DateTime, server_default=func.now())
    plazo_dias = Column(Integer)
    fecha_limite_correccion = Column(Date)
    fecha_solicitud_visita2 = Column(DateTime)
    id_usuario_solicitud_visita2 = Column(Integer, ForeignKey("usuario.id_usuario"))

    cotizacion = relationship("Cotizacion", back_populates="equipos")
    equipo = relationship("Equipo")


class HistorialEstado(Base):
    __tablename__ = "historial_estado"
    id_historial = Column(BigInteger, primary_key=True)
    id_cotizacion_equipo = Column(Integer, ForeignKey("cotizacion_equipo.id_cotizacion_equipo"), nullable=False)
    estado_anterior = Column(String(30))
    estado_nuevo = Column(String(30), nullable=False)
    id_usuario = Column(Integer, ForeignKey("usuario.id_usuario"))
    comentario = Column(String(500))
    fecha = Column(DateTime, server_default=func.now())

    usuario = relationship("Usuario")


# ============================================
# PROGRAMACIÓN
# ============================================
class ProgramacionEquipo(Base):
    __tablename__ = "programacion_equipo"
    id_programacion = Column(Integer, ForeignKey("programacion.id_programacion"), primary_key=True)
    id_cotizacion_equipo = Column(Integer, ForeignKey("cotizacion_equipo.id_cotizacion_equipo"), primary_key=True)

    cotizacion_equipo = relationship("CotizacionEquipo")


class Programacion(Base):
    __tablename__ = "programacion"
    id_programacion = Column(Integer, primary_key=True)
    id_cotizacion = Column(Integer, ForeignKey("cotizacion.id_cotizacion"), nullable=False)
    id_inspector = Column(Integer, ForeignKey("usuario.id_usuario"), nullable=False)
    id_programador = Column(Integer, ForeignKey("usuario.id_usuario"), nullable=False)
    tipo_visita = Column(String(10), nullable=False, default="PRIMERA")
    fecha_programada = Column(Date, nullable=False)
    hora_inicio = Column(Time, nullable=False)
    hora_fin_estimada = Column(Time)
    estado = Column(String(20), nullable=False, default="PROGRAMADA")
    observaciones = Column(String(500))
    motivo_cambio = Column(String(255))
    fecha_creacion = Column(DateTime, server_default=func.now())

    cotizacion = relationship("Cotizacion")
    inspector = relationship("Usuario", foreign_keys=[id_inspector])
    equipos = relationship("ProgramacionEquipo", cascade="all, delete-orphan")


# ============================================
# CHECKLIST
# ============================================
class ChecklistCategoria(Base):
    __tablename__ = "checklist_categoria"
    id_categoria = Column(Integer, primary_key=True)
    codigo = Column(String(20), unique=True, nullable=False)
    nombre = Column(String(150), nullable=False)
    descripcion = Column(String(500))
    norma = Column(String(40), nullable=False)
    numeral_norma = Column(String(40))
    orden = Column(Integer, nullable=False, default=0)
    activo = Column(Boolean, nullable=False, default=True)


class ChecklistItem(Base):
    __tablename__ = "checklist_item"
    id_item = Column(Integer, primary_key=True)
    id_categoria = Column(Integer, ForeignKey("checklist_categoria.id_categoria"), nullable=False)
    numero = Column(Integer, unique=True, nullable=False)
    codigo = Column(String(20), unique=True, nullable=False)
    numeral_norma = Column(String(40))
    descripcion = Column(Text, nullable=False)
    criterio_cumplimiento = Column(Text)
    calificacion = Column(String(10), nullable=False)
    requiere_medicion = Column(Boolean, nullable=False, default=False)
    requiere_foto_medicion = Column(Boolean, nullable=False, default=False)
    plazo_dias = Column(Integer)
    unidad_medida = Column(String(20))
    obligatorio = Column(Boolean, nullable=False, default=True)
    orden = Column(Integer, nullable=False, default=0)
    activo = Column(Boolean, nullable=False, default=True)

    categoria = relationship("ChecklistCategoria")


# ============================================
# INSPECCIÓN
# ============================================
class Inspeccion(Base):
    __tablename__ = "inspeccion"
    id_inspeccion = Column(Integer, primary_key=True)
    numero_inspeccion = Column(String(20), unique=True, nullable=False)
    id_cotizacion_equipo = Column(Integer, ForeignKey("cotizacion_equipo.id_cotizacion_equipo"), nullable=False)
    id_programacion = Column(Integer, ForeignKey("programacion.id_programacion"), nullable=False)
    id_inspector = Column(Integer, ForeignKey("usuario.id_usuario"), nullable=False)
    uuid_offline = Column(String(36), unique=True)
    datos_equipo_json = Column(Text)
    conservacion_informacion = Column(String(10), nullable=False, default="DIGITAL")
    tipo_acrilico = Column(String(80))
    empresa_mantenimiento = Column(String(150))
    tecnico_mantenimiento = Column(String(150))
    fecha_ultimo_mantenimiento = Column(Date)
    fecha_puesta_marcha = Column(Date)
    fecha_ultima_inspeccion = Column(Date)
    capacidad_kg = Column(Integer)
    capacidad_personas = Column(Integer)
    numero_paradas = Column(Integer)
    profundidad_foso_mm = Column(Integer)
    recorrido_m = Column(Numeric(8, 2))
    fecha_inicio = Column(DateTime, nullable=False)
    fecha_fin = Column(DateTime)
    id_programacion_visita2 = Column(Integer, ForeignKey("programacion.id_programacion"))
    id_inspector_visita2 = Column(Integer, ForeignKey("usuario.id_usuario"))
    fecha_visita2 = Column(DateTime)
    estado = Column(String(20), nullable=False, default="EN_CURSO")
    observaciones_generales = Column(Text)
    latitud = Column(Numeric(10, 8))
    longitud = Column(Numeric(11, 8))
    sincronizada = Column(Boolean, nullable=False, default=True)
    fecha_sincronizacion = Column(DateTime)
    fecha_creacion = Column(DateTime, server_default=func.now())

    cotizacion_equipo = relationship("CotizacionEquipo")
    programacion = relationship("Programacion", foreign_keys=[id_programacion])
    inspector = relationship("Usuario", foreign_keys=[id_inspector])
    variantes = relationship("InspeccionVariante", cascade="all, delete-orphan")
    resultados = relationship("InspeccionResultado", cascade="all, delete-orphan")
    fotos = relationship("InspeccionFoto", cascade="all, delete-orphan", order_by="InspeccionFoto.orden")
    firmas = relationship("InspeccionFirma", cascade="all, delete-orphan")
    mediciones = relationship("InspeccionMedicion", cascade="all, delete-orphan")
    instrumentos = relationship("InspeccionInstrumento", cascade="all, delete-orphan")
    informe = relationship("Informe", uselist=False, back_populates="inspeccion")


class InspeccionVariante(Base):
    __tablename__ = "inspeccion_variante"
    id_inspeccion = Column(Integer, ForeignKey("inspeccion.id_inspeccion"), primary_key=True)
    id_variante_tipo = Column(Integer, ForeignKey("variante_tipo.id_variante_tipo"), primary_key=True)
    id_variante_opcion = Column(Integer, ForeignKey("variante_opcion.id_variante_opcion"), nullable=False)

    tipo = relationship("VarianteTipo")
    opcion = relationship("VarianteOpcion")


class InspeccionResultado(Base):
    __tablename__ = "inspeccion_resultado"
    id_resultado = Column(Integer, primary_key=True)
    id_inspeccion = Column(Integer, ForeignKey("inspeccion.id_inspeccion"), nullable=False)
    id_item = Column(Integer, ForeignKey("checklist_item.id_item"), nullable=False)
    resultado = Column(String(15), nullable=False)
    calificacion_defecto = Column(String(10))
    no_aplica_automatico = Column(Boolean, nullable=False, default=False)
    valor_medido = Column(String(50))
    unidad_medida = Column(String(20))
    observacion = Column(Text)
    hallazgo_director = Column(Boolean, nullable=False, default=False)
    estado_segunda_visita = Column(String(15))
    observacion_segunda_visita = Column(Text)

    item = relationship("ChecklistItem")


class InspeccionFoto(Base):
    __tablename__ = "inspeccion_foto"
    id_foto = Column(Integer, primary_key=True)
    id_inspeccion = Column(Integer, ForeignKey("inspeccion.id_inspeccion"), nullable=False)
    id_resultado = Column(Integer, ForeignKey("inspeccion_resultado.id_resultado"))
    uuid_offline = Column(String(36), unique=True)
    nombre_archivo = Column(String(255), nullable=False)
    ruta_archivo = Column(String(500), nullable=False)
    ruta_miniatura = Column(String(500))
    tamano_kb = Column(Integer)
    descripcion = Column(String(300))
    orden = Column(Integer, nullable=False, default=0)
    incluir_en_informe = Column(Boolean, nullable=False, default=True)
    revisada = Column(Boolean, nullable=False, default=False)
    fecha_captura = Column(DateTime)
    latitud = Column(Numeric(10, 8))
    longitud = Column(Numeric(11, 8))
    fecha_subida = Column(DateTime, server_default=func.now())


class InspeccionFirma(Base):
    __tablename__ = "inspeccion_firma"
    id_firma = Column(Integer, primary_key=True)
    id_inspeccion = Column(Integer, ForeignKey("inspeccion.id_inspeccion"), nullable=False)
    numero_visita = Column(SmallInteger, nullable=False, default=1)
    tipo_firmante = Column(String(30), nullable=False)
    id_usuario = Column(Integer, ForeignKey("usuario.id_usuario"))
    nombre = Column(String(150), nullable=False)
    documento = Column(String(30))
    cargo = Column(String(100))
    empresa = Column(String(150))
    ruta_firma = Column(String(500), nullable=False)
    fecha_firma = Column(DateTime, nullable=False)


class InstrumentoMedicion(Base):
    __tablename__ = "instrumento_medicion"
    id_instrumento = Column(Integer, primary_key=True)
    codigo = Column(String(30), unique=True, nullable=False)
    tipo = Column(String(30), nullable=False)
    marca = Column(String(80))
    serial = Column(String(80))
    id_inspector = Column(Integer, ForeignKey("usuario.id_usuario"))
    fecha_calibracion = Column(Date)
    vence_calibracion = Column(Date)
    estado = Column(String(20), nullable=False, default="ACTIVO")


class InspeccionInstrumento(Base):
    __tablename__ = "inspeccion_instrumento"
    id_inspeccion = Column(Integer, ForeignKey("inspeccion.id_inspeccion"), primary_key=True)
    id_instrumento = Column(Integer, ForeignKey("instrumento_medicion.id_instrumento"), primary_key=True)

    instrumento = relationship("InstrumentoMedicion")


class InspeccionMedicion(Base):
    __tablename__ = "inspeccion_medicion"
    id_medicion = Column(Integer, primary_key=True)
    id_inspeccion = Column(Integer, ForeignKey("inspeccion.id_inspeccion"), nullable=False)
    id_item = Column(Integer, ForeignKey("checklist_item.id_item"))
    concepto = Column(String(80), nullable=False)
    valor = Column(Numeric(12, 4))
    unidad = Column(String(20))
    resultado = Column(String(10))
    detalle = Column(String(255))


# ============================================
# INFORME Y CERTIFICADO
# ============================================
class Informe(Base):
    __tablename__ = "informe"
    id_informe = Column(Integer, primary_key=True)
    numero_informe = Column(String(20), unique=True, nullable=False)
    id_inspeccion = Column(Integer, ForeignKey("inspeccion.id_inspeccion"), unique=True, nullable=False)
    id_director = Column(Integer, ForeignKey("usuario.id_usuario"))
    estado = Column(String(20), nullable=False, default="PENDIENTE_REVISION")
    concepto = Column(String(15))
    atestacion = Column(Text)
    observaciones_revision = Column(Text)
    ruta_firma_director = Column(String(500))
    visita_actual = Column(SmallInteger, nullable=False, default=1)
    concepto_visita1 = Column(String(15))
    fecha_aprobacion_visita1 = Column(DateTime)
    ruta_pdf_visita1 = Column(String(500))
    hash_visita1 = Column(String(64))
    ruta_firma_director_v1 = Column(String(500))
    plazo_dias = Column(Integer)
    fecha_limite_correccion = Column(Date)
    total_corregidos = Column(Integer, nullable=False, default=0)
    total_no_corregidos = Column(Integer, nullable=False, default=0)
    total_leves = Column(Integer, nullable=False, default=0)
    total_graves = Column(Integer, nullable=False, default=0)
    total_muy_graves = Column(Integer, nullable=False, default=0)
    total_no_aplica = Column(Integer, nullable=False, default=0)
    fecha_revision = Column(DateTime)
    fecha_aprobacion = Column(DateTime)
    ruta_pdf = Column(String(500))
    hash_sha256 = Column(String(64))
    fecha_envio_cliente = Column(DateTime)
    fecha_envio_certificados = Column(DateTime)
    fecha_creacion = Column(DateTime, server_default=func.now())

    inspeccion = relationship("Inspeccion", back_populates="informe")
    director = relationship("Usuario", foreign_keys=[id_director])
    certificado = relationship("Certificado", uselist=False, back_populates="informe")


class Certificado(Base):
    __tablename__ = "certificado"
    id_certificado = Column(Integer, primary_key=True)
    numero_certificado = Column(String(20), unique=True, nullable=False)
    id_informe = Column(Integer, ForeignKey("informe.id_informe"), unique=True, nullable=False)
    id_cotizacion_equipo = Column(Integer, ForeignKey("cotizacion_equipo.id_cotizacion_equipo"), nullable=False)
    id_emisor = Column(Integer, ForeignKey("usuario.id_usuario"))
    estado = Column(String(20), nullable=False, default="EN_ELABORACION")
    fecha_emision = Column(Date)
    fecha_vencimiento = Column(Date)
    codigo_verificacion = Column(String(40), unique=True)
    ruta_pdf = Column(String(500))
    hash_sha256 = Column(String(64))
    fecha_envio_cliente = Column(DateTime)
    motivo_anulacion = Column(String(255))
    fecha_creacion = Column(DateTime, server_default=func.now())

    informe = relationship("Informe", back_populates="certificado")
    cotizacion_equipo = relationship("CotizacionEquipo")


# ============================================
# SOPORTE
# ============================================
class Parametro(Base):
    __tablename__ = "parametro"
    clave = Column(String(60), primary_key=True)
    valor = Column(Text, nullable=False)
    descripcion = Column(String(255))


class Notificacion(Base):
    __tablename__ = "notificacion"
    id_notificacion = Column(Integer, primary_key=True)
    id_usuario_destino = Column(Integer, ForeignKey("usuario.id_usuario"), nullable=False)
    titulo = Column(String(120), nullable=False)
    mensaje = Column(String(500), nullable=False)
    tipo = Column(String(40))
    id_referencia = Column(Integer)
    enlace = Column(String(255))
    leida = Column(Boolean, nullable=False, default=False)
    fecha_creacion = Column(DateTime, server_default=func.now())
