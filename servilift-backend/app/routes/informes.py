# app/routes/informes.py
# Director técnico: revisa checklist y fotos, devuelve o aprueba (atestación + firma),
# se genera el PDF, queda visible al cliente y pasa a Certificados.

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Cotizacion, CotizacionEquipo, Informe, Inspeccion, Programacion, Usuario
from app.routes.serializers import cot_equipo_dict, fila
from app.security import (
    ADMIN, CERTIFICADOS, CLIENTE, DIRECTOR_TECNICO, PROGRAMACION, crear_enlace_descarga, get_current_user,
    require_roles,
)
from app.services import archivos, pdf
from app.services.checklist import calcular_plazo, resumen
from app.services.flujo import cambiar_estado, notificar, parametro, usuarios_del_cliente, usuarios_por_rol

router = APIRouter(prefix="/informes", tags=["Informes"])


class DevolverIn(BaseModel):
    observaciones: str


class AprobarIn(BaseModel):
    atestacion: str | None = None
    concepto: str | None = None          # CONFORME / NO_CONFORME; si no llega se calcula
    firma_base64: str | None = None      # si no llega se usa la firma registrada del director
    observaciones_revision: str | None = None


def informe_dict(inf: Informe) -> dict:
    d = fila(inf, ["id_informe", "numero_informe", "id_inspeccion", "estado", "concepto", "atestacion",
                   "observaciones_revision", "total_leves", "total_graves", "total_muy_graves", "total_no_aplica",
                   "visita_actual", "concepto_visita1", "total_corregidos", "total_no_corregidos",
                   "plazo_dias", "fecha_limite_correccion",
                   "fecha_revision", "fecha_aprobacion", "fecha_envio_cliente", "fecha_creacion"])
    insp = inf.inspeccion
    d["numero_inspeccion"] = insp.numero_inspeccion
    d["inspector"] = insp.inspector.nombre_completo
    d["director"] = inf.director.nombre_completo if inf.director else None
    d["servicio"] = cot_equipo_dict(insp.cotizacion_equipo)
    d["numero_cotizacion"] = insp.cotizacion_equipo.cotizacion.numero_cotizacion
    d["edificio"] = insp.cotizacion_equipo.cotizacion.edificio.nombre
    d["cliente"] = insp.cotizacion_equipo.cotizacion.cliente.razon_social
    d["resumen_actual"] = resumen(insp)
    d["total_fotos"] = len(insp.fotos)
    d["fotos_revisadas"] = sum(1 for f in insp.fotos if f.revisada)
    d["tiene_pdf"] = bool(inf.ruta_pdf)
    d["tiene_pdf_visita1"] = bool(inf.ruta_pdf_visita1 or (inf.ruta_pdf and inf.visita_actual == 1))
    d["tiene_pdf_visita2"] = bool(inf.ruta_pdf and inf.visita_actual == 2 and inf.estado == "APROBADO")
    d["certificado"] = fila(inf.certificado, ["id_certificado", "numero_certificado", "estado"]) if inf.certificado else None
    return d


def _obtener(db: Session, id_informe: int, usuario: Usuario) -> Informe:
    inf = db.get(Informe, id_informe)
    if not inf:
        raise HTTPException(404, "Informe no encontrado")
    if usuario.rol_codigo == CLIENTE:
        cot = inf.inspeccion.cotizacion_equipo.cotizacion
        if cot.id_cliente != usuario.id_cliente or not (inf.estado == "APROBADO" or inf.ruta_pdf_visita1):
            raise HTTPException(404, "Informe no encontrado")
    return inf


@router.get("")
def listar(estado: str | None = None, numero_cotizacion: str | None = None, db: Session = Depends(get_db),
           usuario: Usuario = Depends(get_current_user)):
    q = db.query(Informe).join(Inspeccion).join(CotizacionEquipo)
    if usuario.rol_codigo == CLIENTE:
        q = q.join(Cotizacion).filter(Cotizacion.id_cliente == usuario.id_cliente, Informe.estado == "APROBADO")
    elif usuario.rol_codigo not in (DIRECTOR_TECNICO, CERTIFICADOS, ADMIN, "ASESOR"):
        raise HTTPException(403, "No tiene permisos para ver informes")
    if estado:
        q = q.filter(Informe.estado == estado)
    if numero_cotizacion:
        q = q.filter(CotizacionEquipo.codigo_servicio.like(f"{numero_cotizacion.strip()}%"))
    return [informe_dict(i) for i in q.order_by(Informe.id_informe.desc()).all()]


