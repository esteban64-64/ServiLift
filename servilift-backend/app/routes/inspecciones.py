# app/routes/inspecciones.py
# App móvil del inspector: agenda, abrir informe (datos precargados), variantes,
# checklist NTC 5926-1, fotos, mediciones, firmas y finalizar.

import json
from datetime import date, datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import (
    ChecklistCategoria, ChecklistItem, CotizacionEquipo, EquipoVariante, Informe, Inspeccion, InspeccionFirma,
    InspeccionFoto, InspeccionInstrumento, InspeccionMedicion, InspeccionResultado, InspeccionVariante,
    InstrumentoMedicion, Programacion, Usuario, VarianteOpcion,
)
from app.routes.serializers import CAMPOS_EDIFICIO, CAMPOS_EQUIPO, cot_equipo_dict, fila, programacion_dict
from app.security import ADMIN, DIRECTOR_TECNICO, INSPECTOR, get_current_user, require_roles
from app.services import archivos
from app.services.checklist import (
    CALIF_CORTA, items_aplicables, pendientes_para_finalizar, pendientes_segunda_visita, precargar_no_aplica,
    resumen,
)
from app.services.flujo import cambiar_estado, notificar, siguiente_numero, usuarios_por_rol

router = APIRouter(prefix="/inspecciones", tags=["Inspecciones"])

RESULTADOS = {"CUMPLE", "NO_CUMPLE", "NO_APLICA", "NO_VERIFICADO"}
TIPOS_FIRMANTE = {"INSPECTOR", "TECNICO_MANTENIMIENTO", "REPRESENTANTE_EDIFICIO"}


# ============================================
# ESQUEMAS
# ============================================
class IniciarIn(BaseModel):
    id_programacion: int
    id_cotizacion_equipo: int
    uuid_offline: str | None = None
    latitud: float | None = None
    longitud: float | None = None


class EncabezadoIn(BaseModel):
    conservacion_informacion: str | None = None
    tipo_acrilico: str | None = None
    empresa_mantenimiento: str | None = None
    tecnico_mantenimiento: str | None = None
    fecha_ultimo_mantenimiento: date | None = None
    fecha_puesta_marcha: date | None = None
    fecha_ultima_inspeccion: date | None = None
    capacidad_kg: int | None = None
    capacidad_personas: int | None = None
    numero_paradas: int | None = None
    profundidad_foso_mm: int | None = None
    recorrido_m: float | None = None
    observaciones_generales: str | None = None


class EquipoDatosIn(BaseModel):
    """Datos del ascensor que el inspector verifica en sitio."""
    tipo_equipo: str | None = None
    marca: str | None = None
    modelo: str | None = None
    numero_serie: str | None = None
    anio_fabricacion: int | None = None
    capacidad_kg: int | None = None
    capacidad_personas: int | None = None
    numero_paradas: int | None = None
    velocidad_ms: float | None = None
    recorrido_m: float | None = None
    profundidad_foso_mm: int | None = None
    fecha_puesta_marcha: date | None = None


# Campos que además quedan en la inspección (encabezado del informe)
CAMPOS_EQUIPO_EN_INSPECCION = ("capacidad_kg", "capacidad_personas", "numero_paradas", "profundidad_foso_mm",
                               "recorrido_m", "fecha_puesta_marcha")


class VarianteIn(BaseModel):
    id_variante_tipo: int
    id_variante_opcion: int


class ResultadoIn(BaseModel):
    id_item: int
    resultado: str
    valor_medido: str | None = None
    unidad_medida: str | None = None
    observacion: str | None = None


class SegundaVisitaIn(BaseModel):
    id_item: int
    estado_segunda_visita: str          # CORREGIDO / NO_CORREGIDO
    observacion_segunda_visita: str | None = None


class FotoUpdate(BaseModel):
    descripcion: str | None = None
    orden: int | None = None
    incluir_en_informe: bool | None = None
    revisada: bool | None = None
    id_item: int | None = None


class FirmaIn(BaseModel):
    tipo_firmante: str
    nombre: str
    documento: str | None = None
    cargo: str | None = None
    empresa: str | None = None
    firma_base64: str
    numero_visita: int = 1


class MedicionIn(BaseModel):
    concepto: str
    valor: Decimal | None = None
    unidad: str | None = None
    resultado: str | None = None
    detalle: str | None = None
    id_item: int | None = None


