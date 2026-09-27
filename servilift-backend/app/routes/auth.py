# app/routes/auth.py

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Usuario
from app.routes.serializers import usuario_dict
from app.routes.usuarios import MIN_CONTRASENA
from app.security import create_access_token, get_current_user, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["Autenticación"])


class LoginIn(BaseModel):
    correo: str
    contrasena: str


class CambioContrasenaIn(BaseModel):
    actual: str
    nueva: str


@router.post("/login")
def login(datos: LoginIn, db: Session = Depends(get_db)):
    usuario = db.query(Usuario).filter(Usuario.correo == datos.correo.lower()).first()
    if not usuario or not verify_password(datos.contrasena, usuario.contrasena_hash):
        raise HTTPException(401, "Correo o contraseña incorrectos")
    if usuario.estado != "ACTIVO":
        raise HTTPException(403, "Usuario inactivo")
    usuario.ultima_sesion = datetime.now()
    db.commit()
    return {"access_token": create_access_token(usuario), "token_type": "bearer", "usuario": usuario_dict(usuario)}


@router.get("/me")
def me(usuario: Usuario = Depends(get_current_user)):
    return usuario_dict(usuario)


@router.post("/cambiar-contrasena")
def cambiar_contrasena(datos: CambioContrasenaIn, usuario: Usuario = Depends(get_current_user),
                       db: Session = Depends(get_db)):
    if not verify_password(datos.actual, usuario.contrasena_hash):
        raise HTTPException(400, "La contraseña actual no es correcta")
    if len(datos.nueva) < MIN_CONTRASENA:
        raise HTTPException(400, f"La nueva contraseña debe tener al menos {MIN_CONTRASENA} caracteres")
    usuario.contrasena_hash = hash_password(datos.nueva)
    db.commit()
    return {"ok": True}
