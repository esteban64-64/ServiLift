# app/routes/programacion.py
# Programación asigna fecha, hora e inspector a los equipos aprobados y notifica al inspector.

from datetime import date, time

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Cotizacion, CotizacionEquipo, Programacion, ProgramacionEquipo, Rol, Usuario
from app.routes.serializers import cot_equipo_dict, cotizacion_dict, programacion_dict
from app.security import INSPECTOR, PROGRAMACION, get_current_user, require_roles
from app.services.flujo import cambiar_estado, notificar, registrar_evento

router = APIRouter(prefix="/programacion", tags=["Programación"])


# Estado en que debe estar el equipo para programar cada tipo de visita
ESTADO_POR_VISITA = {"PRIMERA": "POR_PROGRAMAR", "SEGUNDA": "SEGUNDA_VISITA_SOLICITADA"}


class ProgramacionIn(BaseModel):
    id_cotizacion: int
    id_inspector: int
    fecha_programada: date
    hora_inicio: time
    hora_fin_estimada: time | None = None
    ids_cotizacion_equipo: list[int] = Field(min_length=1)
    tipo_visita: str = "PRIMERA"
    observaciones: str | None = None


class ReprogramarIn(BaseModel):
    id_inspector: int | None = None
    fecha_programada: date | None = None
    hora_inicio: time | None = None
    hora_fin_estimada: time | None = None
    motivo_cambio: str


class CancelarIn(BaseModel):
    motivo_cambio: str


def _inspector(db: Session, id_usuario: int) -> Usuario:
    u = db.query(Usuario).join(Rol).filter(Usuario.id_usuario == id_usuario, Rol.codigo == INSPECTOR,
                                           Usuario.estado == "ACTIVO").first()
    if not u:
        raise HTTPException(400, "El usuario seleccionado no es un inspector activo")
    return u


def _texto_visita(p: Programacion) -> str:
    equipos = ", ".join(pe.cotizacion_equipo.equipo.identificacion for pe in p.equipos)
    return (f"{p.cotizacion.edificio.nombre} ({p.cotizacion.edificio.direccion}) el "
            f"{p.fecha_programada:%d/%m/%Y} a las {p.hora_inicio:%H:%M}. Equipos: {equipos}.")


@router.get("/pendientes")
def pendientes(db: Session = Depends(get_db), _: Usuario = Depends(require_roles(PROGRAMACION))):
    """Bandeja: equipos POR_PROGRAMAR (primera visita) y con segunda visita solicitada (cierre de hallazgos)."""
    cots = (db.query(Cotizacion).join(CotizacionEquipo)
            .filter(CotizacionEquipo.estado.in_(ESTADO_POR_VISITA.values())).distinct()
            .order_by(Cotizacion.fecha_envio_programacion).all())
    salida = []
    for c in cots:
        d = cotizacion_dict(c, detalle=True)
        d["equipos_por_programar"] = [cot_equipo_dict(ce) for ce in c.equipos if ce.estado == "POR_PROGRAMAR"]
        d["equipos_segunda_visita"] = [cot_equipo_dict(ce) for ce in c.equipos if ce.estado == "SEGUNDA_VISITA_SOLICITADA"]
        salida.append(d)
    return salida


