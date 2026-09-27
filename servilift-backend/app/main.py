# app/main.py
# Ejecutar:  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
# (host 0.0.0.0 para que el celular del inspector lo alcance en la red local)

import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.routes import (
    auth, catalogos, certificados, clientes, cotizaciones, dashboard, informes, inspecciones, programacion, seguimiento,
    usuarios,
)

app = FastAPI(title="ServiLift API", version="0.1.0",
              description="Gestión de certificación de ascensores NTC 5926-1: de la cotización al certificado.")

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",  # Flutter web en desarrollo
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

for r in (auth, usuarios, clientes, cotizaciones, programacion, inspecciones, informes, certificados,
          seguimiento, catalogos, dashboard):
    app.include_router(r.router)

# Fotos y firmas (nombres aleatorios). Los PDF se descargan por los endpoints con permisos.
os.makedirs(os.path.join(settings.STORAGE_DIR, "inspecciones"), exist_ok=True)
app.mount("/archivos/inspecciones", StaticFiles(directory=os.path.join(settings.STORAGE_DIR, "inspecciones")),
          name="archivos")


@app.get("/")
def root():
    return {"message": "ServiLift API funcionando"}
