# app/routes/clientes.py
# El asesor registra clientes, sus edificios y los equipos de cada edificio.

from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Cliente, Edificio, Equipo, Usuario
from app.routes.serializers import cliente_dict, edificio_dict, equipo_dict, usuario_dict
from app.routes.usuarios import UsuarioIn, crear_usuario
from app.security import ASESOR, CLIENTE, get_current_user, require_roles

router = APIRouter(tags=["Clientes, edificios y equipos"])


# ============================================
# ESQUEMAS
# ============================================
class ClienteIn(BaseModel):
    tipo_documento: str = "NIT"
    numero_documento: str
    razon_social: str
    tipo_cliente: str = "PROPIEDAD_HORIZONTAL"
    contacto_nombre: str | None = None
    contacto_cargo: str | None = None
    contacto_correo: EmailStr | None = None
    contacto_telefono: str | None = None
    direccion: str | None = None
    ciudad: str | None = None


class ClienteUpdate(ClienteIn):
    tipo_documento: str | None = None
    numero_documento: str | None = None
    razon_social: str | None = None
    tipo_cliente: str | None = None
    estado: str | None = None


class EdificioIn(BaseModel):
    nombre: str
    direccion: str
    ciudad: str
    barrio: str | None = None
    departamento: str | None = None
    numero_pisos: int | None = None
    numero_equipos: int = 0
    administrador_nombre: str | None = None
    administrador_telefono: str | None = None
    administrador_correo: EmailStr | None = None
    empresa_mantenimiento: str | None = None


class EdificioUpdate(EdificioIn):
    nombre: str | None = None
    direccion: str | None = None
    ciudad: str | None = None
    numero_equipos: int | None = None
    estado: str | None = None


class EquipoIn(BaseModel):
    identificacion: str
    tipo_equipo: str = "ASCENSOR_PASAJEROS"
    marca: str | None = None
    modelo: str | None = None
    numero_serie: str | None = None
    anio_fabricacion: int | None = None
    capacidad_kg: int | None = None
    capacidad_personas: int | None = None
    numero_paradas: int | None = None
    recorrido_m: float | None = None
    velocidad_ms: float | None = None
    profundidad_foso_mm: int | None = None
    fecha_puesta_marcha: date | None = None


class EquipoUpdate(EquipoIn):
    identificacion: str | None = None
    tipo_equipo: str | None = None
    estado: str | None = None


class UsuarioClienteIn(BaseModel):
    nombre_completo: str
    correo: EmailStr
    contrasena: str
    telefono: str | None = None
    cargo: str | None = None


# ============================================
# ACCESO
# ============================================
def _cliente_visible(db: Session, id_cliente: int, usuario: Usuario) -> Cliente:
    c = db.get(Cliente, id_cliente)
    if not c:
        raise HTTPException(404, "Cliente no encontrado")
    if usuario.rol_codigo == CLIENTE and usuario.id_cliente != c.id_cliente:
        raise HTTPException(403, "No tiene acceso a este cliente")
    return c


def _edificio_visible(db: Session, id_edificio: int, usuario: Usuario) -> Edificio:
    e = db.get(Edificio, id_edificio)
    if not e:
        raise HTTPException(404, "Edificio no encontrado")
    _cliente_visible(db, e.id_cliente, usuario)
    return e


# ============================================
# CLIENTES
# ============================================
@router.get("/clientes")
def listar_clientes(buscar: str | None = None, solo_mios: bool = False, db: Session = Depends(get_db),
                    usuario: Usuario = Depends(get_current_user)):
    q = db.query(Cliente)
    if usuario.rol_codigo == CLIENTE:
        q = q.filter(Cliente.id_cliente == usuario.id_cliente)
    if solo_mios:
        q = q.filter(Cliente.id_asesor == usuario.id_usuario)
    if buscar:
        like = f"%{buscar}%"
        q = q.filter(or_(Cliente.razon_social.like(like), Cliente.numero_documento.like(like)))
    return [cliente_dict(c) for c in q.order_by(Cliente.razon_social).all()]


@router.post("/clientes", status_code=201)
def crear_cliente(datos: ClienteIn, db: Session = Depends(get_db), usuario: Usuario = Depends(require_roles(ASESOR))):
    existe = db.query(Cliente).filter(Cliente.tipo_documento == datos.tipo_documento,
                                      Cliente.numero_documento == datos.numero_documento).first()
    if existe:
        raise HTTPException(409, f"Ya existe el cliente {existe.razon_social} con ese documento")
    c = Cliente(id_asesor=usuario.id_usuario, **datos.model_dump())
    db.add(c)
    db.commit()
    db.refresh(c)
    return cliente_dict(c)