# ============================================
# ACCESO
# ============================================
def _obtener(db: Session, id_inspeccion: int, usuario: Usuario) -> Inspeccion:
    insp = db.get(Inspeccion, id_inspeccion)
    if not insp:
        raise HTTPException(404, "Inspección no encontrada")
    if usuario.rol_codigo == INSPECTOR and usuario.id_usuario not in (insp.id_inspector, insp.id_inspector_visita2):
        raise HTTPException(403, "Esta inspección no está asignada a usted")
    if usuario.rol_codigo not in (INSPECTOR, DIRECTOR_TECNICO, ADMIN):
        raise HTTPException(403, "No tiene permisos para ver inspecciones")
    return insp


def _editable(insp: Inspeccion, usuario: Usuario, primera_visita: bool = False):
    """El inspector edita mientras está en curso, devuelta o en segunda visita; el director mientras revisa.
    primera_visita=True: solo lo que se diligencia en la primera visita (checklist, variantes)."""
    estados = ("EN_CURSO", "DEVUELTA") if primera_visita else ("EN_CURSO", "DEVUELTA", "EN_SEGUNDA_VISITA")
    if usuario.rol_codigo == INSPECTOR and insp.estado in estados:
        return
    if usuario.rol_codigo in (DIRECTOR_TECNICO, ADMIN) and insp.informe and insp.informe.estado == "PENDIENTE_REVISION":
        return
    raise HTTPException(409, f"La inspección está {insp.estado} y no se puede modificar")


# ============================================
# SERIALIZACIÓN
# ============================================
def _foto_dict(f: InspeccionFoto):
    d = fila(f, ["id_foto", "id_resultado", "uuid_offline", "nombre_archivo", "descripcion", "orden",
                 "incluir_en_informe", "revisada", "fecha_captura", "tamano_kb"])
    d["url"] = f"/archivos/{f.ruta_archivo}"
    d["url_miniatura"] = f"/archivos/{f.ruta_miniatura or f.ruta_archivo}"
    return d


def _detalle(db: Session, insp: Inspeccion) -> dict:
    d = fila(insp, ["id_inspeccion", "numero_inspeccion", "id_cotizacion_equipo", "id_programacion", "id_inspector",
                    "conservacion_informacion", "tipo_acrilico", "empresa_mantenimiento", "tecnico_mantenimiento",
                    "fecha_ultimo_mantenimiento", "fecha_puesta_marcha", "fecha_ultima_inspeccion", "capacidad_kg",
                    "capacidad_personas", "numero_paradas", "profundidad_foso_mm", "recorrido_m", "fecha_inicio",
                    "fecha_fin", "fecha_visita2", "estado", "observaciones_generales"])
    d["inspector"] = insp.inspector.nombre_completo
    d["id_inspector_visita2"] = insp.id_inspector_visita2
    d["id_programacion_visita2"] = insp.id_programacion_visita2
    d["numero_visita"] = 2 if insp.id_programacion_visita2 else 1
    d["datos_equipo"] = json.loads(insp.datos_equipo_json or "{}")
    d["variantes"] = [{"id_variante_tipo": v.id_variante_tipo, "tipo": v.tipo.nombre, "codigo_tipo": v.tipo.codigo,
                       "id_variante_opcion": v.id_variante_opcion, "opcion": v.opcion.nombre,
                       "codigo_opcion": v.opcion.codigo} for v in insp.variantes]
    d["resumen"] = resumen(insp)
    d["total_fotos"] = len(insp.fotos)
    d["firmas"] = [fila(f, ["id_firma", "numero_visita", "tipo_firmante", "nombre", "documento", "cargo", "empresa",
                            "fecha_firma"]) | {"url": f"/archivos/{f.ruta_firma}"} for f in insp.firmas]
    d["mediciones"] = [fila(m, ["id_medicion", "id_item", "concepto", "valor", "unidad", "resultado", "detalle"])
                       for m in insp.mediciones]
    d["instrumentos"] = [fila(i.instrumento, ["id_instrumento", "codigo", "tipo", "vence_calibracion"])
                         for i in insp.instrumentos]
    inf = insp.informe
    d["informe"] = fila(inf, ["id_informe", "numero_informe", "estado", "concepto", "observaciones_revision",
                              "visita_actual", "concepto_visita1"]) if inf else None
    return d


