# app/routes/cotizaciones.py
# Asesor crea la cotización (un edificio, equipos elegidos uno a uno con su valor),
# la envía al cliente; el cliente aprueba o rechaza; el asesor la envía a programación.

from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Cotizacion, CotizacionEquipo, Edificio, Usuario
from app.routes.serializers import cotizacion_dict
from app.security import ASESOR, CLIENTE, PROGRAMACION, get_current_user, require_roles
from app.services.flujo import (
    cambiar_estado, notificar, registrar_evento, siguiente_numero, usuarios_del_cliente, usuarios_por_rol,
)

router = APIRouter(prefix="/cotizaciones", tags=["Cotizaciones"])

TIPOS_SERVICIO = {"INSPECCION_INICIAL", "INSPECCION_PERIODICA", "REINSPECCION", "EXTRAORDINARIA"}


class EquipoCotizadoIn(BaseModel):
    id_equipo: int
    valor: Decimal = Field(ge=0)
    tipo_servicio: str = "INSPECCION_PERIODICA"
    descripcion: str | None = None


class CotizacionIn(BaseModel):
    id_edificio: int
    equipos: list[EquipoCotizadoIn] = Field(min_length=1)
    dias_validez: int = 30
    iva_porcentaje: Decimal = Decimal("19")
    condiciones: str | None = None
    observaciones: str | None = None


class RespuestaClienteIn(BaseModel):
    aprobada: bool
    comentario: str | None = None


class MotivoIn(BaseModel):
    motivo: str | None = None


# ============================================
# AYUDAS
# ============================================
def _obtener(db: Session, id_cotizacion: int, usuario: Usuario) -> Cotizacion:
    c = db.get(Cotizacion, id_cotizacion)
    if not c:
        raise HTTPException(404, "Cotización no encontrada")
    if usuario.rol_codigo == CLIENTE and (c.id_cliente != usuario.id_cliente or c.estado == "BORRADOR"):
        raise HTTPException(404, "Cotización no encontrada")
    return c


def _dos(v: Decimal) -> Decimal:
    return v.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _cargar_equipos(db: Session, cot: Cotizacion, edificio: Edificio, equipos: list[EquipoCotizadoIn]):
    ids = [e.id_equipo for e in equipos]
    if len(ids) != len(set(ids)):
        raise HTTPException(400, "Un equipo está repetido en la cotización")
    validos = {e.id_equipo for e in edificio.equipos}
    ajenos = set(ids) - validos
    if ajenos:
        raise HTTPException(400, f"Los equipos {sorted(ajenos)} no pertenecen al edificio {edificio.nombre}")
    cot.equipos.clear()
    db.flush()
    for i, e in enumerate(equipos, start=1):
        if e.tipo_servicio not in TIPOS_SERVICIO:
            raise HTTPException(400, f"Tipo de servicio inválido: {e.tipo_servicio}")
        cot.equipos.append(CotizacionEquipo(
            id_equipo=e.id_equipo, codigo_servicio=f"{cot.numero_cotizacion}-{i:02d}",
            tipo_servicio=e.tipo_servicio, descripcion=e.descripcion, valor=_dos(e.valor),
            estado="PENDIENTE_APROBACION",
        ))
    cot.subtotal = _dos(sum((e.valor for e in equipos), Decimal("0")))
    cot.iva_valor = _dos(cot.subtotal * Decimal(cot.iva_porcentaje) / 100)
    cot.total = cot.subtotal + cot.iva_valor