@router.get("/clientes/{id_cliente}")
def obtener_cliente(id_cliente: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    c = _cliente_visible(db, id_cliente, usuario)
    d = cliente_dict(c)
    d["edificios"] = [edificio_dict(e, con_equipos=True) for e in c.edificios]
    d["usuarios"] = [usuario_dict(u) for u in db.query(Usuario).filter(Usuario.id_cliente == c.id_cliente)]
    return d


@router.put("/clientes/{id_cliente}")
def actualizar_cliente(id_cliente: int, datos: ClienteUpdate, db: Session = Depends(get_db),
                       usuario: Usuario = Depends(require_roles(ASESOR))):
    c = _cliente_visible(db, id_cliente, usuario)
    for k, v in datos.model_dump(exclude_unset=True).items():
        setattr(c, k, v)
    db.commit()
    return cliente_dict(c)


@router.post("/clientes/{id_cliente}/usuarios", status_code=201)
def crear_usuario_cliente(id_cliente: int, datos: UsuarioClienteIn, db: Session = Depends(get_db),
                          usuario: Usuario = Depends(require_roles())):
    """Acceso al portal para el cliente. Solo el administrador crea usuarios."""
    _cliente_visible(db, id_cliente, usuario)
    u = crear_usuario(db, UsuarioIn(rol=CLIENTE, id_cliente=id_cliente, **datos.model_dump()))
    db.commit()
    return usuario_dict(u)


# ============================================
# EDIFICIOS
# ============================================
@router.get("/clientes/{id_cliente}/edificios")
def listar_edificios(id_cliente: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    c = _cliente_visible(db, id_cliente, usuario)
    return [edificio_dict(e, con_equipos=True) for e in c.edificios]


@router.post("/clientes/{id_cliente}/edificios", status_code=201)
def crear_edificio(id_cliente: int, datos: EdificioIn, db: Session = Depends(get_db),
                   usuario: Usuario = Depends(require_roles(ASESOR))):
    _cliente_visible(db, id_cliente, usuario)
    e = Edificio(id_cliente=id_cliente, **datos.model_dump())
    db.add(e)
    db.commit()
    db.refresh(e)
    return edificio_dict(e, con_equipos=True)


@router.get("/edificios/{id_edificio}")
def obtener_edificio(id_edificio: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    return edificio_dict(_edificio_visible(db, id_edificio, usuario), con_equipos=True)


@router.put("/edificios/{id_edificio}")
def actualizar_edificio(id_edificio: int, datos: EdificioUpdate, db: Session = Depends(get_db),
                        usuario: Usuario = Depends(require_roles(ASESOR))):
    e = _edificio_visible(db, id_edificio, usuario)
    for k, v in datos.model_dump(exclude_unset=True).items():
        setattr(e, k, v)
    db.commit()
    return edificio_dict(e, con_equipos=True)


# ============================================
# EQUIPOS
# ============================================
@router.post("/edificios/{id_edificio}/equipos", status_code=201)
def crear_equipo(id_edificio: int, datos: EquipoIn, db: Session = Depends(get_db),
                 usuario: Usuario = Depends(require_roles(ASESOR))):
    e = _edificio_visible(db, id_edificio, usuario)
    if any(x.identificacion.lower() == datos.identificacion.lower() for x in e.equipos):
        raise HTTPException(409, f"Ya existe '{datos.identificacion}' en este edificio")
    eq = Equipo(id_edificio=id_edificio, **datos.model_dump())
    db.add(eq)
    db.flush()
    # El número de ascensores declarado nunca queda por debajo de los registrados
    e.numero_equipos = max(e.numero_equipos or 0, len(e.equipos))
    db.commit()
    db.refresh(eq)
    return equipo_dict(eq)


@router.post("/edificios/{id_edificio}/equipos/generar", status_code=201)
def generar_equipos(id_edificio: int, db: Session = Depends(get_db),
                    usuario: Usuario = Depends(require_roles(ASESOR))):
    """Crea 'Ascensor 1..N' según numero_equipos del edificio (para registrar rápido y completar después)."""
    e = _edificio_visible(db, id_edificio, usuario)
    existentes = {x.identificacion.lower() for x in e.equipos}
    creados = []
    for i in range(1, (e.numero_equipos or 0) + 1):
        nombre = f"Ascensor {i}"
        if nombre.lower() not in existentes:
            eq = Equipo(id_edificio=id_edificio, identificacion=nombre)
            db.add(eq)
            creados.append(eq)
    db.commit()
    return [equipo_dict(x) for x in creados]


@router.put("/equipos/{id_equipo}")
def actualizar_equipo(id_equipo: int, datos: EquipoUpdate, db: Session = Depends(get_db),
                      usuario: Usuario = Depends(require_roles(ASESOR))):
    eq = db.get(Equipo, id_equipo)
    if not eq:
        raise HTTPException(404, "Equipo no encontrado")
    _edificio_visible(db, eq.id_edificio, usuario)
    for k, v in datos.model_dump(exclude_unset=True).items():
        setattr(eq, k, v)
    db.commit()
    return equipo_dict(eq)