# ============================================
# AGENDA DEL INSPECTOR
# ============================================
@router.get("/agenda")
def agenda(desde: date | None = None, db: Session = Depends(get_db),
           usuario: Usuario = Depends(require_roles(INSPECTOR))):
    # Visitas abiertas + las que tienen una inspección devuelta por el director o en segunda visita
    con_pendientes = {i.id_programacion_visita2 if i.estado == "EN_SEGUNDA_VISITA" else i.id_programacion
                      for i in db.query(Inspeccion).filter(
                          or_(Inspeccion.id_inspector == usuario.id_usuario,
                              Inspeccion.id_inspector_visita2 == usuario.id_usuario),
                          Inspeccion.estado.in_(("DEVUELTA", "EN_CURSO", "EN_SEGUNDA_VISITA")))}
    q = db.query(Programacion).filter(
        Programacion.id_inspector == usuario.id_usuario,
        or_(Programacion.estado.in_(("PROGRAMADA", "REPROGRAMADA", "EN_CURSO")),
            Programacion.id_programacion.in_(con_pendientes or {0})))
    if desde:
        q = q.filter(Programacion.fecha_programada >= desde)
    salida = []
    for p in q.order_by(Programacion.fecha_programada, Programacion.hora_inicio):
        d = programacion_dict(p)
        for eq in d["equipos"]:
            insp = (db.query(Inspeccion).filter(Inspeccion.id_cotizacion_equipo == eq["id_cotizacion_equipo"])
                    .order_by(Inspeccion.id_inspeccion.desc()).first())
            eq["inspeccion"] = {"id_inspeccion": insp.id_inspeccion, "estado": insp.estado} if insp else None
        salida.append(d)
    return salida


@router.get("")
def listar(estado: str | None = None, numero_cotizacion: str | None = None, db: Session = Depends(get_db),
           usuario: Usuario = Depends(require_roles(INSPECTOR, DIRECTOR_TECNICO))):
    q = db.query(Inspeccion)
    if usuario.rol_codigo == INSPECTOR:
        q = q.filter(Inspeccion.id_inspector == usuario.id_usuario)
    if estado:
        q = q.filter(Inspeccion.estado == estado)
    if numero_cotizacion:
        q = q.join(CotizacionEquipo).filter(CotizacionEquipo.codigo_servicio.like(f"{numero_cotizacion.strip()}%"))
    salida = []
    for i in q.order_by(Inspeccion.id_inspeccion.desc()).all():
        d = fila(i, ["id_inspeccion", "numero_inspeccion", "estado", "fecha_inicio", "fecha_fin"])
        d["servicio"] = cot_equipo_dict(i.cotizacion_equipo)
        d["inspector"] = i.inspector.nombre_completo
        salida.append(d)
    return salida


