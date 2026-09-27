# app/routes/seguimiento.py
# Búsqueda por número de cotización y estado por equipo (también es la vista del portal del cliente).

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Certificado, CotizacionEquipo, HistorialEstado, Informe, Inspeccion, Usuario
from app.routes.serializers import fila, plazo_dict
from app.security import ADMIN, ASESOR, CLIENTE, INSPECTOR, PROGRAMACION, get_current_user
from app.services.flujo import (
    ETIQUETAS_ESTADO, cambiar_estado, notificar, usuarios_del_cliente, usuarios_por_rol,
)

router = APIRouter(tags=["Seguimiento"])


def _valor(v):
    """Fechas a ISO y horas (MySQL TIME llega como timedelta) a HH:MM:SS."""
    if isinstance(v, timedelta):
        seg = int(v.total_seconds())
        return f"{seg // 3600:02d}:{seg % 3600 // 60:02d}:{seg % 60:02d}"
    return v.isoformat() if hasattr(v, "isoformat") else v


def _enlaces(db: Session, id_cotizacion_equipo: int, rol: str) -> dict:
    """Informe y certificado descargables, respetando lo que el cliente puede ver."""
    insp = (db.query(Inspeccion).filter(Inspeccion.id_cotizacion_equipo == id_cotizacion_equipo)
            .order_by(Inspeccion.id_inspeccion.desc()).first())
    inf = insp.informe if insp else None
    cert = db.query(Certificado).filter(Certificado.id_cotizacion_equipo == id_cotizacion_equipo,
                                        Certificado.estado != "ANULADO").first()
    if rol == CLIENTE:
        inf = inf if inf and (inf.estado == "APROBADO" or inf.ruta_pdf_visita1) else None
        cert = cert if cert and cert.estado == "ENVIADO_CLIENTE" else None
    return {
        "id_inspeccion": insp.id_inspeccion if insp and rol != CLIENTE else None,
        "id_informe": inf.id_informe if inf else None,
        "pdf_informe": f"/informes/{inf.id_informe}/pdf" if inf and inf.ruta_pdf else None,
        "informe_visita1": bool(inf and (inf.ruta_pdf_visita1 or (inf.ruta_pdf and inf.visita_actual == 1))),
        "informe_visita2": bool(inf and inf.ruta_pdf and inf.visita_actual == 2 and inf.estado == "APROBADO"),
        "id_certificado": cert.id_certificado if cert else None,
        "pdf_certificado": f"/certificados/{cert.id_certificado}/pdf" if cert and cert.ruta_pdf else None,
    }


@router.get("/seguimiento")
def seguimiento(numero_cotizacion: str | None = None, id_cliente: int | None = None, estado: str | None = None,
                id_edificio: int | None = None, db: Session = Depends(get_db),
                usuario: Usuario = Depends(get_current_user)):
    """Una fila por equipo cotizado con su estado actual, programación, informe y certificado."""
    filtros, params = ["1=1"], {}
    if usuario.rol_codigo == CLIENTE:
        filtros.append("id_cliente = :cli AND estado_cotizacion <> 'BORRADOR'")
        params["cli"] = usuario.id_cliente
    elif id_cliente:
        filtros.append("id_cliente = :cli")
        params["cli"] = id_cliente
    if usuario.rol_codigo == INSPECTOR:  # solo los equipos que le han programado
        filtros.append("v.codigo_servicio IN (SELECT ce2.codigo_servicio FROM cotizacion_equipo ce2 "
                       "JOIN programacion_equipo pe ON pe.id_cotizacion_equipo = ce2.id_cotizacion_equipo "
                       "JOIN programacion p ON p.id_programacion = pe.id_programacion WHERE p.id_inspector = :insp)")
        params["insp"] = usuario.id_usuario
    if numero_cotizacion:
        filtros.append("numero_cotizacion LIKE :num")
        params["num"] = f"%{numero_cotizacion.strip()}%"
    if estado:
        filtros.append("estado_equipo = :est")
        params["est"] = estado
    if id_edificio:
        filtros.append("id_edificio = :edi")
        params["edi"] = id_edificio
    sql = (f"SELECT v.*, ce.id_cotizacion_equipo FROM v_seguimiento_equipo v "
           f"JOIN cotizacion_equipo ce ON ce.codigo_servicio = v.codigo_servicio "
           f"WHERE {' AND '.join(filtros)} ORDER BY v.numero_cotizacion DESC, v.codigo_servicio")
    salida = []
    for r in db.execute(text(sql), params).mappings():
        d = {k: _valor(v) for k, v in r.items() if k not in ("pdf_informe", "pdf_certificado")}
        d["estado_etiqueta"] = ETIQUETAS_ESTADO.get(r["estado_equipo"], r["estado_equipo"])
        d.update(plazo_dict(r["plazo_dias"], r["fecha_limite_correccion"], r["estado_equipo"]))
        if usuario.rol_codigo == CLIENTE:  # el cliente no ve datos internos de revisión
            for k in ("estado_inspeccion", "numero_inspeccion"):
                d.pop(k, None)
            if r["estado_informe"] != "APROBADO":
                d["numero_informe"] = d["estado_informe"] = d["concepto"] = None
            if r["estado_certificado"] != "ENVIADO_CLIENTE":
                d["numero_certificado"] = d["estado_certificado"] = d["fecha_vencimiento"] = None
        d.update(_enlaces(db, r["id_cotizacion_equipo"], usuario.rol_codigo))
        salida.append(d)
    return salida


