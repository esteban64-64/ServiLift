# app/services/flujo.py
# Numeración consecutiva, máquina de estados por equipo y notificaciones.

from datetime import datetime

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (
    Consecutivo, Cotizacion, CotizacionEquipo, HistorialEstado, Notificacion, Parametro, Rol, Usuario,
)

# ============================================
# CONSECUTIVOS: COT-2026-0001, INS-..., INF-..., CER-...
# ============================================
def siguiente_numero(db: Session, prefijo: str) -> str:
    anio = datetime.now().year
    fila = db.execute(
        select(Consecutivo).where(Consecutivo.prefijo == prefijo, Consecutivo.anio == anio).with_for_update()
    ).scalar_one_or_none()
    if fila is None:
        fila = Consecutivo(prefijo=prefijo, anio=anio, ultimo_numero=0)
        db.add(fila)
    fila.ultimo_numero += 1
    db.flush()
    return f"{prefijo}-{anio}-{fila.ultimo_numero:04d}"


# ============================================
# ESTADOS POR EQUIPO (cotizacion_equipo.estado)
# ============================================
TRANSICIONES = {
    "PENDIENTE_APROBACION": {"APROBADO_CLIENTE", "RECHAZADO", "ANULADO"},
    "APROBADO_CLIENTE": {"POR_PROGRAMAR", "ANULADO"},
    "POR_PROGRAMAR": {"PROGRAMADO", "ANULADO"},
    "PROGRAMADO": {"EN_INSPECCION", "POR_PROGRAMAR", "SEGUNDA_VISITA_SOLICITADA", "ANULADO"},
    "EN_INSPECCION": {"EN_REVISION", "POR_PROGRAMAR", "NO_CONFORME"},
    "EN_REVISION": {"INFORME_APROBADO", "NO_CONFORME", "EN_INSPECCION"},
    "NO_CONFORME": {"SEGUNDA_VISITA_SOLICITADA"},          # el cliente o el asesor la solicita
    "SEGUNDA_VISITA_SOLICITADA": {"PROGRAMADO"},          # programación agenda el cierre de hallazgos
    "INFORME_APROBADO": {"CERTIFICADO_LISTO"},
    "CERTIFICADO_LISTO": set(),
    "RECHAZADO": set(),
    "ANULADO": set(),
}

ESTADOS_FINALES = {"CERTIFICADO_LISTO", "RECHAZADO", "ANULADO"}

ETIQUETAS_ESTADO = {
    "PENDIENTE_APROBACION": "Pendiente por aprobación",
    "APROBADO_CLIENTE": "Aprobado",
    "POR_PROGRAMAR": "Por programar",
    "PROGRAMADO": "Programado",
    "EN_INSPECCION": "En inspección",
    "EN_REVISION": "En revisión técnica",
    "NO_CONFORME": "No conforme: solicitar segunda visita",
    "SEGUNDA_VISITA_SOLICITADA": "Segunda visita solicitada",
    "INFORME_APROBADO": "Informe disponible",
    "CERTIFICADO_LISTO": "Certificado listo",
    "RECHAZADO": "Rechazado",
    "ANULADO": "Anulado",
}


def cambiar_estado(db: Session, ce: CotizacionEquipo, nuevo: str, usuario: Usuario | None, comentario: str | None = None):
    if ce.estado == nuevo:
        return
    if nuevo not in TRANSICIONES.get(ce.estado, set()):
        raise HTTPException(409, f"El equipo {ce.codigo_servicio} está en {ce.estado} y no puede pasar a {nuevo}")
    db.add(HistorialEstado(
        id_cotizacion_equipo=ce.id_cotizacion_equipo,
        estado_anterior=ce.estado,
        estado_nuevo=nuevo,
        id_usuario=usuario.id_usuario if usuario else None,
        comentario=comentario,
    ))
    ce.estado = nuevo
    ce.fecha_estado = datetime.now()
    _actualizar_estado_cotizacion(ce.cotizacion)


def registrar_evento(db: Session, ce: CotizacionEquipo, usuario: Usuario | None, comentario: str):
    """Deja en el historial del equipo un hecho que no cambia su estado (envío, emisión, reprogramación...)."""
    db.add(HistorialEstado(id_cotizacion_equipo=ce.id_cotizacion_equipo, estado_anterior=ce.estado,
                           estado_nuevo=ce.estado, id_usuario=usuario.id_usuario if usuario else None,
                           comentario=comentario[:500]))


def _actualizar_estado_cotizacion(cot: Cotizacion):
    """Una vez en programación, la cotización pasa a EN_EJECUCION y a FINALIZADA cuando todos sus equipos terminan."""
    if cot.estado not in ("ENVIADA_PROGRAMACION", "EN_EJECUCION"):
        return
    estados = {e.estado for e in cot.equipos}
    if estados and estados <= ESTADOS_FINALES:
        cot.estado = "FINALIZADA"
    elif estados - {"POR_PROGRAMAR"} - ESTADOS_FINALES:
        cot.estado = "EN_EJECUCION"


# ============================================
# NOTIFICACIONES
# ============================================
def notificar(db: Session, usuarios, titulo: str, mensaje: str, tipo: str, id_referencia: int | None = None,
              enlace: str | None = None):
    for u in usuarios:
        db.add(Notificacion(id_usuario_destino=u.id_usuario, titulo=titulo[:120], mensaje=mensaje[:500],
                            tipo=tipo, id_referencia=id_referencia, enlace=enlace))


def usuarios_por_rol(db: Session, codigo_rol: str):
    return db.query(Usuario).join(Rol).filter(Rol.codigo == codigo_rol, Usuario.estado == "ACTIVO").all()


def usuarios_del_cliente(db: Session, id_cliente: int):
    return db.query(Usuario).filter(Usuario.id_cliente == id_cliente, Usuario.estado == "ACTIVO").all()


def parametro(db: Session, clave: str, defecto: str = "") -> str:
    p = db.get(Parametro, clave)
    return p.valor if p else defecto
