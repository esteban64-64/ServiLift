# app/routes/serializers.py
# Conversión de modelos a dict para las respuestas JSON.

from datetime import date

from app.models import (
    Cliente, Cotizacion, CotizacionEquipo, Edificio, Equipo, Programacion, Usuario,
)
from app.services.flujo import ETIQUETAS_ESTADO


def _f(v):
    """Decimal -> float, fechas -> iso, resto igual."""
    if v is None:
        return None
    if hasattr(v, "isoformat"):
        return v.isoformat()
    if v.__class__.__name__ == "Decimal":
        return float(v)
    return v


def fila(obj, campos):
    return {c: _f(getattr(obj, c)) for c in campos}


def usuario_dict(u: Usuario):
    d = fila(u, ["id_usuario", "nombre_completo", "correo", "tipo_documento", "documento", "telefono",
                 "cargo", "matricula_profesional", "estado", "id_cliente"])
    d["rol"] = u.rol_codigo
    d["rol_nombre"] = u.rol.nombre if u.rol else None
    d["tiene_firma"] = bool(u.ruta_firma)
    return d


CAMPOS_CLIENTE = ["id_cliente", "id_asesor", "tipo_documento", "numero_documento", "razon_social", "tipo_cliente",
                  "contacto_nombre", "contacto_cargo", "contacto_correo", "contacto_telefono", "direccion",
                  "ciudad", "estado", "fecha_registro"]
CAMPOS_EDIFICIO = ["id_edificio", "id_cliente", "nombre", "direccion", "barrio", "ciudad", "departamento",
                   "numero_pisos", "numero_equipos", "administrador_nombre", "administrador_telefono",
                   "administrador_correo", "empresa_mantenimiento", "latitud", "longitud", "estado"]
CAMPOS_EQUIPO = ["id_equipo", "id_edificio", "identificacion", "tipo_equipo", "marca", "modelo", "numero_serie",
                 "anio_fabricacion", "capacidad_kg", "capacidad_personas", "numero_paradas", "recorrido_m",
                 "velocidad_ms", "profundidad_foso_mm", "fecha_puesta_marcha", "estado"]


def cliente_dict(c: Cliente):
    d = fila(c, CAMPOS_CLIENTE)
    d["asesor"] = c.asesor.nombre_completo if c.asesor else None
    return d


def edificio_dict(e: Edificio, con_equipos=False):
    d = fila(e, CAMPOS_EDIFICIO)
    d["equipos_registrados"] = len(e.equipos)
    if con_equipos:
        d["equipos"] = [equipo_dict(x) for x in e.equipos]
    return d


def equipo_dict(e: Equipo):
    return fila(e, CAMPOS_EQUIPO)


def cot_equipo_dict(ce: CotizacionEquipo):
    d = fila(ce, ["id_cotizacion_equipo", "id_cotizacion", "id_equipo", "codigo_servicio", "tipo_servicio",
                  "descripcion", "valor", "estado", "fecha_estado"])
    d["estado_etiqueta"] = ETIQUETAS_ESTADO.get(ce.estado, ce.estado)
    d["equipo"] = equipo_dict(ce.equipo) if ce.equipo else None
    d.update(plazo_dict(ce.plazo_dias, ce.fecha_limite_correccion, ce.estado))
    d["fecha_solicitud_visita2"] = _f(ce.fecha_solicitud_visita2)
    return d


def plazo_dict(plazo_dias, fecha_limite, estado) -> dict:
    """Plazo de corrección y días que quedan (solo mientras la 2ª visita está pendiente)."""
    activo = estado in ("NO_CONFORME", "SEGUNDA_VISITA_SOLICITADA", "PROGRAMADO") and fecha_limite is not None
    if isinstance(fecha_limite, str):
        fecha_limite = date.fromisoformat(fecha_limite[:10])
    return {
        "plazo_dias": plazo_dias,
        "fecha_limite_correccion": _f(fecha_limite),
        "dias_restantes": (fecha_limite - date.today()).days if activo else None,
    }


def cotizacion_dict(c: Cotizacion, detalle=False):
    d = fila(c, ["id_cotizacion", "numero_cotizacion", "id_cliente", "id_edificio", "id_asesor", "fecha_cotizacion",
                 "dias_validez", "subtotal", "iva_porcentaje", "iva_valor", "total", "estado", "condiciones",
                 "observaciones", "fecha_envio_cliente", "fecha_respuesta_cliente", "comentario_cliente",
                 "fecha_envio_programacion", "fecha_creacion"])
    d["cliente"] = c.cliente.razon_social if c.cliente else None
    d["edificio"] = c.edificio.nombre if c.edificio else None
    d["asesor"] = c.asesor.nombre_completo if c.asesor else None
    d["cantidad_equipos"] = len(c.equipos)
    if detalle:
        d["equipos"] = [cot_equipo_dict(x) for x in c.equipos]
        d["edificio_detalle"] = fila(c.edificio, CAMPOS_EDIFICIO) if c.edificio else None
    return d


def programacion_dict(p: Programacion):
    d = fila(p, ["id_programacion", "id_cotizacion", "id_inspector", "id_programador", "tipo_visita",
                 "fecha_programada", "hora_inicio", "hora_fin_estimada", "estado", "observaciones", "motivo_cambio"])
    d["inspector"] = p.inspector.nombre_completo if p.inspector else None
    cot = p.cotizacion
    d["numero_cotizacion"] = cot.numero_cotizacion if cot else None
    d["cliente"] = cot.cliente.razon_social if cot and cot.cliente else None
    d["edificio"] = fila(cot.edificio, CAMPOS_EDIFICIO) if cot and cot.edificio else None
    d["equipos"] = [cot_equipo_dict(pe.cotizacion_equipo) for pe in p.equipos]
    return d