# ============================================
# ABRIR EL INFORME
# ============================================
@router.post("/iniciar", status_code=201)
def iniciar(datos: IniciarIn, db: Session = Depends(get_db), usuario: Usuario = Depends(require_roles(INSPECTOR))):
    if datos.uuid_offline:
        previa = db.query(Inspeccion).filter(Inspeccion.uuid_offline == datos.uuid_offline).first()
        if previa:
            return _detalle(db, previa)  # reintento desde el celular: idempotente
    p = db.get(Programacion, datos.id_programacion)
    if not p or p.id_inspector != usuario.id_usuario or p.estado == "CANCELADA":
        raise HTTPException(404, "Visita no encontrada en su agenda")
    if datos.id_cotizacion_equipo not in {pe.id_cotizacion_equipo for pe in p.equipos}:
        raise HTTPException(400, "El equipo no hace parte de esta visita")
    ce = db.get(CotizacionEquipo, datos.id_cotizacion_equipo)
    if p.tipo_visita == "SEGUNDA":
        return _iniciar_segunda_visita(db, p, ce, usuario)
    abierta = (db.query(Inspeccion).filter(Inspeccion.id_cotizacion_equipo == ce.id_cotizacion_equipo,
                                           Inspeccion.estado.in_(("EN_CURSO", "DEVUELTA"))).first())
    if abierta:
        return _detalle(db, abierta)

    cot, eq = ce.cotizacion, ce.equipo
    ed, cl = cot.edificio, cot.cliente
    # Copia de los datos tal como estaban al abrir el informe (el informe no cambia si luego editan el cliente)
    snapshot = {
        "numero_cotizacion": cot.numero_cotizacion, "codigo_servicio": ce.codigo_servicio,
        "tipo_servicio": ce.tipo_servicio,
        "cliente": {"razon_social": cl.razon_social, "tipo_documento": cl.tipo_documento,
                    "numero_documento": cl.numero_documento, "contacto": cl.contacto_nombre},
        "edificio": fila(ed, CAMPOS_EDIFICIO),
        "equipo": fila(eq, CAMPOS_EQUIPO),
    }
    anterior = (db.query(Inspeccion).join(CotizacionEquipo)
                .filter(CotizacionEquipo.id_equipo == eq.id_equipo, Inspeccion.estado.in_(("APROBADA", "CERRADA")))
                .order_by(Inspeccion.fecha_inicio.desc()).first())
    insp = Inspeccion(
        numero_inspeccion=siguiente_numero(db, "INS"), id_cotizacion_equipo=ce.id_cotizacion_equipo,
        id_programacion=p.id_programacion, id_inspector=usuario.id_usuario, uuid_offline=datos.uuid_offline,
        datos_equipo_json=json.dumps(snapshot, ensure_ascii=False), fecha_inicio=datetime.now(),
        empresa_mantenimiento=ed.empresa_mantenimiento, fecha_puesta_marcha=eq.fecha_puesta_marcha,
        fecha_ultima_inspeccion=anterior.fecha_inicio.date() if anterior else None,
        capacidad_kg=eq.capacidad_kg, capacidad_personas=eq.capacidad_personas, numero_paradas=eq.numero_paradas,
        profundidad_foso_mm=eq.profundidad_foso_mm, recorrido_m=eq.recorrido_m,
        latitud=datos.latitud, longitud=datos.longitud, estado="EN_CURSO",
    )
    db.add(insp)
    db.flush()
    # Variantes conocidas del equipo e instrumentos asignados al inspector se precargan
    for v in eq.variantes:
        insp.variantes.append(InspeccionVariante(id_variante_tipo=v.id_variante_tipo, id_variante_opcion=v.id_variante_opcion))
    for ins in db.query(InstrumentoMedicion).filter(InstrumentoMedicion.id_inspector == usuario.id_usuario,
                                                    InstrumentoMedicion.estado == "ACTIVO"):
        insp.instrumentos.append(InspeccionInstrumento(id_instrumento=ins.id_instrumento))
    if eq.variantes:
        precargar_no_aplica(db, insp)
    cambiar_estado(db, ce, "EN_INSPECCION", usuario)
    p.estado = "EN_CURSO"
    db.commit()
    db.refresh(insp)
    return _detalle(db, insp)


def _iniciar_segunda_visita(db: Session, p: Programacion, ce: CotizacionEquipo, usuario: Usuario):
    insp = (db.query(Inspeccion).filter(Inspeccion.id_cotizacion_equipo == ce.id_cotizacion_equipo)
            .order_by(Inspeccion.id_inspeccion.desc()).first())
    if insp and insp.estado == "EN_SEGUNDA_VISITA" and insp.id_programacion_visita2 == p.id_programacion:
        return _detalle(db, insp)
    if not insp or insp.estado != "APROBADA" or not insp.informe or insp.informe.concepto != "NO_CONFORME":
        raise HTTPException(409, "El equipo no tiene un informe no conforme pendiente de segunda visita")
    insp.estado = "EN_SEGUNDA_VISITA"
    insp.id_programacion_visita2, insp.id_inspector_visita2 = p.id_programacion, usuario.id_usuario
    insp.fecha_visita2 = datetime.now()
    # Las firmas de una segunda visita anterior (si hubo más de una) se reemplazan
    for f in [f for f in insp.firmas if f.numero_visita == 2]:
        insp.firmas.remove(f)
    cambiar_estado(db, ce, "EN_INSPECCION", usuario, "Segunda visita")
    p.estado = "EN_CURSO"
    db.commit()
    db.refresh(insp)
    return _detalle(db, insp)


