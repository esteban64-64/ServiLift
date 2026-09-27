# app/services/checklist.py
# Aplicabilidad de ítems según las variantes elegidas y resumen de hallazgos.

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models import ChecklistItem, Inspeccion, InspeccionResultado, VarianteTipo

CALIF_CORTA = {"LEVE": "L", "GRAVE": "G", "MUY_GRAVE": "MG"}


def items_aplicables(db: Session, id_inspeccion: int) -> dict[int, bool]:
    filas = db.execute(text("SELECT id_item, aplica FROM v_inspeccion_item_aplica WHERE id_inspeccion = :i"),
                       {"i": id_inspeccion}).all()
    return {f.id_item: bool(f.aplica) for f in filas}


def precargar_no_aplica(db: Session, insp: Inspeccion):
    """Marca NO_APLICA (automático) lo que no corresponde a las variantes y libera lo que vuelve a aplicar.
    Nunca sobreescribe lo que el inspector ya calificó a mano."""
    db.flush()
    aplica = items_aplicables(db, insp.id_inspeccion)
    actuales = {r.id_item: r for r in insp.resultados}
    for id_item, ok in aplica.items():
        r = actuales.get(id_item)
        if not ok and r is None:
            insp.resultados.append(InspeccionResultado(id_item=id_item, resultado="NO_APLICA", no_aplica_automatico=True))
        elif ok and r is not None and r.no_aplica_automatico:
            insp.resultados.remove(r)


def variantes_faltantes(db: Session, insp: Inspeccion) -> list[str]:
    elegidas = {v.id_variante_tipo for v in insp.variantes}
    tipos = db.query(VarianteTipo).filter(VarianteTipo.activo.is_(True), VarianteTipo.obligatoria.is_(True)).all()
    return [t.nombre for t in tipos if t.id_variante_tipo not in elegidas]


def resumen(insp: Inspeccion) -> dict:
    r = {"leves": 0, "graves": 0, "muy_graves": 0, "no_aplica": 0, "cumple": 0, "calificados": 0,
         "corregidos": 0, "no_corregidos": 0}
    for x in insp.resultados:
        if x.resultado == "NO_CUMPLE":
            clave = {"LEVE": "leves", "GRAVE": "graves", "MUY_GRAVE": "muy_graves"}.get(x.calificacion_defecto or "")
            if clave:
                r[clave] += 1
            if x.estado_segunda_visita == "CORREGIDO":
                r["corregidos"] += 1
            elif x.estado_segunda_visita == "NO_CORREGIDO":
                r["no_corregidos"] += 1
        elif x.resultado == "NO_APLICA":
            r["no_aplica"] += 1
        elif x.resultado == "CUMPLE":
            r["cumple"] += 1
        if x.resultado != "NO_VERIFICADO":
            r["calificados"] += 1
    r["total_no_cumple"] = r["leves"] + r["graves"] + r["muy_graves"]
    return r


def pendientes_para_finalizar(db: Session, insp: Inspeccion) -> list[str]:
    errores = []
    faltan = variantes_faltantes(db, insp)
    if faltan:
        errores.append("Faltan variantes del equipo: " + ", ".join(faltan))
    items = db.query(ChecklistItem).filter(ChecklistItem.activo.is_(True)).all()
    res = {r.id_item: r for r in insp.resultados}
    sin_calificar = [i.numero for i in items if i.id_item not in res or res[i.id_item].resultado == "NO_VERIFICADO"]
    if sin_calificar:
        errores.append(f"Hay {len(sin_calificar)} ítems sin calificar (ej. {', '.join(map(str, sorted(sin_calificar)[:10]))})")
    sin_medida = [i.numero for i in items if i.requiere_medicion and i.id_item in res
                  and res[i.id_item].resultado != "NO_APLICA" and not (res[i.id_item].valor_medido or "").strip()]
    if sin_medida:
        errores.append("Ítems con obligación de medida sin valor: " + ", ".join(map(str, sorted(sin_medida))))
    con_foto = {f.id_resultado for f in insp.fotos if f.id_resultado}
    nc_sin_foto = [r.item.numero for r in insp.resultados if r.resultado == "NO_CUMPLE" and r.id_resultado not in con_foto]
    if nc_sin_foto:
        errores.append("Hallazgos (No cumple) sin foto de evidencia: " + ", ".join(map(str, sorted(nc_sin_foto))))
    firmas = {f.tipo_firmante for f in insp.firmas if f.numero_visita == 1}
    for tipo, nombre in (("INSPECTOR", "inspector"), ("TECNICO_MANTENIMIENTO", "técnico de mantenimiento"),
                         ("REPRESENTANTE_EDIFICIO", "representante del edificio")):
        if tipo not in firmas:
            errores.append(f"Falta la firma del {nombre}")
    if not insp.fotos:
        errores.append("Debe adjuntar el registro fotográfico")
    return errores


def pendientes_segunda_visita(insp: Inspeccion) -> list[str]:
    errores = []
    sin_revisar = [r.item.numero for r in insp.resultados if r.resultado == "NO_CUMPLE" and not r.estado_segunda_visita]
    if sin_revisar:
        errores.append("Hallazgos sin marcar como corregido / no corregido: " + ", ".join(map(str, sorted(sin_revisar))))
    firmas = {f.tipo_firmante for f in insp.firmas if f.numero_visita == 2}
    for tipo, nombre in (("INSPECTOR", "inspector"), ("TECNICO_MANTENIMIENTO", "técnico de mantenimiento"),
                         ("REPRESENTANTE_EDIFICIO", "representante del edificio")):
        if tipo not in firmas:
            errores.append(f"Falta la firma del {nombre} (segunda visita)")
    return errores


def calcular_plazo(db, insp: Inspeccion, visita: int) -> int | None:
    """Días para corregir: el menor plazo entre los hallazgos pendientes (el defecto más exigente manda).
    Cada ítem puede tener su propio plazo; si no, se usa el de su calificación (parámetros PLAZO_DIAS_*)."""
    from app.services.flujo import parametro
    por_calif = {c: int(parametro(db, f"PLAZO_DIAS_{c}", d)) for c, d in (("LEVE", "180"), ("GRAVE", "30"), ("MUY_GRAVE", "0"))}
    plazos = []
    for r in insp.resultados:
        pendiente = r.resultado == "NO_CUMPLE" and (visita == 1 or r.estado_segunda_visita != "CORREGIDO")
        if pendiente:
            plazos.append(r.item.plazo_dias if r.item.plazo_dias is not None else por_calif[r.item.calificacion])
    return min(plazos) if plazos else None
