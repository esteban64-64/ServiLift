"""Crea el primer usuario administrador.

Uso (desde servilift-backend, con el .env configurado):
    python -m scripts.crear_admin "Nombre Apellido" admin@empresa.com
La contraseña se pide por consola (no queda en el historial).
"""
import getpass
import sys

from app.database import SessionLocal
from app.models import Rol, Usuario
from app.security import hash_password


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    nombre, correo = sys.argv[1], sys.argv[2].lower()
    clave = getpass.getpass("Contraseña (mín. 8 caracteres): ")
    if len(clave) < 8:
        sys.exit("La contraseña debe tener al menos 8 caracteres")
    db = SessionLocal()
    try:
        if db.query(Usuario).filter(Usuario.correo == correo).first():
            sys.exit(f"Ya existe un usuario con el correo {correo}")
        rol = db.query(Rol).filter(Rol.codigo == "ADMIN").one()
        db.add(Usuario(id_rol=rol.id_rol, nombre_completo=nombre, correo=correo, contrasena_hash=hash_password(clave)))
        db.commit()
        print(f"Administrador {correo} creado.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
