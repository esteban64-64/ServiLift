# app/routes/certificados.py
# Rol Certificados: elabora el certificado a partir del informe aprobado y lo envía al cliente.

import secrets
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Certificado, Cotizacion, CotizacionEquipo, Informe, Usuario
from app.routes.informes import informe_dict
from app.routes.serializers import cot_equipo_dict, fila
from app.security import (
    ADMIN, CERTIFICADOS, CLIENTE, crear_enlace_descarga, get_current_user, leer_enlace_descarga, require_roles,
)
from app.services import archivos, pdf
from app.services.flujo import (
    cambiar_estado, notificar, parametro, registrar_evento, siguiente_numero, usuarios_del_cliente,
)

router = APIRouter(tags=["Certificados"])


class EmitirIn(BaseModel):
    id_informe: int
    fecha_emision: date | None = None
    fecha_vencimiento: date | None = None


class AnularIn(BaseModel):
    motivo: str


def sumar_meses(d: date, meses: int) -> date:
    m = d.month - 1 + meses
    anio, mes = d.year + m // 12, m % 12 + 1
    dias = [31, 29 if anio % 4 == 0 and (anio % 100 != 0 or anio % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return date(anio, mes, min(d.day, dias[mes - 1]))


def certificado_dict(c: Certificado) -> dict:
    d = fila(c, ["id_certificado", "numero_certificado", "id_informe", "id_cotizacion_equipo", "estado",
                 "fecha_emision", "fecha_vencimiento", "codigo_verificacion", "fecha_envio_cliente",
                 "motivo_anulacion"])
    d["numero_informe"] = c.informe.numero_informe
    d["concepto"] = c.informe.concepto
    d["servicio"] = cot_equipo_dict(c.cotizacion_equipo)
    d["numero_cotizacion"] = c.cotizacion_equipo.cotizacion.numero_cotizacion
    d["edificio"] = c.cotizacion_equipo.cotizacion.edificio.nombre
    d["cliente"] = c.cotizacion_equipo.cotizacion.cliente.razon_social
    d["tiene_pdf"] = bool(c.ruta_pdf)
    return d


def _obtener(db: Session, id_certificado: int, usuario: Usuario) -> Certificado:
    c = db.get(Certificado, id_certificado)
    if not c:
        raise HTTPException(404, "Certificado no encontrado")
    if usuario.rol_codigo == CLIENTE and (c.cotizacion_equipo.cotizacion.id_cliente != usuario.id_cliente
                                          or c.estado != "ENVIADO_CLIENTE"):
        raise HTTPException(404, "Certificado no encontrado")
    return c


@router.get("/certificados/pendientes")
def pendientes(db: Session = Depends(get_db), _: Usuario = Depends(require_roles(CERTIFICADOS))):
    """Informes aprobados que todavía no tienen certificado."""
    q = (db.query(Informe).outerjoin(Certificado)
         .filter(Informe.estado == "APROBADO", Informe.concepto == "CONFORME", Certificado.id_certificado.is_(None))
         .order_by(Informe.fecha_aprobacion))
    return [informe_dict(i) for i in q.all()]


@router.get("/certificados")
def listar(numero_cotizacion: str | None = None, estado: str | None = None, vence_antes: date | None = None,
           db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    q = db.query(Certificado).join(CotizacionEquipo).join(Cotizacion)
    if usuario.rol_codigo == CLIENTE:
        q = q.filter(Cotizacion.id_cliente == usuario.id_cliente, Certificado.estado == "ENVIADO_CLIENTE")
    if numero_cotizacion:
        q = q.filter(Cotizacion.numero_cotizacion.like(f"%{numero_cotizacion.strip()}%"))
    if estado:
        q = q.filter(Certificado.estado == estado)
    if vence_antes:
        q = q.filter(Certificado.fecha_vencimiento <= vence_antes)
    return [certificado_dict(c) for c in q.order_by(Certificado.id_certificado.desc()).all()]


@router.post("/certificados", status_code=201)
def emitir(datos: EmitirIn, db: Session = Depends(get_db), usuario: Usuario = Depends(require_roles(CERTIFICADOS))):
    inf = db.get(Informe, datos.id_informe)
    if not inf or inf.estado != "APROBADO":
        raise HTTPException(404, "Informe aprobado no encontrado")
    if inf.concepto != "CONFORME":
        raise HTTPException(409, "El informe es NO CONFORME: el certificado se emite cuando la segunda visita "
                                 "confirme que todos los hallazgos fueron corregidos")
    if inf.certificado and inf.certificado.estado != "ANULADO":
        raise HTTPException(409, f"El informe ya tiene el certificado {inf.certificado.numero_certificado}")
    if inf.certificado:  # se reemplaza uno anulado
        db.delete(inf.certificado)
        db.flush()
    emision = datos.fecha_emision or date.today()
    meses = int(parametro(db, "CERTIFICADO_VIGENCIA_MESES", "12"))
    c = Certificado(
        numero_certificado=siguiente_numero(db, "CER"), id_informe=inf.id_informe,
        id_cotizacion_equipo=inf.inspeccion.id_cotizacion_equipo, id_emisor=usuario.id_usuario,
        fecha_emision=emision, fecha_vencimiento=datos.fecha_vencimiento or sumar_meses(emision, meses),
        codigo_verificacion=secrets.token_urlsafe(12), estado="EN_ELABORACION",
    )
    db.add(c)
    db.flush()
    db.refresh(c)
    c.ruta_pdf = pdf.generar_certificado(db, c)
    c.hash_sha256 = archivos.sha256(c.ruta_pdf)
    c.estado = "EMITIDO"
    registrar_evento(db, c.cotizacion_equipo, usuario,
                     f"Certificado {c.numero_certificado} emitido, vigente hasta {c.fecha_vencimiento:%d/%m/%Y}")
    db.commit()
    return certificado_dict(c)


@router.post("/certificados/{id_certificado}/enviar")
def enviar(id_certificado: int, db: Session = Depends(get_db), usuario: Usuario = Depends(require_roles(CERTIFICADOS))):
    c = _obtener(db, id_certificado, usuario)
    if c.estado != "EMITIDO":
        raise HTTPException(409, f"El certificado está {c.estado}")
    c.estado, c.fecha_envio_cliente = "ENVIADO_CLIENTE", datetime.now()
    ce = c.cotizacion_equipo
    cambiar_estado(db, ce, "CERTIFICADO_LISTO", usuario, f"Certificado {c.numero_certificado}")
    notificar(db, usuarios_del_cliente(db, ce.cotizacion.id_cliente), f"Certificado listo {c.numero_certificado}",
              f"El certificado de {ce.equipo.identificacion} ({ce.cotizacion.edificio.nombre}) está disponible.",
              "CERTIFICADO", c.id_certificado, f"/certificados/{c.id_certificado}")
    db.commit()
    return certificado_dict(c)


@router.post("/certificados/{id_certificado}/anular")
def anular(id_certificado: int, datos: AnularIn, db: Session = Depends(get_db),
           usuario: Usuario = Depends(require_roles(CERTIFICADOS))):
    c = _obtener(db, id_certificado, usuario)
    if c.estado == "ENVIADO_CLIENTE" and usuario.rol_codigo != ADMIN:
        raise HTTPException(409, "Un certificado ya enviado solo lo anula el administrador")
    c.estado, c.motivo_anulacion = "ANULADO", datos.motivo
    db.commit()
    return certificado_dict(c)


@router.get("/certificados/{id_certificado}")
def obtener(id_certificado: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    return certificado_dict(_obtener(db, id_certificado, usuario))


@router.get("/certificados/{id_certificado}/pdf")
def descargar_pdf(id_certificado: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    c = _obtener(db, id_certificado, usuario)
    if not c.ruta_pdf:
        raise HTTPException(404, "El certificado aún no tiene PDF")
    return FileResponse(archivos.ruta_absoluta(c.ruta_pdf), media_type="application/pdf",
                        filename=f"{c.numero_certificado}.pdf")


@router.get("/certificados/{id_certificado}/enlace-pdf")
def enlace_pdf(id_certificado: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    c = _obtener(db, id_certificado, usuario)
    if not c.ruta_pdf:
        raise HTTPException(404, "El certificado aún no tiene PDF")
    return {"url": crear_enlace_descarga(c.ruta_pdf, f"{c.numero_certificado}.pdf")}


@router.get("/descargas/{token}")
def descargar(token: str):
    ruta, nombre = leer_enlace_descarga(token)
    return FileResponse(archivos.ruta_absoluta(ruta), media_type="application/pdf", filename=nombre,
                        content_disposition_type="inline")


@router.get("/verificar/{codigo}")
def verificar(codigo: str, db: Session = Depends(get_db)):
    """Público (QR del certificado): confirma que el certificado existe y está vigente."""
    c = db.query(Certificado).filter(Certificado.codigo_verificacion == codigo).first()
    if not c or c.estado not in ("EMITIDO", "ENVIADO_CLIENTE", "ANULADO"):
        raise HTTPException(404, "Certificado no encontrado")
    ce = c.cotizacion_equipo
    return {
        "numero_certificado": c.numero_certificado,
        "estado": "ANULADO" if c.estado == "ANULADO" else ("VIGENTE" if c.fecha_vencimiento >= date.today() else "VENCIDO"),
        "fecha_emision": c.fecha_emision.isoformat(),
        "fecha_vencimiento": c.fecha_vencimiento.isoformat(),
        "concepto": c.informe.concepto,
        "edificio": ce.cotizacion.edificio.nombre,
        "ciudad": ce.cotizacion.edificio.ciudad,
        "equipo": ce.equipo.identificacion,
        "empresa": parametro(db, "EMPRESA_NOMBRE", "ServiLift"),
    }
