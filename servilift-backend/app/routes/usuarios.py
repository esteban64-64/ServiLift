# app/routes/usuarios.py

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Cliente, Rol, Usuario
from app.routes.serializers import usuario_dict
from app.security import ADMIN, CLIENTE, PROGRAMACION, get_current_user, hash_password, require_roles
from app.services.archivos import guardar_firma_base64

router = APIRouter(prefix="/usuarios", tags=["Usuarios"])

# Solo el ADMIN crea usuarios y restablece contraseñas.
MIN_CONTRASENA = 6


class UsuarioIn(BaseModel):
    rol: str
    nombre_completo: str
    correo: EmailStr
    contrasena: str
    tipo_documento: str | None = None
    documento: str | None = None
    telefono: str | None = None
    cargo: str | None = None
    matricula_profesional: str | None = None
    id_cliente: int | None = None


class UsuarioUpdate(BaseModel):
    nombre_completo: str | None = None
    telefono: str | None = None
    cargo: str | None = None
    matricula_profesional: str | None = None
    estado: str | None = None
    rol: str | None = None
    id_cliente: int | None = None
    contrasena: str | None = None   # restablecer contraseña (solo administrador)


class FirmaIn(BaseModel):
    firma_base64: str


def crear_usuario(db: Session, datos: UsuarioIn) -> Usuario:
    rol = db.query(Rol).filter(Rol.codigo == datos.rol).first()
    if not rol:
        raise HTTPException(400, f"Rol inválido: {datos.rol}")
    if db.query(Usuario).filter(Usuario.correo == datos.correo.lower()).first():
        raise HTTPException(409, "Ya existe un usuario con ese correo")
    if rol.codigo == CLIENTE and not datos.id_cliente:
        raise HTTPException(400, "Un usuario cliente debe pertenecer a un cliente (id_cliente)")
    if datos.id_cliente and not db.get(Cliente, datos.id_cliente):
        raise HTTPException(400, "El cliente indicado no existe")
    if len(datos.contrasena) < MIN_CONTRASENA:
        raise HTTPException(400, f"La contraseña debe tener al menos {MIN_CONTRASENA} caracteres")
    u = Usuario(
        id_rol=rol.id_rol, id_cliente=datos.id_cliente if rol.codigo == CLIENTE else None,
        nombre_completo=datos.nombre_completo, correo=datos.correo.lower(),
        contrasena_hash=hash_password(datos.contrasena), tipo_documento=datos.tipo_documento,
        documento=datos.documento, telefono=datos.telefono, cargo=datos.cargo,
        matricula_profesional=datos.matricula_profesional,
    )
    db.add(u)
    db.flush()
    return u


@router.get("")
def listar(rol: str | None = None, db: Session = Depends(get_db),
           usuario: Usuario = Depends(require_roles(PROGRAMACION))):
    q = db.query(Usuario).join(Rol)
    if usuario.rol_codigo != ADMIN:
        q = q.filter(Rol.codigo == "INSPECTOR", Usuario.estado == "ACTIVO")  # programación solo ve inspectores
    elif rol:
        q = q.filter(Rol.codigo == rol)
    return [usuario_dict(u) for u in q.order_by(Usuario.nombre_completo).all()]


@router.post("", status_code=201)
def crear(datos: UsuarioIn, db: Session = Depends(get_db), _: Usuario = Depends(require_roles(ADMIN))):
    u = crear_usuario(db, datos)
    db.commit()
    return usuario_dict(u)


@router.put("/{id_usuario}")
def actualizar(id_usuario: int, datos: UsuarioUpdate, db: Session = Depends(get_db),
               _: Usuario = Depends(require_roles(ADMIN))):
    u = db.get(Usuario, id_usuario)
    if not u:
        raise HTTPException(404, "Usuario no encontrado")
    cambios = datos.model_dump(exclude_unset=True)
    if "rol" in cambios:
        rol = db.query(Rol).filter(Rol.codigo == cambios.pop("rol")).first()
        if not rol:
            raise HTTPException(400, "Rol inválido")
        u.id_rol = rol.id_rol
    if "contrasena" in cambios:
        nueva = cambios.pop("contrasena") or ""
        if len(nueva) < MIN_CONTRASENA:
            raise HTTPException(400, f"La contraseña debe tener al menos {MIN_CONTRASENA} caracteres")
        u.contrasena_hash = hash_password(nueva)
    for k, v in cambios.items():
        setattr(u, k, v)
    db.commit()
    db.refresh(u)
    return usuario_dict(u)


@router.put("/me/firma")
def registrar_mi_firma(datos: FirmaIn, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    """El director técnico / inspector registra su firma una vez y se reutiliza en los informes."""
    usuario.ruta_firma = guardar_firma_base64(f"firmas/usuarios/{usuario.id_usuario}", datos.firma_base64)
    db.commit()
    return {"ok": True}
