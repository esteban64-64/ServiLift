# app/routes/dashboard.py
# Página de inicio de cada rol: indicadores (KPI), gráficas y listas de pendientes.
# Respuesta genérica para que la app la dibuje igual en todos los roles:
#   {"titulo", "kpis": [{titulo, valor, detalle, color}],
#    "graficas": [{titulo, tipo: "barras"|"meses"|"dona", datos: [{etiqueta, valor, color}]}],
#    "listas": [{titulo, items: [{texto, subtexto, estado}]}]}

from collections import Counter
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import (
    Certificado, ChecklistItem, Cliente, Cotizacion, CotizacionEquipo, Informe, Inspeccion, InspeccionResultado,
    Programacion, Rol, Usuario,
)
from app.security import (
    ADMIN, ASESOR, CERTIFICADOS, CLIENTE, DIRECTOR_TECNICO, INSPECTOR, PROGRAMACION, get_current_user,
)
from app.services.flujo import ETIQUETAS_ESTADO

router = APIRouter(tags=["Inicio"])

COLOR_ESTADO = {
    "PENDIENTE_APROBACION": "alerta", "APROBADO_CLIENTE": "exito", "POR_PROGRAMAR": "alerta", "PROGRAMADO": "info",
    "EN_INSPECCION": "info", "EN_REVISION": "alerta", "NO_CONFORME": "error", "SEGUNDA_VISITA_SOLICITADA": "alerta",
    "INFORME_APROBADO": "exito", "CERTIFICADO_LISTO": "exito", "RECHAZADO": "gris", "ANULADO": "gris",
}
MESES = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]


def _kpi(titulo, valor, detalle=None, color="info"):
    return {"titulo": titulo, "valor": valor, "detalle": detalle, "color": color}


def _moneda(v) -> str:
    return "$" + f"{float(v or 0):,.0f}".replace(",", ".")