@router.get("/{id_inspeccion}")
def obtener(id_inspeccion: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    return _detalle(db, _obtener(db, id_inspeccion, usuario))


@router.put("/{id_inspeccion}/encabezado")
def encabezado(id_inspeccion: int, datos: EncabezadoIn, db: Session = Depends(get_db),
               usuario: Usuario = Depends(get_current_user)):
    insp = _obtener(db, id_inspeccion, usuario)
    _editable(insp, usuario)
    for k, v in datos.model_dump(exclude_unset=True).items():
        setattr(insp, k, v)
    db.commit()
    return _detalle(db, insp)


@router.put("/{id_inspeccion}/equipo")
def datos_equipo(id_inspeccion: int, datos: EquipoDatosIn, db: Session = Depends(get_db),
                 usuario: Usuario = Depends(get_current_user)):
    """El inspector registra/corrige los datos del ascensor: quedan en el equipo (para próximas
    inspecciones) y en la copia del informe."""
    insp = _obtener(db, id_inspeccion, usuario)
    _editable(insp, usuario, primera_visita=True)
    equipo = insp.cotizacion_equipo.equipo
    cambios = datos.model_dump(exclude_unset=True)
    for k, v in cambios.items():
        setattr(equipo, k, v)
        if k in CAMPOS_EQUIPO_EN_INSPECCION:
            setattr(insp, k, v)
    db.flush()
    snapshot = json.loads(insp.datos_equipo_json or "{}")
    snapshot["equipo"] = fila(equipo, CAMPOS_EQUIPO)
    insp.datos_equipo_json = json.dumps(snapshot, ensure_ascii=False)
    db.commit()
    return _detalle(db, insp)


# ============================================
# VARIANTES (tracción / hidráulico, enhebrado, máquina...)
# ============================================
@router.put("/{id_inspeccion}/variantes")
def variantes(id_inspeccion: int, datos: list[VarianteIn], db: Session = Depends(get_db),
              usuario: Usuario = Depends(get_current_user)):
    insp = _obtener(db, id_inspeccion, usuario)
    _editable(insp, usuario, primera_visita=True)
    actuales = {v.id_variante_tipo: v for v in insp.variantes}
    equipo = insp.cotizacion_equipo.equipo
    del_equipo = {v.id_variante_tipo: v for v in equipo.variantes}
    for v in datos:
        op = db.get(VarianteOpcion, v.id_variante_opcion)
        if not op or op.id_variante_tipo != v.id_variante_tipo:
            raise HTTPException(400, f"Opción {v.id_variante_opcion} no válida para la variante {v.id_variante_tipo}")
        if v.id_variante_tipo in actuales:
            actuales[v.id_variante_tipo].id_variante_opcion = v.id_variante_opcion
        else:
            insp.variantes.append(InspeccionVariante(**v.model_dump()))
        # El equipo recuerda sus variantes para la próxima inspección
        if v.id_variante_tipo in del_equipo:
            del_equipo[v.id_variante_tipo].id_variante_opcion = v.id_variante_opcion
        else:
            equipo.variantes.append(EquipoVariante(**v.model_dump()))
    precargar_no_aplica(db, insp)
    db.commit()
    db.refresh(insp)
    return _detalle(db, insp)


# ============================================
# CHECKLIST
# ============================================
@router.get("/{id_inspeccion}/checklist")
def checklist(id_inspeccion: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    insp = _obtener(db, id_inspeccion, usuario)
    aplica = items_aplicables(db, insp.id_inspeccion)
    res = {r.id_item: r for r in insp.resultados}
    fotos_por_res = {}
    for f in insp.fotos:
        if f.id_resultado:
            fotos_por_res.setdefault(f.id_resultado, []).append(_foto_dict(f))
    categorias = []
    for cat in db.query(ChecklistCategoria).filter(ChecklistCategoria.activo.is_(True)).order_by(ChecklistCategoria.orden):
        items = (db.query(ChecklistItem).filter(ChecklistItem.id_categoria == cat.id_categoria,
                                                ChecklistItem.activo.is_(True)).order_by(ChecklistItem.orden).all())
        lista = []
        for it in items:
            r = res.get(it.id_item)
            lista.append({
                "id_item": it.id_item, "numero": it.numero, "codigo": it.codigo, "descripcion": it.descripcion,
                "criterio_cumplimiento": it.criterio_cumplimiento, "calificacion": it.calificacion,
                "calificacion_corta": CALIF_CORTA[it.calificacion], "requiere_medicion": it.requiere_medicion,
                "requiere_foto_medicion": it.requiere_foto_medicion, "aplica": aplica.get(it.id_item, True),
                "resultado": fila(r, ["id_resultado", "resultado", "calificacion_defecto", "no_aplica_automatico",
                                      "valor_medido", "unidad_medida", "observacion", "hallazgo_director",
                                      "estado_segunda_visita", "observacion_segunda_visita"]) if r else None,
                "fotos": fotos_por_res.get(r.id_resultado, []) if r else [],
            })
        categorias.append({"id_categoria": cat.id_categoria, "codigo": cat.codigo, "nombre": cat.nombre,
                           "total": len(lista), "calificados": sum(1 for x in lista if x["resultado"]),
                           "items": lista})
    return {"id_inspeccion": insp.id_inspeccion, "resumen": resumen(insp), "categorias": categorias}


@router.put("/{id_inspeccion}/resultados")
def guardar_resultados(id_inspeccion: int, datos: list[ResultadoIn], db: Session = Depends(get_db),
                       usuario: Usuario = Depends(get_current_user)):
    """Guarda en lote (sirve para sincronizar lo que el celular llenó sin señal)."""
    insp = _obtener(db, id_inspeccion, usuario)
    _editable(insp, usuario, primera_visita=True)
    items = {i.id_item: i for i in db.query(ChecklistItem).filter(ChecklistItem.id_item.in_([d.id_item for d in datos]))}
    res = {r.id_item: r for r in insp.resultados}
    es_director = usuario.rol_codigo in (DIRECTOR_TECNICO, ADMIN)
    for d in datos:
        it = items.get(d.id_item)
        if not it:
            raise HTTPException(400, f"Ítem {d.id_item} no existe")
        if d.resultado not in RESULTADOS:
            raise HTTPException(400, f"Resultado inválido: {d.resultado}")
        r = res.get(d.id_item)
        if r is None:
            r = InspeccionResultado(id_item=d.id_item)
            insp.resultados.append(r)
            res[d.id_item] = r
        if es_director and r.resultado != d.resultado and d.resultado == "NO_CUMPLE":
            r.hallazgo_director = True
        r.resultado = d.resultado
        r.calificacion_defecto = it.calificacion if d.resultado == "NO_CUMPLE" else None
        r.no_aplica_automatico = False
        r.valor_medido, r.unidad_medida, r.observacion = d.valor_medido, d.unidad_medida, d.observacion
    insp.fecha_sincronizacion = datetime.now()
    db.commit()
    return {"guardados": len(datos), "resumen": resumen(insp)}


@router.put("/{id_inspeccion}/segunda-visita")
def guardar_segunda_visita(id_inspeccion: int, datos: list[SegundaVisitaIn], db: Session = Depends(get_db),
                           usuario: Usuario = Depends(get_current_user)):
    """Cierre de hallazgos: cada ítem NO CUMPLE se marca CORREGIDO o NO_CORREGIDO."""
    insp = _obtener(db, id_inspeccion, usuario)
    director_revisando = (usuario.rol_codigo in (DIRECTOR_TECNICO, ADMIN) and insp.informe
                          and insp.informe.visita_actual == 2 and insp.informe.estado == "PENDIENTE_REVISION")
    if insp.estado != "EN_SEGUNDA_VISITA" and not director_revisando:
        raise HTTPException(409, "La inspección no está en segunda visita")
    res = {r.id_item: r for r in insp.resultados}
    for d in datos:
        r = res.get(d.id_item)
        if not r or r.resultado != "NO_CUMPLE":
            raise HTTPException(400, f"El ítem {d.id_item} no es un hallazgo (NO CUMPLE) de esta inspección")
        if d.estado_segunda_visita not in ("CORREGIDO", "NO_CORREGIDO"):
            raise HTTPException(400, "estado_segunda_visita debe ser CORREGIDO o NO_CORREGIDO")
        r.estado_segunda_visita, r.observacion_segunda_visita = d.estado_segunda_visita, d.observacion_segunda_visita
    db.commit()
    return {"guardados": len(datos), "resumen": resumen(insp)}


# ============================================
# FOTOS (álbum de ~100 por equipo)
# ============================================
@router.post("/{id_inspeccion}/fotos", status_code=201)
def subir_fotos(id_inspeccion: int, archivos_foto: list[UploadFile] = File(..., alias="archivos"),
                id_item: int | None = Form(None), descripcion: str | None = Form(None),
                uuid_offline: str | None = Form(None), db: Session = Depends(get_db),
                usuario: Usuario = Depends(get_current_user)):
    insp = _obtener(db, id_inspeccion, usuario)
    _editable(insp, usuario)
    if uuid_offline and len(archivos_foto) == 1:
        previa = db.query(InspeccionFoto).filter(InspeccionFoto.uuid_offline == uuid_offline).first()
        if previa:
            return [_foto_dict(previa)]
    id_resultado = None
    if id_item:
        r = next((x for x in insp.resultados if x.id_item == id_item), None)
        if r is None:
            r = InspeccionResultado(id_item=id_item, resultado="NO_VERIFICADO")
            insp.resultados.append(r)
            db.flush()
        id_resultado = r.id_resultado
    orden = max((f.orden for f in insp.fotos), default=0)
    nuevas = []
    for a in archivos_foto:
        orden += 1
        info = archivos.guardar_foto(insp.id_inspeccion, a)
        f = InspeccionFoto(id_resultado=id_resultado, descripcion=descripcion, orden=orden,
                           uuid_offline=uuid_offline if len(archivos_foto) == 1 else None,
                           fecha_captura=datetime.now(), **info)
        insp.fotos.append(f)
        nuevas.append(f)
    db.commit()
    return [_foto_dict(f) for f in nuevas]


@router.get("/{id_inspeccion}/fotos")
def listar_fotos(id_inspeccion: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    return [_foto_dict(f) for f in _obtener(db, id_inspeccion, usuario).fotos]


@router.put("/{id_inspeccion}/fotos/{id_foto}")
def actualizar_foto(id_inspeccion: int, id_foto: int, datos: FotoUpdate, db: Session = Depends(get_db),
                    usuario: Usuario = Depends(get_current_user)):
    insp = _obtener(db, id_inspeccion, usuario)
    _editable(insp, usuario)
    f = next((x for x in insp.fotos if x.id_foto == id_foto), None)
    if not f:
        raise HTTPException(404, "Foto no encontrada")
    cambios = datos.model_dump(exclude_unset=True)
    if "id_item" in cambios:
        id_item = cambios.pop("id_item")
        r = next((x for x in insp.resultados if x.id_item == id_item), None) if id_item else None
        f.id_resultado = r.id_resultado if r else None
    for k, v in cambios.items():
        setattr(f, k, v)
    db.commit()
    return _foto_dict(f)


@router.delete("/{id_inspeccion}/fotos/{id_foto}", status_code=204)
def borrar_foto(id_inspeccion: int, id_foto: int, db: Session = Depends(get_db),
                usuario: Usuario = Depends(require_roles(INSPECTOR))):
    insp = _obtener(db, id_inspeccion, usuario)
    _editable(insp, usuario)
    f = next((x for x in insp.fotos if x.id_foto == id_foto), None)
    if not f:
        raise HTTPException(404, "Foto no encontrada")
    archivos.borrar(f.ruta_archivo)
    archivos.borrar(f.ruta_miniatura)
    insp.fotos.remove(f)
    db.commit()


# ============================================
# INSTRUMENTOS Y MEDICIONES
# ============================================
@router.put("/{id_inspeccion}/instrumentos")
def instrumentos(id_inspeccion: int, ids_instrumento: list[int], db: Session = Depends(get_db),
                 usuario: Usuario = Depends(get_current_user)):
    insp = _obtener(db, id_inspeccion, usuario)
    _editable(insp, usuario)
    validos = {i.id_instrumento for i in db.query(InstrumentoMedicion).filter(InstrumentoMedicion.id_instrumento.in_(ids_instrumento))}
    insp.instrumentos.clear()
    db.flush()
    for i in dict.fromkeys(ids_instrumento):
        if i not in validos:
            raise HTTPException(400, f"Instrumento {i} no existe")
        insp.instrumentos.append(InspeccionInstrumento(id_instrumento=i))
    db.commit()
    return _detalle(db, insp)


@router.put("/{id_inspeccion}/mediciones")
def mediciones(id_inspeccion: int, datos: list[MedicionIn], db: Session = Depends(get_db),
               usuario: Usuario = Depends(get_current_user)):
    insp = _obtener(db, id_inspeccion, usuario)
    _editable(insp, usuario)
    insp.mediciones.clear()
    db.flush()
    for m in datos:
        insp.mediciones.append(InspeccionMedicion(**m.model_dump()))
    db.commit()
    return _detalle(db, insp)


# ============================================
# FIRMAS: inspector, técnico de mantenimiento y representante del edificio
# ============================================
@router.post("/{id_inspeccion}/firmas", status_code=201)
def firmar(id_inspeccion: int, datos: FirmaIn, db: Session = Depends(get_db),
           usuario: Usuario = Depends(require_roles(INSPECTOR))):
    insp = _obtener(db, id_inspeccion, usuario)
    permitido = insp.estado in ("EN_CURSO", "DEVUELTA") if datos.numero_visita == 1 else insp.estado == "EN_SEGUNDA_VISITA"
    if not permitido:
        raise HTTPException(409, f"La inspección está {insp.estado}; no se puede firmar")
    if datos.tipo_firmante not in TIPOS_FIRMANTE:
        raise HTTPException(400, f"Tipo de firmante inválido: {datos.tipo_firmante}")
    ruta = archivos.guardar_firma_base64(f"inspecciones/{insp.id_inspeccion}/firmas", datos.firma_base64)
    previa = next((f for f in insp.firmas if f.tipo_firmante == datos.tipo_firmante
                   and f.numero_visita == datos.numero_visita), None)
    if previa:
        archivos.borrar(previa.ruta_firma)
        insp.firmas.remove(previa)
        db.flush()
    insp.firmas.append(InspeccionFirma(
        numero_visita=datos.numero_visita, tipo_firmante=datos.tipo_firmante,
        id_usuario=usuario.id_usuario if datos.tipo_firmante == "INSPECTOR" else None,
        nombre=datos.nombre, documento=datos.documento, cargo=datos.cargo, empresa=datos.empresa,
        ruta_firma=ruta, fecha_firma=datetime.now(),
    ))
    if datos.tipo_firmante == "TECNICO_MANTENIMIENTO" and not insp.tecnico_mantenimiento:
        insp.tecnico_mantenimiento = datos.nombre
    db.commit()
    return _detalle(db, insp)


# ============================================
# FINALIZAR -> pasa al director técnico
# ============================================
@router.get("/{id_inspeccion}/validar")
def validar(id_inspeccion: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    insp = _obtener(db, id_inspeccion, usuario)
    errores = (pendientes_segunda_visita(insp) if insp.estado == "EN_SEGUNDA_VISITA"
               else pendientes_para_finalizar(db, insp))
    return {"puede_finalizar": not errores, "pendientes": errores}


@router.post("/{id_inspeccion}/finalizar")
def finalizar(id_inspeccion: int, db: Session = Depends(get_db), usuario: Usuario = Depends(require_roles(INSPECTOR))):
    insp = _obtener(db, id_inspeccion, usuario)
    if insp.estado == "EN_SEGUNDA_VISITA":
        return _finalizar_segunda_visita(db, insp, usuario)
    if insp.estado not in ("EN_CURSO", "DEVUELTA"):
        raise HTTPException(409, f"La inspección ya está {insp.estado}")
    errores = pendientes_para_finalizar(db, insp)
    if errores:
        raise HTTPException(422, {"mensaje": "La inspección tiene pendientes", "pendientes": errores})

    insp.estado, insp.fecha_fin = "FINALIZADA", datetime.now()
    if insp.informe:
        insp.informe.estado = "PENDIENTE_REVISION"
    else:
        db.add(Informe(numero_informe=siguiente_numero(db, "INF"), id_inspeccion=insp.id_inspeccion,
                       estado="PENDIENTE_REVISION"))
    cambiar_estado(db, insp.cotizacion_equipo, "EN_REVISION", usuario)
    p = insp.programacion
    if all(pe.cotizacion_equipo.estado not in ("PROGRAMADO", "EN_INSPECCION") for pe in p.equipos):
        p.estado = "REALIZADA"
    ce = insp.cotizacion_equipo
    notificar(db, usuarios_por_rol(db, DIRECTOR_TECNICO), f"Informe por revisar {ce.codigo_servicio}",
              f"{insp.inspector.nombre_completo} finalizó la inspección de {ce.equipo.identificacion} "
              f"en {ce.cotizacion.edificio.nombre}.", "INFORME", insp.id_inspeccion, "/informes")
    db.commit()
    db.refresh(insp)
    return _detalle(db, insp)


def _finalizar_segunda_visita(db: Session, insp: Inspeccion, usuario: Usuario):
    errores = pendientes_segunda_visita(insp)
    if errores:
        raise HTTPException(422, {"mensaje": "La segunda visita tiene pendientes", "pendientes": errores})
    insp.estado = "FINALIZADA"
    inf = insp.informe
    inf.estado, inf.visita_actual = "PENDIENTE_REVISION", 2
    ce = insp.cotizacion_equipo
    cambiar_estado(db, ce, "EN_REVISION", usuario, "Segunda visita finalizada")
    p2 = db.get(Programacion, insp.id_programacion_visita2)
    if all(pe.cotizacion_equipo.estado not in ("PROGRAMADO", "EN_INSPECCION") for pe in p2.equipos):
        p2.estado = "REALIZADA"
    r = resumen(insp)
    notificar(db, usuarios_por_rol(db, DIRECTOR_TECNICO), f"Segunda visita por revisar {ce.codigo_servicio}",
              f"{usuario.nombre_completo} cerró la segunda visita de {ce.equipo.identificacion}: "
              f"{r['corregidos']} corregidos, {r['no_corregidos']} no corregidos.", "INFORME",
              insp.id_inspeccion, "/informes")
    db.commit()
    db.refresh(insp)
    return _detalle(db, insp)
