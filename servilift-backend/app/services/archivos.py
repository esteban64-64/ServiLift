# app/services/archivos.py
# Guardado de fotos, firmas y PDFs bajo settings.STORAGE_DIR.
# En la base se guarda la ruta relativa (ej. inspecciones/12/fotos/abc.jpg).

import base64
import hashlib
import os
import uuid
from io import BytesIO

from fastapi import HTTPException, UploadFile
from PIL import Image, ImageOps

from app.config import settings

EXT_IMAGEN = {".jpg", ".jpeg", ".png", ".webp", ".heic"}


def ruta_absoluta(relativa: str) -> str:
    return os.path.join(settings.STORAGE_DIR, relativa)


def _asegurar_dir(relativa: str):
    os.makedirs(os.path.dirname(ruta_absoluta(relativa)), exist_ok=True)


def guardar_foto(id_inspeccion: int, archivo: UploadFile) -> dict:
    ext = os.path.splitext(archivo.filename or "")[1].lower() or ".jpg"
    if ext not in EXT_IMAGEN:
        raise HTTPException(400, f"Formato de imagen no permitido: {ext}")
    datos = archivo.file.read()
    if len(datos) > settings.MAX_FOTO_MB * 1024 * 1024:
        raise HTTPException(413, f"La foto supera {settings.MAX_FOTO_MB} MB")

    nombre = f"{uuid.uuid4().hex}.jpg"
    rel = f"inspecciones/{id_inspeccion}/fotos/{nombre}"
    rel_min = f"inspecciones/{id_inspeccion}/fotos/min_{nombre}"
    _asegurar_dir(rel)
    try:
        img = ImageOps.exif_transpose(Image.open(BytesIO(datos))).convert("RGB")
    except Exception:
        raise HTTPException(400, "El archivo no es una imagen válida")
    # Se normaliza a JPG de máx. 1920 px para que 100 fotos por equipo no saturen el servidor
    img.thumbnail((1920, 1920))
    img.save(ruta_absoluta(rel), "JPEG", quality=85)
    img.thumbnail((480, 480))
    img.save(ruta_absoluta(rel_min), "JPEG", quality=75)
    return {
        "nombre_archivo": archivo.filename or nombre,
        "ruta_archivo": rel,
        "ruta_miniatura": rel_min,
        "tamano_kb": os.path.getsize(ruta_absoluta(rel)) // 1024,
    }


def guardar_firma_base64(carpeta: str, contenido_base64: str) -> str:
    """Recibe el PNG de la firma (base64, con o sin prefijo data:) y devuelve la ruta relativa."""
    if "," in contenido_base64 and contenido_base64.strip().startswith("data:"):
        contenido_base64 = contenido_base64.split(",", 1)[1]
    try:
        datos = base64.b64decode(contenido_base64, validate=True)
        Image.open(BytesIO(datos)).verify()
    except Exception:
        raise HTTPException(400, "La firma no es una imagen PNG/JPG válida en base64")
    rel = f"{carpeta}/firma_{uuid.uuid4().hex}.png"
    _asegurar_dir(rel)
    with open(ruta_absoluta(rel), "wb") as f:
        f.write(datos)
    return rel


def borrar(relativa: str | None):
    if relativa and os.path.exists(ruta_absoluta(relativa)):
        os.remove(ruta_absoluta(relativa))


def sha256(relativa: str) -> str:
    with open(ruta_absoluta(relativa), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()