@router.get("")
def calendario(desde: date | None = None, hasta: date | None = None, id_inspector: int | None = None,
               db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    q = db.query(Programacion).filter(Programacion.estado != "CANCELADA")
    if usuario.rol_codigo == INSPECTOR:
        q = q.filter(Programacion.id_inspector == usuario.id_usuario)
    elif usuario.rol_codigo not in (PROGRAMACION, "ADMIN", "DIRECTOR_TECNICO", "ASESOR"):
        raise HTTPException(403, "No tiene permisos para ver la programación")
    elif id_inspector:
        q = q.filter(Programacion.id_inspector == id_inspector)
    if desde:
        q = q.filter(Programacion.fecha_programada >= desde)
    if hasta:
        q = q.filter(Programacion.fecha_programada <= hasta)
    return [programacion_dict(p) for p in q.order_by(Programacion.fecha_programada, Programacion.hora_inicio)]


@router.post("", status_code=201)
def programar(datos: ProgramacionIn, db: Session = Depends(get_db),
              usuario: Usuario = Depends(require_roles(PROGRAMACION))):
    cot = db.get(Cotizacion, datos.id_cotizacion)
    if not cot:
        raise HTTPException(404, "Cotización no encontrada")
    inspector = _inspector(db, datos.id_inspector)
    if datos.tipo_visita not in ESTADO_POR_VISITA:
        raise HTTPException(400, "tipo_visita debe ser PRIMERA o SEGUNDA")
    requerido = ESTADO_POR_VISITA[datos.tipo_visita]
    equipos = {ce.id_cotizacion_equipo: ce for ce in cot.equipos}
    p = Programacion(id_cotizacion=cot.id_cotizacion, id_inspector=inspector.id_usuario,
                     id_programador=usuario.id_usuario, fecha_programada=datos.fecha_programada,
                     hora_inicio=datos.hora_inicio, hora_fin_estimada=datos.hora_fin_estimada,
                     tipo_visita=datos.tipo_visita, observaciones=datos.observaciones)
    db.add(p)
    db.flush()
    for id_ce in dict.fromkeys(datos.ids_cotizacion_equipo):
        ce = equipos.get(id_ce)
        if not ce:
            raise HTTPException(400, f"El equipo {id_ce} no pertenece a la cotización {cot.numero_cotizacion}")
        if ce.estado != requerido:
            raise HTTPException(409, f"{ce.codigo_servicio} está en {ce.estado}; para la visita "
                                     f"{datos.tipo_visita.lower()} debe estar en {requerido}")
        p.equipos.append(ProgramacionEquipo(id_cotizacion_equipo=id_ce))
        cambiar_estado(db, ce, "PROGRAMADO", usuario, f"Visita {datos.fecha_programada} con {inspector.nombre_completo}")
    db.flush()
    db.refresh(p)
    titulo = "Nueva inspección" if datos.tipo_visita == "PRIMERA" else "Segunda visita (cierre de hallazgos)"
    notificar(db, [inspector], f"{titulo} {cot.numero_cotizacion}", _texto_visita(p),
              "PROGRAMACION", p.id_programacion, "/inspecciones/agenda")
    db.commit()
    return programacion_dict(p)


@router.put("/{id_programacion}")
def reprogramar(id_programacion: int, datos: ReprogramarIn, db: Session = Depends(get_db),
                usuario: Usuario = Depends(require_roles(PROGRAMACION))):
    p = db.get(Programacion, id_programacion)
    if not p or p.estado in ("CANCELADA", "REALIZADA"):
        raise HTTPException(404, "Programación no encontrada o ya cerrada")
    anterior = p.inspector
    if datos.id_inspector and datos.id_inspector != p.id_inspector:
        p.id_inspector = _inspector(db, datos.id_inspector).id_usuario
    for campo in ("fecha_programada", "hora_inicio", "hora_fin_estimada"):
        v = getattr(datos, campo)
        if v is not None:
            setattr(p, campo, v)
    p.estado, p.motivo_cambio = "REPROGRAMADA", datos.motivo_cambio
    db.flush()
    db.refresh(p)
    for pe in p.equipos:
        registrar_evento(db, pe.cotizacion_equipo, usuario,
                         f"Visita reprogramada: {p.fecha_programada} {p.hora_inicio:%H:%M} con "
                         f"{p.inspector.nombre_completo}. Motivo: {datos.motivo_cambio}")
    db.refresh(p)
    destinatarios = {anterior.id_usuario: anterior, p.inspector.id_usuario: p.inspector}.values()
    notificar(db, destinatarios, f"Inspección reprogramada {p.cotizacion.numero_cotizacion}",
              _texto_visita(p) + f" Motivo: {datos.motivo_cambio}", "PROGRAMACION", p.id_programacion,
              "/inspecciones/agenda")
    db.commit()
    return programacion_dict(p)


@router.post("/{id_programacion}/cancelar")
def cancelar(id_programacion: int, datos: CancelarIn, db: Session = Depends(get_db),
             usuario: Usuario = Depends(require_roles(PROGRAMACION))):
    p = db.get(Programacion, id_programacion)
    if not p or p.estado in ("CANCELADA", "REALIZADA"):
        raise HTTPException(404, "Programación no encontrada o ya cerrada")
    for pe in p.equipos:
        if pe.cotizacion_equipo.estado == "PROGRAMADO":
            cambiar_estado(db, pe.cotizacion_equipo, ESTADO_POR_VISITA[p.tipo_visita], usuario, datos.motivo_cambio)
    p.estado, p.motivo_cambio = "CANCELADA", datos.motivo_cambio
    notificar(db, [p.inspector], f"Inspección cancelada {p.cotizacion.numero_cotizacion}",
              _texto_visita(p) + f" Motivo: {datos.motivo_cambio}", "PROGRAMACION", p.id_programacion)
    db.commit()
    return programacion_dict(p)