# ============================================
# CONSULTAS
# ============================================
@router.get("")
def listar(numero: str | None = None, estado: str | None = None, id_cliente: int | None = None,
           id_edificio: int | None = None, solo_mias: bool = False,
           db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    q = db.query(Cotizacion)
    if usuario.rol_codigo == CLIENTE:
        q = q.filter(Cotizacion.id_cliente == usuario.id_cliente, Cotizacion.estado != "BORRADOR")
    elif id_cliente:
        q = q.filter(Cotizacion.id_cliente == id_cliente)
    if solo_mias:
        q = q.filter(Cotizacion.id_asesor == usuario.id_usuario)
    if numero:
        q = q.filter(Cotizacion.numero_cotizacion.like(f"%{numero.strip()}%"))
    if estado:
        q = q.filter(Cotizacion.estado == estado)
    if id_edificio:
        q = q.filter(Cotizacion.id_edificio == id_edificio)
    return [cotizacion_dict(c) for c in q.order_by(Cotizacion.id_cotizacion.desc()).all()]


@router.get("/{id_cotizacion}")
def obtener(id_cotizacion: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    return cotizacion_dict(_obtener(db, id_cotizacion, usuario), detalle=True)


# ============================================
# ASESOR: CREAR / EDITAR / ENVIAR
# ============================================
@router.post("", status_code=201)
def crear(datos: CotizacionIn, db: Session = Depends(get_db), usuario: Usuario = Depends(require_roles(ASESOR))):
    edificio = db.get(Edificio, datos.id_edificio)
    if not edificio:
        raise HTTPException(404, "Edificio no encontrado")
    cot = Cotizacion(
        numero_cotizacion=siguiente_numero(db, "COT"), id_cliente=edificio.id_cliente,
        id_edificio=edificio.id_edificio, id_asesor=usuario.id_usuario, fecha_cotizacion=date.today(),
        dias_validez=datos.dias_validez, iva_porcentaje=datos.iva_porcentaje,
        condiciones=datos.condiciones, observaciones=datos.observaciones, estado="BORRADOR",
    )
    db.add(cot)
    db.flush()
    _cargar_equipos(db, cot, edificio, datos.equipos)
    db.commit()
    db.refresh(cot)
    return cotizacion_dict(cot, detalle=True)


@router.put("/{id_cotizacion}")
def editar(id_cotizacion: int, datos: CotizacionIn, db: Session = Depends(get_db),
           usuario: Usuario = Depends(require_roles(ASESOR))):
    cot = _obtener(db, id_cotizacion, usuario)
    if cot.estado != "BORRADOR":
        raise HTTPException(409, "Solo se puede editar una cotización en borrador")
    if datos.id_edificio != cot.id_edificio:
        raise HTTPException(400, "No se puede cambiar el edificio; cree una cotización nueva")
    cot.dias_validez, cot.iva_porcentaje = datos.dias_validez, datos.iva_porcentaje
    cot.condiciones, cot.observaciones = datos.condiciones, datos.observaciones
    _cargar_equipos(db, cot, cot.edificio, datos.equipos)
    db.commit()
    db.refresh(cot)
    return cotizacion_dict(cot, detalle=True)


@router.post("/{id_cotizacion}/enviar-cliente")
def enviar_cliente(id_cotizacion: int, db: Session = Depends(get_db),
                   usuario: Usuario = Depends(require_roles(ASESOR))):
    cot = _obtener(db, id_cotizacion, usuario)
    if cot.estado not in ("BORRADOR", "ENVIADA_CLIENTE"):
        raise HTTPException(409, f"La cotización está en {cot.estado}")
    destinatarios = usuarios_del_cliente(db, cot.id_cliente)
    if not destinatarios:
        raise HTTPException(409, "El cliente no tiene usuario en el portal. Créelo antes de enviar la cotización.")
    cot.estado = "ENVIADA_CLIENTE"
    cot.fecha_envio_cliente = datetime.now()
    for ce in cot.equipos:
        registrar_evento(db, ce, usuario, f"Cotización {cot.numero_cotizacion} enviada al cliente (${ce.valor:,.0f})".replace(",", "."))
    notificar(db, destinatarios, f"Nueva cotización {cot.numero_cotizacion}",
              f"Tiene una cotización por aprobar para {cot.edificio.nombre} ({len(cot.equipos)} equipos).",
              "COTIZACION", cot.id_cotizacion, f"/cotizaciones/{cot.id_cotizacion}")
    db.commit()
    return cotizacion_dict(cot, detalle=True)


# ============================================
# CLIENTE: APROBAR / RECHAZAR
# ============================================
@router.post("/{id_cotizacion}/responder")
def responder(id_cotizacion: int, datos: RespuestaClienteIn, db: Session = Depends(get_db),
              usuario: Usuario = Depends(require_roles(CLIENTE))):
    cot = _obtener(db, id_cotizacion, usuario)
    if cot.estado != "ENVIADA_CLIENTE":
        raise HTTPException(409, "Esta cotización no está pendiente de aprobación")
    cot.estado = "APROBADA_CLIENTE" if datos.aprobada else "RECHAZADA_CLIENTE"
    cot.fecha_respuesta_cliente = datetime.now()
    cot.id_usuario_respuesta = usuario.id_usuario
    cot.comentario_cliente = datos.comentario
    for ce in cot.equipos:
        cambiar_estado(db, ce, "APROBADO_CLIENTE" if datos.aprobada else "RECHAZADO", usuario, datos.comentario)
    notificar(db, [cot.asesor], f"Cotización {cot.numero_cotizacion} {'aprobada' if datos.aprobada else 'rechazada'}",
              f"{cot.cliente.razon_social} {'aprobó' if datos.aprobada else 'rechazó'} la cotización."
              + (f" Comentario: {datos.comentario}" if datos.comentario else ""),
              "COTIZACION", cot.id_cotizacion, f"/cotizaciones/{cot.id_cotizacion}")
    db.commit()
    return cotizacion_dict(cot, detalle=True)


# ============================================
# ASESOR: ACEPTAR Y ENVIAR A PROGRAMACIÓN
# ============================================
@router.post("/{id_cotizacion}/enviar-programacion")
def enviar_programacion(id_cotizacion: int, db: Session = Depends(get_db),
                        usuario: Usuario = Depends(require_roles(ASESOR))):
    cot = _obtener(db, id_cotizacion, usuario)
    if cot.estado != "APROBADA_CLIENTE":
        raise HTTPException(409, "El cliente todavía no ha aprobado la cotización")
    cot.estado = "ENVIADA_PROGRAMACION"
    cot.fecha_envio_programacion = datetime.now()
    for ce in cot.equipos:
        cambiar_estado(db, ce, "POR_PROGRAMAR", usuario)
    notificar(db, usuarios_por_rol(db, PROGRAMACION), f"Por programar: {cot.numero_cotizacion}",
              f"{cot.edificio.nombre} - {len(cot.equipos)} equipos listos para programar.",
              "PROGRAMACION", cot.id_cotizacion, "/programacion/pendientes")
    db.commit()
    return cotizacion_dict(cot, detalle=True)


@router.post("/{id_cotizacion}/anular")
def anular(id_cotizacion: int, datos: MotivoIn, db: Session = Depends(get_db),
           usuario: Usuario = Depends(require_roles(ASESOR))):
    cot = _obtener(db, id_cotizacion, usuario)
    if any(ce.estado in ("EN_INSPECCION", "EN_REVISION", "INFORME_APROBADO", "CERTIFICADO_LISTO") for ce in cot.equipos):
        raise HTTPException(409, "No se puede anular: ya hay equipos inspeccionados")
    for ce in cot.equipos:
        if ce.estado not in ("RECHAZADO", "ANULADO"):
            cambiar_estado(db, ce, "ANULADO", usuario, datos.motivo)
    cot.estado = "ANULADA"
    cot.observaciones = ((cot.observaciones or "") + f"\nAnulada: {datos.motivo or ''}").strip()
    db.commit()
    return cotizacion_dict(cot, detalle=True)