@router.get("/{id_informe}")
def obtener(id_informe: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    return informe_dict(_obtener(db, id_informe, usuario))


@router.get("/{id_informe}/pdf")
def descargar_pdf(id_informe: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    inf = _obtener(db, id_informe, usuario)
    if not inf.ruta_pdf:
        raise HTTPException(404, "El informe aún no tiene PDF")
    return FileResponse(archivos.ruta_absoluta(inf.ruta_pdf), media_type="application/pdf",
                        filename=f"{inf.numero_informe}.pdf")


@router.get("/{id_informe}/enlace-pdf")
def enlace_pdf(id_informe: int, visita: int | None = None, db: Session = Depends(get_db),
               usuario: Usuario = Depends(get_current_user)):
    """visita=1: informe de primera visita; visita=2 (o sin indicar): el informe vigente."""
    inf = _obtener(db, id_informe, usuario)
    segunda_lista = inf.visita_actual == 2 and inf.estado == "APROBADO"
    if visita == 1 or (not segunda_lista and inf.ruta_pdf_visita1):
        ruta = inf.ruta_pdf_visita1 or (inf.ruta_pdf if inf.visita_actual == 1 else None)
        nombre = f"{inf.numero_informe}-1V.pdf"
    else:
        ruta = inf.ruta_pdf
        nombre = f"{inf.numero_informe}-{'2V' if inf.visita_actual == 2 else '1V'}.pdf"
    if not ruta:
        raise HTTPException(404, "Ese informe aún no tiene PDF")
    return {"url": crear_enlace_descarga(ruta, nombre)}


@router.get("/{id_informe}/vista-previa")
def vista_previa(id_informe: int, db: Session = Depends(get_db),
                 usuario: Usuario = Depends(require_roles(DIRECTOR_TECNICO))):
    """PDF del informe tal como quedaría, marcado BORRADOR, para revisarlo antes de devolver o aprobar.
    No cambia nada en la base de datos."""
    inf = _obtener(db, id_informe, usuario)
    r = resumen(inf.inspeccion)
    if inf.estado != "APROBADO":
        # Valores provisionales solo para el PDF; se descartan con el rollback
        pendientes = r["total_no_cumple"] if inf.visita_actual == 1 else r["total_no_cumple"] - r["corregidos"]
        inf.concepto = "CONFORME" if pendientes == 0 else "NO_CONFORME"
        inf.total_leves, inf.total_graves = r["leves"], r["graves"]
        inf.total_muy_graves, inf.total_no_aplica = r["muy_graves"], r["no_aplica"]
        inf.total_corregidos, inf.total_no_corregidos = r["corregidos"], r["no_corregidos"]
        inf.id_director = usuario.id_usuario
        inf.atestacion = inf.atestacion or parametro(db, "TEXTO_ATESTACION")
        db.flush()
    ruta = pdf.generar_informe(db, inf, borrador=True, visita=inf.visita_actual)
    db.rollback()
    return {"url": crear_enlace_descarga(ruta, f"{inf.numero_informe}-borrador.pdf")}


@router.post("/{id_informe}/devolver")
def devolver(id_informe: int, datos: DevolverIn, db: Session = Depends(get_db),
             usuario: Usuario = Depends(require_roles(DIRECTOR_TECNICO))):
    inf = _obtener(db, id_informe, usuario)
    if inf.estado != "PENDIENTE_REVISION":
        raise HTTPException(409, f"El informe está {inf.estado}")
    inf.estado, inf.observaciones_revision = "DEVUELTO", datos.observaciones
    inf.id_director, inf.fecha_revision = usuario.id_usuario, datetime.now()
    insp = inf.inspeccion
    insp.estado = "EN_SEGUNDA_VISITA" if inf.visita_actual == 2 else "DEVUELTA"
    # La visita vuelve a quedar abierta para que aparezca en la agenda del inspector
    visita = insp.id_programacion_visita2 if inf.visita_actual == 2 else insp.id_programacion
    p = db.get(Programacion, visita)
    if p and p.estado == "REALIZADA":
        p.estado = "EN_CURSO"
    cambiar_estado(db, insp.cotizacion_equipo, "EN_INSPECCION", usuario, f"Devuelto: {datos.observaciones}")
    notificar(db, [insp.inspector], f"Informe devuelto {inf.numero_informe}", datos.observaciones,
              "INFORME", insp.id_inspeccion, f"/inspecciones/{insp.id_inspeccion}")
    db.commit()
    return informe_dict(inf)


@router.post("/{id_informe}/aprobar")
def aprobar(id_informe: int, datos: AprobarIn, db: Session = Depends(get_db),
            usuario: Usuario = Depends(require_roles(DIRECTOR_TECNICO))):
    inf = _obtener(db, id_informe, usuario)
    if inf.estado != "PENDIENTE_REVISION":
        raise HTTPException(409, f"El informe está {inf.estado}")
    insp = inf.inspeccion
    r = resumen(insp)

    if datos.firma_base64:
        inf.ruta_firma_director = archivos.guardar_firma_base64(f"informes/firmas/{inf.id_informe}", datos.firma_base64)
    elif usuario.ruta_firma:
        inf.ruta_firma_director = usuario.ruta_firma
    else:
        raise HTTPException(400, "Debe firmar el informe (o registrar su firma en el perfil)")
    if datos.concepto and datos.concepto not in ("CONFORME", "NO_CONFORME"):
        raise HTTPException(400, "Concepto inválido")

    inf.id_director = usuario.id_usuario
    # 1ª visita: conforme si no hay hallazgos. 2ª visita: conforme si todos los hallazgos quedaron corregidos.
    pendientes = r["total_no_cumple"] if inf.visita_actual == 1 else r["total_no_cumple"] - r["corregidos"]
    inf.concepto = datos.concepto or ("CONFORME" if pendientes == 0 else "NO_CONFORME")
    inf.atestacion = datos.atestacion or parametro(db, "TEXTO_ATESTACION")
    inf.observaciones_revision = datos.observaciones_revision
    inf.total_leves, inf.total_graves = r["leves"], r["graves"]
    inf.total_muy_graves, inf.total_no_aplica = r["muy_graves"], r["no_aplica"]
    inf.total_corregidos, inf.total_no_corregidos = r["corregidos"], r["no_corregidos"]
    ahora = datetime.now()
    if inf.visita_actual == 1:
        inf.concepto_visita1, inf.fecha_aprobacion_visita1 = inf.concepto, ahora
    inf.fecha_revision = inf.fecha_aprobacion = ahora
    for f in insp.fotos:
        f.revisada = True
    db.flush()

    inf.ruta_pdf = pdf.generar_informe(db, inf, visita=inf.visita_actual)
    inf.hash_sha256 = archivos.sha256(inf.ruta_pdf)
    if inf.visita_actual == 1:
        # El informe de primera visita se conserva tal cual; la 2ª visita genera uno nuevo
        inf.ruta_pdf_visita1, inf.hash_visita1 = inf.ruta_pdf, inf.hash_sha256
        inf.ruta_firma_director_v1 = inf.ruta_firma_director
    inf.estado = "APROBADO"
    inf.fecha_envio_cliente = ahora
    conforme = inf.concepto == "CONFORME"
    insp.estado = "CERRADA" if conforme and inf.visita_actual == 2 else "APROBADA"
    ce = insp.cotizacion_equipo
    if not conforme:
        inf.plazo_dias = calcular_plazo(db, insp, inf.visita_actual) or 0
        inf.fecha_limite_correccion = (ahora + timedelta(days=inf.plazo_dias)).date()
        ce.plazo_dias, ce.fecha_limite_correccion = inf.plazo_dias, inf.fecha_limite_correccion
        ce.fecha_solicitud_visita2 = ce.id_usuario_solicitud_visita2 = None
    cambiar_estado(db, ce, "INFORME_APROBADO" if conforme else "NO_CONFORME", usuario,
                   f"Informe {inf.numero_informe} {inf.concepto} (visita {inf.visita_actual})"
                   + ("" if conforme else f". Plazo de corrección: {inf.plazo_dias} días, hasta "
                                          f"{inf.fecha_limite_correccion:%d/%m/%Y}"))

    cot = ce.cotizacion
    notificar(db, usuarios_del_cliente(db, cot.id_cliente), f"Informe disponible {inf.numero_informe}",
              f"Ya puede ver y descargar el informe de {ce.equipo.identificacion} ({cot.edificio.nombre}).",
              "INFORME", inf.id_informe, f"/informes/{inf.id_informe}")
    if conforme:
        inf.fecha_envio_certificados = ahora
        notificar(db, usuarios_por_rol(db, CERTIFICADOS), f"Certificado por elaborar {ce.codigo_servicio}",
                  f"Informe {inf.numero_informe} conforme. {ce.equipo.identificacion} - {cot.edificio.nombre}.",
                  "CERTIFICADO", inf.id_informe, "/certificados/pendientes")
    else:
        # El certificado queda bloqueado: el cliente o el asesor solicitan la segunda visita dentro del plazo
        notificar(db, usuarios_del_cliente(db, cot.id_cliente) + [cot.asesor],
                  f"Solicite la segunda visita {ce.codigo_servicio}",
                  f"{ce.equipo.identificacion} ({cot.edificio.nombre}) quedó NO CONFORME. "
                  + ("Tiene hallazgos muy graves que deben corregirse de forma inmediata; solicite la segunda visita "
                     "en cuanto estén corregidos." if inf.plazo_dias == 0 else
                     f"Tiene {inf.plazo_dias} días (hasta {inf.fecha_limite_correccion:%d/%m/%Y}) para corregir y "
                     f"solicitar la segunda visita."),
                  "COTIZACION", cot.id_cotizacion, f"/cotizaciones/{cot.id_cotizacion}")
    db.commit()
    return informe_dict(inf)
