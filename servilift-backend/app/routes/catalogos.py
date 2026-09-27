# app/routes/catalogos.py
# Catálogos que la app descarga (también para trabajar sin señal): variantes, checklist, parámetros,
# instrumentos de medición. Notificaciones del usuario.

from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import (
    ChecklistCategoria, ChecklistItem, InstrumentoMedicion, Notificacion, Parametro, Usuario, VarianteTipo,
)
from app.routes.serializers import fila
from app.security import ADMIN, INSPECTOR, get_current_user, require_roles

router = APIRouter(tags=["Catálogos y notificaciones"])


class ParametroIn(BaseModel):
    valor: str


class InstrumentoIn(BaseModel):
    codigo: str
    tipo: str
    marca: str | None = None
    serial: str | None = None
    id_inspector: int | None = None
    fecha_calibracion: date | None = None
    vence_calibracion: date | None = None
    estado: str = "ACTIVO"


@router.get("/catalogos/variantes")
def variantes(db: Session = Depends(get_db), _: Usuario = Depends(get_current_user)):
    tipos = db.query(VarianteTipo).filter(VarianteTipo.activo.is_(True)).order_by(VarianteTipo.orden).all()
    return [fila(t, ["id_variante_tipo", "codigo", "nombre", "obligatoria"]) |
            {"opciones": [fila(o, ["id_variante_opcion", "codigo", "nombre"]) for o in t.opciones if o.activo]}
            for t in tipos]


@router.get("/catalogos/checklist")
def checklist(db: Session = Depends(get_db), _: Usuario = Depends(get_current_user)):
    cats = db.query(ChecklistCategoria).filter(ChecklistCategoria.activo.is_(True)).order_by(ChecklistCategoria.orden).all()
    items = db.query(ChecklistItem).filter(ChecklistItem.activo.is_(True)).order_by(ChecklistItem.orden).all()
    campos = ["id_item", "numero", "codigo", "descripcion", "criterio_cumplimiento", "calificacion",
              "requiere_medicion", "requiere_foto_medicion", "unidad_medida"]
    return [fila(c, ["id_categoria", "codigo", "nombre", "norma"]) |
            {"items": [fila(i, campos) for i in items if i.id_categoria == c.id_categoria]} for c in cats]


@router.get("/catalogos/parametros")
def parametros(db: Session = Depends(get_db), _: Usuario = Depends(get_current_user)):
    return {p.clave: p.valor for p in db.query(Parametro).all()}


@router.put("/catalogos/parametros/{clave}")
def actualizar_parametro(clave: str, datos: ParametroIn, db: Session = Depends(get_db),
                         _: Usuario = Depends(require_roles(ADMIN))):
    p = db.get(Parametro, clave)
    if not p:
        raise HTTPException(404, "Parámetro no encontrado")
    p.valor = datos.valor
    db.commit()
    return {clave: p.valor}


@router.get("/instrumentos")
def instrumentos(db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    q = db.query(InstrumentoMedicion)
    if usuario.rol_codigo == INSPECTOR:
        q = q.filter(InstrumentoMedicion.estado == "ACTIVO")
    return [fila(i, ["id_instrumento", "codigo", "tipo", "marca", "serial", "id_inspector", "fecha_calibracion",
                     "vence_calibracion", "estado"]) for i in q.order_by(InstrumentoMedicion.tipo, InstrumentoMedicion.codigo)]


@router.post("/instrumentos", status_code=201)
def crear_instrumento(datos: InstrumentoIn, db: Session = Depends(get_db), _: Usuario = Depends(require_roles(ADMIN))):
    if db.query(InstrumentoMedicion).filter(InstrumentoMedicion.codigo == datos.codigo).first():
        raise HTTPException(409, "Ya existe un instrumento con ese código")
    i = InstrumentoMedicion(**datos.model_dump())
    db.add(i)
    db.commit()
    return fila(i, ["id_instrumento", "codigo", "tipo", "id_inspector", "estado"])


@router.get("/notificaciones")
def notificaciones(solo_no_leidas: bool = False, db: Session = Depends(get_db),
                   usuario: Usuario = Depends(get_current_user)):
    q = db.query(Notificacion).filter(Notificacion.id_usuario_destino == usuario.id_usuario)
    if solo_no_leidas:
        q = q.filter(Notificacion.leida.is_(False))
    return [fila(n, ["id_notificacion", "titulo", "mensaje", "tipo", "id_referencia", "enlace", "leida",
                     "fecha_creacion"]) for n in q.order_by(Notificacion.id_notificacion.desc()).limit(100)]


@router.put("/notificaciones/{id_notificacion}/leida")
def marcar_leida(id_notificacion: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    n = db.get(Notificacion, id_notificacion)
    if not n or n.id_usuario_destino != usuario.id_usuario:
        raise HTTPException(404, "Notificación no encontrada")
    n.leida = True
    db.commit()
    return {"ok": True}