@router.get("/seguimiento/equipo/{id_cotizacion_equipo}/historial")
def historial(id_cotizacion_equipo: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    ce = db.get(CotizacionEquipo, id_cotizacion_equipo)
    if not ce or (usuario.rol_codigo == CLIENTE and ce.cotizacion.id_cliente != usuario.id_cliente):
        raise HTTPException(404, "Equipo no encontrado")
    eventos = (db.query(HistorialEstado).filter(HistorialEstado.id_cotizacion_equipo == id_cotizacion_equipo)
               .order_by(HistorialEstado.fecha, HistorialEstado.id_historial).all())
    salida = []
    for h in eventos:
        d = fila(h, ["estado_anterior", "estado_nuevo", "fecha"])
        d["evento"] = h.estado_anterior == h.estado_nuevo   # hecho sin cambio de estado
        d["estado_etiqueta"] = (h.comentario if d["evento"] else ETIQUETAS_ESTADO.get(h.estado_nuevo, h.estado_nuevo))
        if usuario.rol_codigo != CLIENTE:
            d["usuario"] = h.usuario.nombre_completo if h.usuario else None
            d["comentario"] = None if d["evento"] else h.comentario
        salida.append(d)
    return {"codigo_servicio": ce.codigo_servicio, "numero_cotizacion": ce.cotizacion.numero_cotizacion,
            "equipo": ce.equipo.identificacion, "edificio": ce.cotizacion.edificio.nombre,
            "estado_actual": ce.estado, "estado_etiqueta": ETIQUETAS_ESTADO.get(ce.estado, ce.estado),
            "historial": salida}


class SolicitudIn(BaseModel):
    comentario: str | None = None


@router.post("/seguimiento/equipo/{id_cotizacion_equipo}/solicitar-segunda-visita")
def solicitar_segunda_visita(id_cotizacion_equipo: int, datos: SolicitudIn, db: Session = Depends(get_db),
                             usuario: Usuario = Depends(get_current_user)):
    """El cliente (o su asesor) informa que corrigió los hallazgos y pide la visita de cierre."""
    ce = db.get(CotizacionEquipo, id_cotizacion_equipo)
    if not ce or (usuario.rol_codigo == CLIENTE and ce.cotizacion.id_cliente != usuario.id_cliente):
        raise HTTPException(404, "Equipo no encontrado")
    if usuario.rol_codigo not in (CLIENTE, ASESOR, ADMIN):
        raise HTTPException(403, "Solo el cliente o el asesor pueden solicitar la segunda visita")
    if ce.estado != "NO_CONFORME":
        raise HTTPException(409, "El equipo no está pendiente de segunda visita")
    ce.fecha_solicitud_visita2, ce.id_usuario_solicitud_visita2 = datetime.now(), usuario.id_usuario
    cambiar_estado(db, ce, "SEGUNDA_VISITA_SOLICITADA", usuario,
                   f"Solicitada por {usuario.nombre_completo}" + (f": {datos.comentario}" if datos.comentario else ""))
    cot = ce.cotizacion
    limite = f" Fecha límite: {ce.fecha_limite_correccion:%d/%m/%Y}." if ce.fecha_limite_correccion else ""
    notificar(db, usuarios_por_rol(db, PROGRAMACION), f"Segunda visita por programar {ce.codigo_servicio}",
              f"{ce.equipo.identificacion} - {cot.edificio.nombre}.{limite}", "PROGRAMACION", cot.id_cotizacion,
              "/programacion/pendientes")
    otros = [cot.asesor] if usuario.rol_codigo == CLIENTE else usuarios_del_cliente(db, cot.id_cliente)
    notificar(db, otros, f"Segunda visita solicitada {ce.codigo_servicio}",
              f"{usuario.nombre_completo} solicitó la segunda visita de {ce.equipo.identificacion}.", "COTIZACION",
              cot.id_cotizacion, f"/cotizaciones/{cot.id_cotizacion}")
    db.commit()
    return {"ok": True, "estado": ce.estado}


@router.get("/dashboard/resumen")
def resumen(db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    """Conteo de equipos por estado (para el tablero de cada rol)."""
    q = "SELECT estado_equipo, COUNT(*) n FROM v_seguimiento_equipo"
    params = {}
    if usuario.rol_codigo == CLIENTE:
        q += " WHERE id_cliente = :cli AND estado_cotizacion <> 'BORRADOR'"
        params["cli"] = usuario.id_cliente
    elif usuario.rol_codigo == ASESOR:
        q += " WHERE asesor = :ase"
        params["ase"] = usuario.nombre_completo
    q += " GROUP BY estado_equipo"
    conteo = {r.estado_equipo: r.n for r in db.execute(text(q), params)}
    return [{"estado": e, "etiqueta": et, "cantidad": conteo.get(e, 0)} for e, et in ETIQUETAS_ESTADO.items()]