def _ultimos_meses(n=6):
    hoy = date.today().replace(day=1)
    meses = []
    for i in range(n - 1, -1, -1):
        m = hoy.month - 1 - i
        meses.append((hoy.year + m // 12, m % 12 + 1))
    return meses


def _serie_mensual(fechas, n=6):
    cuenta = Counter((f.year, f.month) for f in fechas if f)
    return [{"etiqueta": f"{MESES[m - 1]} {str(a)[2:]}", "valor": cuenta.get((a, m), 0)} for a, m in _ultimos_meses(n)]


def _equipos_por_estado(q):
    cuenta = Counter(ce.estado for ce in q)
    return [{"etiqueta": ETIQUETAS_ESTADO.get(e, e), "valor": n, "color": COLOR_ESTADO.get(e, "info")}
            for e, n in cuenta.most_common()]


def _inicio_mes():
    return datetime.combine(date.today().replace(day=1), datetime.min.time())


def _hallazgos_por_calificacion(db, filtro_insp=None):
    q = (db.query(InspeccionResultado.calificacion_defecto, func.count())
         .join(Inspeccion).filter(InspeccionResultado.resultado == "NO_CUMPLE"))
    if filtro_insp is not None:
        q = q.filter(filtro_insp)
    datos = dict(q.group_by(InspeccionResultado.calificacion_defecto).all())
    return [{"etiqueta": "Leves", "valor": datos.get("LEVE", 0), "color": "info"},
            {"etiqueta": "Graves", "valor": datos.get("GRAVE", 0), "color": "alerta"},
            {"etiqueta": "Muy graves", "valor": datos.get("MUY_GRAVE", 0), "color": "error"}]


def _top_hallazgos(db, n=5):
    filas = (db.query(ChecklistItem.numero, ChecklistItem.descripcion, func.count().label("n"))
             .join(InspeccionResultado, InspeccionResultado.id_item == ChecklistItem.id_item)
             .filter(InspeccionResultado.resultado == "NO_CUMPLE")
             .group_by(ChecklistItem.id_item).order_by(func.count().desc()).limit(n).all())
    return [{"etiqueta": f"{f.numero}. {f.descripcion[:45]}", "valor": f.n, "color": "error"} for f in filas]


# ============================================
# POR ROL
# ============================================
def _asesor(db: Session, u: Usuario, admin=False):
    cots = db.query(Cotizacion)
    if not admin:
        cots = cots.filter(Cotizacion.id_asesor == u.id_usuario)
    cots = cots.all()
    ids = [c.id_cotizacion for c in cots]
    enviadas = [c for c in cots if c.estado != "BORRADOR"]
    aprobadas = [c for c in cots if c.estado in ("APROBADA_CLIENTE", "ENVIADA_PROGRAMACION", "EN_EJECUCION", "FINALIZADA")]
    respondidas = [c for c in enviadas if c.estado not in ("ENVIADA_CLIENTE", "ANULADA")]
    mes = [c for c in aprobadas if c.fecha_respuesta_cliente and c.fecha_respuesta_cliente >= _inicio_mes()]
    clientes = db.query(Cliente).filter(True if admin else Cliente.id_asesor == u.id_usuario).count()
    equipos = db.query(CotizacionEquipo).filter(CotizacionEquipo.id_cotizacion.in_(ids or [0])).all()
    pendientes_cliente = [c for c in cots if c.estado == "ENVIADA_CLIENTE"]
    por_pasar = [c for c in cots if c.estado == "APROBADA_CLIENTE"]
    return {
        "kpis": [
            _kpi("Clientes", clientes, color="info"),
            _kpi("Cotizaciones", len(cots), f"{len(pendientes_cliente)} esperando al cliente", "info"),
            _kpi("Tasa de aprobación", f"{round(100 * len(aprobadas) / len(respondidas)) if respondidas else 0}%",
                 f"{len(aprobadas)} aprobadas de {len(respondidas)} respondidas", "exito"),
            _kpi("Aprobado este mes", _moneda(sum(c.total for c in mes)), f"{len(mes)} cotizaciones", "exito"),
            _kpi("Por enviar a programación", len(por_pasar), "Aprobadas por el cliente", "alerta" if por_pasar else "gris"),
        ],
        "graficas": [
            {"titulo": "Cotizaciones por estado", "tipo": "dona",
             "datos": [{"etiqueta": ETIQUETAS_ESTADO.get(e, e.replace('_', ' ').capitalize()), "valor": n}
                       for e, n in Counter(c.estado for c in cots).most_common()]},
            {"titulo": "Cotizaciones creadas por mes", "tipo": "meses", "datos": _serie_mensual([c.fecha_cotizacion for c in cots])},
            {"titulo": "Equipos por estado", "tipo": "barras", "datos": _equipos_por_estado(equipos)},
        ],
        "listas": [
            {"titulo": "Aprobadas: enviar a programación",
             "items": [{"texto": f"{c.numero_cotizacion} · {c.edificio.nombre}", "subtexto": c.cliente.razon_social,
                        "estado": c.estado, "id_cotizacion": c.id_cotizacion} for c in por_pasar[:8]]},
            {"titulo": "Esperando respuesta del cliente",
             "items": [{"texto": f"{c.numero_cotizacion} · {c.edificio.nombre}",
                        "subtexto": f"{c.cliente.razon_social} · enviada {c.fecha_envio_cliente:%d/%m/%Y}" if c.fecha_envio_cliente else c.cliente.razon_social,
                        "estado": c.estado, "id_cotizacion": c.id_cotizacion} for c in pendientes_cliente[:8]]},
        ],
    }


def _cliente(db: Session, u: Usuario):
    equipos = (db.query(CotizacionEquipo).join(Cotizacion)
               .filter(Cotizacion.id_cliente == u.id_cliente, Cotizacion.estado != "BORRADOR").all())
    hoy = date.today()
    certs = (db.query(Certificado).join(CotizacionEquipo).join(Cotizacion)
             .filter(Cotizacion.id_cliente == u.id_cliente, Certificado.estado == "ENVIADO_CLIENTE").all())
    vigentes = [c for c in certs if c.fecha_vencimiento and c.fecha_vencimiento >= hoy]
    por_vencer = [c for c in vigentes if c.fecha_vencimiento <= hoy + timedelta(days=60)]
    por_aprobar = (db.query(Cotizacion).filter(Cotizacion.id_cliente == u.id_cliente, Cotizacion.estado == "ENVIADA_CLIENTE").all())
    no_conf = [e for e in equipos if e.estado == "NO_CONFORME"]
    return {
        "kpis": [
            _kpi("Equipos en proceso", sum(1 for e in equipos if e.estado not in ("CERTIFICADO_LISTO", "RECHAZADO", "ANULADO")), color="info"),
            _kpi("Certificados vigentes", len(vigentes), f"{len(por_vencer)} vencen en 60 días", "exito"),
            _kpi("Cotizaciones por aprobar", len(por_aprobar), color="alerta" if por_aprobar else "gris"),
            _kpi("Pendientes de 2ª visita", len(no_conf), "Solicítela antes del plazo", "error" if no_conf else "gris"),
        ],
        "graficas": [
            {"titulo": "Mis equipos por estado", "tipo": "dona", "datos": _equipos_por_estado(equipos)},
        ],
        "listas": [
            {"titulo": "Cotizaciones por aprobar",
             "items": [{"texto": f"{c.numero_cotizacion} · {c.edificio.nombre}", "subtexto": _moneda(c.total),
                        "estado": c.estado, "id_cotizacion": c.id_cotizacion} for c in por_aprobar]},
            {"titulo": "Equipos no conformes: solicite la segunda visita",
             "items": [{"texto": f"{e.equipo.identificacion} · {e.cotizacion.edificio.nombre}",
                        "subtexto": f"Plazo hasta {e.fecha_limite_correccion:%d/%m/%Y}" if e.fecha_limite_correccion else e.codigo_servicio,
                        "estado": e.estado, "id_cotizacion": e.id_cotizacion} for e in no_conf]},
            {"titulo": "Certificados por vencer (60 días)",
             "items": [{"texto": f"{c.numero_certificado} · {c.cotizacion_equipo.equipo.identificacion}",
                        "subtexto": f"Vence {c.fecha_vencimiento:%d/%m/%Y}", "estado": "NO_CONFORME"} for c in por_vencer]},
        ],
    }


def _programacion(db: Session, u: Usuario):
    hoy = date.today()
    por_prog = db.query(CotizacionEquipo).filter(CotizacionEquipo.estado == "POR_PROGRAMAR").count()
    segunda = db.query(CotizacionEquipo).filter(CotizacionEquipo.estado == "SEGUNDA_VISITA_SOLICITADA").all()
    urgentes = [e for e in segunda if e.fecha_limite_correccion and e.fecha_limite_correccion <= hoy + timedelta(days=3)]
    semana = (db.query(Programacion).filter(Programacion.estado.in_(("PROGRAMADA", "REPROGRAMADA", "EN_CURSO")),
                                            Programacion.fecha_programada >= hoy,
                                            Programacion.fecha_programada <= hoy + timedelta(days=7)).all())
    por_insp = Counter(p.inspector.nombre_completo for p in semana)
    por_dia = Counter(p.fecha_programada for p in semana)
    todas = db.query(Programacion).filter(Programacion.estado != "CANCELADA").all()
    return {
        "kpis": [
            _kpi("Por programar (1ª visita)", por_prog, color="alerta" if por_prog else "gris"),
            _kpi("2ª visitas solicitadas", len(segunda), f"{len(urgentes)} vencen en ≤ 3 días", "error" if urgentes else "info"),
            _kpi("Visitas hoy", por_dia.get(hoy, 0), color="info"),
            _kpi("Visitas próximos 7 días", len(semana), color="info"),
        ],
        "graficas": [
            {"titulo": "Carga por inspector (7 días)", "tipo": "barras",
             "datos": [{"etiqueta": k, "valor": v} for k, v in por_insp.most_common()]},
            {"titulo": "Visitas por día (7 días)", "tipo": "meses",
             "datos": [{"etiqueta": (hoy + timedelta(days=i)).strftime("%d/%m"), "valor": por_dia.get(hoy + timedelta(days=i), 0)}
                       for i in range(8)]},
            {"titulo": "Visitas programadas por mes", "tipo": "meses", "datos": _serie_mensual([p.fecha_programada for p in todas])},
        ],
        "listas": [
            {"titulo": "2ª visitas por vencer",
             "items": [{"texto": f"{e.codigo_servicio} · {e.cotizacion.edificio.nombre}",
                        "subtexto": f"Límite {e.fecha_limite_correccion:%d/%m/%Y}" if e.fecha_limite_correccion else "",
                        "estado": e.estado} for e in sorted(segunda, key=lambda e: e.fecha_limite_correccion or date.max)[:8]]},
        ],
    }


def _inspector(db: Session, u: Usuario):
    hoy = date.today()
    mias = db.query(Inspeccion).filter(Inspeccion.id_inspector == u.id_usuario).all()
    visitas = db.query(Programacion).filter(Programacion.id_inspector == u.id_usuario, Programacion.estado != "CANCELADA").all()
    hoy_v = [p for p in visitas if p.fecha_programada == hoy]
    proximas = [p for p in visitas if hoy <= p.fecha_programada <= hoy + timedelta(days=7) and p.estado != "REALIZADA"]
    devueltas = [i for i in mias if i.estado == "DEVUELTA"]
    mes = [i for i in mias if i.fecha_fin and i.fecha_fin >= _inicio_mes()]
    return {
        "kpis": [
            _kpi("Visitas hoy", len(hoy_v), color="info"),
            _kpi("Próximos 7 días", len(proximas), color="info"),
            _kpi("En curso", sum(1 for i in mias if i.estado in ("EN_CURSO", "EN_SEGUNDA_VISITA")), color="alerta"),
            _kpi("Devueltas por el director", len(devueltas), "Por corregir", "error" if devueltas else "gris"),
            _kpi("Finalizadas este mes", len(mes), color="exito"),
        ],
        "graficas": [
            {"titulo": "Inspecciones finalizadas por mes", "tipo": "meses", "datos": _serie_mensual([i.fecha_fin for i in mias])},
            {"titulo": "Hallazgos encontrados por calificación", "tipo": "barras",
             "datos": _hallazgos_por_calificacion(db, Inspeccion.id_inspector == u.id_usuario)},
        ],
        "listas": [
            {"titulo": "Próximas visitas",
             "items": [{"texto": f"{p.fecha_programada:%d/%m} {p.hora_inicio:%H:%M} · {p.cotizacion.edificio.nombre}",
                        "subtexto": f"{p.cotizacion.edificio.direccion} · {len(p.equipos)} equipos"
                                    + (" · 2ª visita" if p.tipo_visita == "SEGUNDA" else ""),
                        "estado": "PROGRAMADO"} for p in sorted(proximas, key=lambda p: (p.fecha_programada, p.hora_inicio))[:8]]},
            {"titulo": "Devueltas por el director",
             "items": [{"texto": f"{i.numero_inspeccion} · {i.cotizacion_equipo.equipo.identificacion}",
                        "subtexto": (i.informe.observaciones_revision or "") if i.informe else "",
                        "estado": "DEVUELTO"} for i in devueltas]},
        ],
    }


def _director(db: Session, u: Usuario):
    informes = db.query(Informe).all()
    pend = [i for i in informes if i.estado == "PENDIENTE_REVISION"]
    aprob = [i for i in informes if i.estado == "APROBADO"]
    mes = [i for i in aprob if i.fecha_aprobacion and i.fecha_aprobacion >= _inicio_mes()]
    conformes = sum(1 for i in aprob if i.concepto == "CONFORME")
    tiempos = [(i.fecha_revision - i.inspeccion.fecha_fin).total_seconds() / 3600 for i in aprob
               if i.fecha_revision and i.inspeccion.fecha_fin]
    return {
        "kpis": [
            _kpi("Informes por revisar", len(pend), f"{sum(1 for i in pend if i.visita_actual == 2)} de 2ª visita",
                 "alerta" if pend else "gris"),
            _kpi("Aprobados este mes", len(mes), color="exito"),
            _kpi("Conformes", f"{round(100 * conformes / len(aprob)) if aprob else 0}%", f"{conformes} de {len(aprob)} aprobados", "exito"),
            _kpi("Tiempo medio de revisión", f"{round(sum(tiempos) / len(tiempos), 1) if tiempos else 0} h", color="info"),
            _kpi("Devueltos", sum(1 for i in informes if i.estado == "DEVUELTO"), "Esperando corrección", "error"),
        ],
        "graficas": [
            {"titulo": "Concepto de informes aprobados", "tipo": "dona",
             "datos": [{"etiqueta": "Conforme", "valor": conformes, "color": "exito"},
                       {"etiqueta": "No conforme", "valor": len(aprob) - conformes, "color": "error"}]},
            {"titulo": "Informes aprobados por mes", "tipo": "meses", "datos": _serie_mensual([i.fecha_aprobacion for i in aprob])},
            {"titulo": "Hallazgos por calificación", "tipo": "barras", "datos": _hallazgos_por_calificacion(db)},
            {"titulo": "Ítems que más fallan", "tipo": "barras", "datos": _top_hallazgos(db)},
        ],
        "listas": [
            {"titulo": "Por revisar",
             "items": [{"texto": f"{i.numero_informe} · {i.inspeccion.cotizacion_equipo.cotizacion.edificio.nombre}",
                        "subtexto": f"{i.inspeccion.cotizacion_equipo.equipo.identificacion} · {i.inspeccion.inspector.nombre_completo}"
                                    + (" · 2ª visita" if i.visita_actual == 2 else ""),
                        "estado": "PENDIENTE_REVISION", "id_informe": i.id_informe} for i in pend[:8]]},
        ],
    }


def _certificados(db: Session, u: Usuario):
    hoy = date.today()
    pendientes = (db.query(Informe).outerjoin(Certificado)
                  .filter(Informe.estado == "APROBADO", Informe.concepto == "CONFORME", Certificado.id_certificado.is_(None)).count())
    certs = db.query(Certificado).filter(Certificado.estado != "ANULADO").all()
    sin_enviar = [c for c in certs if c.estado == "EMITIDO"]
    mes = [c for c in certs if c.fecha_emision and c.fecha_emision >= hoy.replace(day=1)]
    por_vencer = [c for c in certs if c.fecha_vencimiento and hoy <= c.fecha_vencimiento <= hoy + timedelta(days=60)]
    return {
        "kpis": [
            _kpi("Por elaborar", pendientes, color="alerta" if pendientes else "gris"),
            _kpi("Emitidos sin enviar", len(sin_enviar), color="alerta" if sin_enviar else "gris"),
            _kpi("Emitidos este mes", len(mes), color="exito"),
            _kpi("Vencen en 60 días", len(por_vencer), "Oportunidad de recotizar", "info"),
        ],
        "graficas": [
            {"titulo": "Certificados emitidos por mes", "tipo": "meses", "datos": _serie_mensual([c.fecha_emision for c in certs])},
            {"titulo": "Vencimientos próximos (meses)", "tipo": "barras",
             "datos": [{"etiqueta": f"{MESES[m - 1]} {a}", "valor": sum(1 for c in certs if c.fecha_vencimiento
                                                                        and (c.fecha_vencimiento.year, c.fecha_vencimiento.month) == (a, m))}
                       for a, m in [((hoy.year + (hoy.month - 1 + i) // 12), (hoy.month - 1 + i) % 12 + 1) for i in range(4)]]},
        ],
        "listas": [
            {"titulo": "Emitidos pendientes de enviar",
             "items": [{"texto": f"{c.numero_certificado} · {c.cotizacion_equipo.cotizacion.edificio.nombre}",
                        "subtexto": c.cotizacion_equipo.equipo.identificacion, "estado": "EMITIDO"} for c in sin_enviar[:8]]},
            {"titulo": "Por vencer",
             "items": [{"texto": f"{c.numero_certificado} · {c.cotizacion_equipo.cotizacion.cliente.razon_social}",
                        "subtexto": f"Vence {c.fecha_vencimiento:%d/%m/%Y}", "estado": "NO_CONFORME"} for c in por_vencer[:8]]},
        ],
    }


def _admin(db: Session, u: Usuario):
    base = _asesor(db, u, admin=True)
    equipos = db.query(CotizacionEquipo).all()
    usuarios = Counter(r for (r,) in db.query(Rol.nombre).join(Usuario).filter(Usuario.estado == "ACTIVO").all())
    certs = db.query(Certificado).filter(Certificado.estado != "ANULADO").all()
    insp = db.query(Inspeccion).all()
    base["kpis"] = [
        _kpi("Equipos en proceso", sum(1 for e in equipos if e.estado not in ("CERTIFICADO_LISTO", "RECHAZADO", "ANULADO")), color="info"),
        _kpi("Certificados emitidos", len(certs), color="exito"),
        _kpi("Informes por revisar", db.query(Informe).filter(Informe.estado == "PENDIENTE_REVISION").count(), color="alerta"),
        _kpi("Usuarios activos", sum(usuarios.values()), color="info"),
    ] + base["kpis"][1:4]
    base["graficas"] = [
        {"titulo": "Equipos por estado", "tipo": "dona", "datos": _equipos_por_estado(equipos)},
        {"titulo": "Inspecciones finalizadas por mes", "tipo": "meses", "datos": _serie_mensual([i.fecha_fin for i in insp])},
        {"titulo": "Certificados emitidos por mes", "tipo": "meses", "datos": _serie_mensual([c.fecha_emision for c in certs])},
        {"titulo": "Usuarios por rol", "tipo": "barras", "datos": [{"etiqueta": k, "valor": v} for k, v in usuarios.most_common()]},
    ] + base["graficas"][:1]
    return base


@router.get("/dashboard")
def dashboard(db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    rol = usuario.rol_codigo
    fn = {ASESOR: _asesor, CLIENTE: _cliente, PROGRAMACION: _programacion, INSPECTOR: _inspector,
          DIRECTOR_TECNICO: _director, CERTIFICADOS: _certificados, ADMIN: _admin}[rol]
    datos = fn(db, usuario)
    datos["titulo"] = f"Hola, {usuario.nombre_completo.split()[0]}"
    datos["rol"] = rol
    return datos
