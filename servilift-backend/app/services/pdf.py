# app/services/pdf.py
# PDF del informe de inspección (estructura de la plantilla NTC 5926-1) y del certificado con QR.

import json
import os
import uuid
from datetime import datetime

from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing, Line, PolyLine
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    Image, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle,
)
from sqlalchemy.orm import Session

from app.config import settings
from app.models import Certificado, ChecklistItem, Informe, Usuario
from app.services.archivos import ruta_absoluta
from app.services.checklist import CALIF_CORTA
from app.services.flujo import parametro

AZUL = colors.HexColor("#1F3A5F")
GRIS = colors.HexColor("#E8ECF1")

_estilos = getSampleStyleSheet()
P = ParagraphStyle("p", parent=_estilos["Normal"], fontSize=8, leading=10)
PB = ParagraphStyle("pb", parent=P, fontName="Helvetica-Bold")
PT = ParagraphStyle("pt", parent=_estilos["Title"], fontSize=12, leading=14, textColor=AZUL)
PS = ParagraphStyle("ps", parent=PB, fontSize=9, textColor=colors.white)
PC = ParagraphStyle("pc", parent=P, alignment=TA_CENTER)

RESULTADO_CORTO = {"CUMPLE": "C", "NO_CUMPLE": "NC", "NO_APLICA": "NA", "NO_VERIFICADO": "-"}


def _p(txt, estilo=P):
    return Paragraph("" if txt is None else str(txt).replace("\n", "<br/>"), estilo)


def _fecha(v):
    if not v:
        return "NI"
    if isinstance(v, str):
        v = datetime.fromisoformat(v)
    return v.strftime("%d/%m/%Y")


def _seccion(titulo):
    t = Table([[_p(titulo, PS)]], colWidths=[19 * cm])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), AZUL), ("TOPPADDING", (0, 0), (-1, -1), 3),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]))
    return t


def _grilla(filas, anchos):
    """filas de pares etiqueta/valor."""
    datos = [[_p(c, PB if i % 2 == 0 else P) for i, c in enumerate(f)] for f in filas]
    t = Table(datos, colWidths=anchos)
    t.setStyle(TableStyle([("GRID", (0, 0), (-1, -1), 0.4, colors.grey), ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]
                          + [("BACKGROUND", (c, 0), (c, -1), GRIS) for c in range(0, len(anchos), 2)]))
    return t


def _imagen(relativa, ancho, alto):
    ruta = ruta_absoluta(relativa) if relativa else None
    if not ruta or not os.path.exists(ruta):
        return _p("(sin imagen)", PC)
    img = Image(ruta)
    escala = min(ancho / img.imageWidth, alto / img.imageHeight)
    img.drawWidth, img.drawHeight = img.imageWidth * escala, img.imageHeight * escala
    return img


def _pie(db: Session, titulo: str, borrador: bool = False):
    empresa = parametro(db, "EMPRESA_NOMBRE", "ServiLift")
    codigo = parametro(db, "INFORME_CODIGO_FORMATO")
    version = parametro(db, "INFORME_VERSION_FORMATO", "1")

    def dibujar(canvas, doc):
        canvas.saveState()
        canvas.setFont("Helvetica", 7)
        canvas.setFillColor(colors.grey)
        texto = f"{empresa} · {titulo}" + (f" · Código {codigo} v{version}" if codigo else "")
        canvas.drawString(1.3 * cm, 1 * cm, texto)
        canvas.drawRightString(letter[0] - 1.3 * cm, 1 * cm, f"Página {doc.page}")
        if borrador:
            canvas.setFont("Helvetica-Bold", 60)
            canvas.setFillColor(colors.Color(0.8, 0.1, 0.1, alpha=0.12))
            canvas.translate(letter[0] / 2, letter[1] / 2)
            canvas.rotate(40)
            canvas.drawCentredString(0, 0, "BORRADOR - SIN APROBAR")
        canvas.restoreState()

    return dibujar


def _destino(carpeta: str, numero: str) -> str:
    # uuid en el nombre: los PDF se sirven por URL y no deben ser adivinables
    rel = f"{carpeta}/{numero}_{uuid.uuid4().hex[:12]}.pdf"
    os.makedirs(os.path.dirname(ruta_absoluta(rel)), exist_ok=True)
    return rel


# ============================================
# INFORME DE INSPECCIÓN
# ============================================
def _marca(tipo, tam=12):
    """✔ verde (cumple / corregido) o ✘ roja (no cumple) dibujadas como vectores: se ven igual en cualquier visor."""
    if tipo not in ("si", "no"):
        return _p("")
    d = Drawing(tam, tam)
    if tipo == "si":
        d.add(PolyLine([1, tam * .5, tam * .4, 1.5, tam - 1, tam - 1], strokeColor=colors.HexColor("#0E7C4A"),
                       strokeWidth=2.2, strokeLineCap=1, strokeLineJoin=1))
    else:
        rojo = colors.HexColor("#C0392B")
        d.add(Line(2, 2, tam - 2, tam - 2, strokeColor=rojo, strokeWidth=2.2, strokeLineCap=1))
        d.add(Line(2, tam - 2, tam - 2, 2, strokeColor=rojo, strokeWidth=2.2, strokeLineCap=1))
    return d


def _leyenda():
    t = Table([[_p("CUMPLE"), _marca("si", 9), _p("NO CUMPLE"), _marca("no", 9), _p("NO APLICA = NA")]],
              colWidths=[1.6 * cm, 0.6 * cm, 2 * cm, 0.6 * cm, 3.4 * cm])
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("LEFTPADDING", (0, 0), (-1, -1), 1)]))
    return t


def _texto_plazo(dias):
    if dias is None:
        return ""
    return "LOS HALLAZGOS DEBERÁN CORREGIRSE DE FORMA INMEDIATA." if int(dias) == 0 \
        else f"TIENE {dias} DÍAS PARA CORREGIR ESTOS HALLAZGOS."


def generar_informe(db: Session, informe: Informe, borrador: bool = False, visita: int | None = None) -> str:
    """Informe con el formato de la plantilla: datos, resumen con tiempos de solución, hallazgos (solo No cumple)
    con su foto en la fila y columnas de 2ª visita, evidencia de equipos de medición, firmas de ambas visitas e
    ítems que no aplican. visita=1 genera el informe de primera visita (columnas de 2ª visita vacías);
    visita=2 el de segunda visita (corregido / no corregido y foto de la corrección)."""
    visita = visita or informe.visita_actual
    insp = informe.inspeccion
    snap = json.loads(insp.datos_equipo_json or "{}")
    cli, edi, eq = snap.get("cliente", {}), snap.get("edificio", {}), snap.get("equipo", {})
    variantes = {v.tipo.codigo: v.opcion.nombre for v in insp.variantes}
    res = {r.id_item: r for r in insp.resultados}
    items = db.query(ChecklistItem).filter(ChecklistItem.activo.is_(True)).order_by(ChecklistItem.numero).all()
    firmas = {(f.numero_visita, f.tipo_firmante): f for f in insp.firmas}
    inspector2 = db.get(Usuario, insp.id_inspector_visita2) if insp.id_inspector_visita2 else None
    director = informe.director.nombre_completo if informe.director else ""
    corte_v2 = insp.fecha_visita2

    def es_foto_v2(f):
        return bool(corte_v2 and f.fecha_captura and f.fecha_captura >= corte_v2)

    fotos_por_res = {}
    for f in insp.fotos:
        if f.id_resultado and f.incluir_en_informe and (visita == 2 or not es_foto_v2(f)):
            fotos_por_res.setdefault(f.id_resultado, []).append(f)

    sufijo = "1V" if visita == 1 else "2V"
    rel = _destino("informes/borradores" if borrador else "informes", f"{informe.numero_informe}-{sufijo}")
    doc = SimpleDocTemplate(ruta_absoluta(rel), pagesize=letter, leftMargin=1.3 * cm, rightMargin=1.3 * cm,
                            topMargin=1.2 * cm, bottomMargin=1.6 * cm, title=f"{informe.numero_informe} {sufijo}")
    titulo = parametro(db, "INFORME_TITULO", "INFORME DE INSPECCIÓN DE ASCENSORES NTC 5926-1:2012")
    h = []

    visita_txt = "PRIMERA VISITA" if visita == 1 else "SEGUNDA VISITA / CIERRE DE HALLAZGOS"
    emision = informe.fecha_aprobacion_visita1 if visita == 1 and informe.fecha_aprobacion_visita1 else informe.fecha_aprobacion
    cab = Table([[_p(parametro(db, "EMPRESA_NOMBRE", "ServiLift"), PB), _p(f"{titulo}<br/><font size=9>{visita_txt}</font>", PT),
                  _p(f"Informe: <b>{informe.numero_informe}-{sufijo}</b><br/>Emisión: {_fecha(emision)}")]],
                colWidths=[4 * cm, 10.5 * cm, 4.5 * cm])
    cab.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.8, AZUL), ("INNERGRID", (0, 0), (-1, -1), 0.4, colors.grey),
                             ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]))
    h += [cab, Spacer(1, 6)]

    h += [_seccion("DATOS DEL CLIENTE"), _grilla([
        ["Número de cotización", snap.get("numero_cotizacion"), "Consecutivo único", insp.numero_inspeccion],
        ["Cliente / Razón social", cli.get("razon_social"), "NIT o C.C.", f"{cli.get('tipo_documento', '')} {cli.get('numero_documento', '')}"],
        ["Dirección y ciudad", f"{edi.get('direccion', '')}, {edi.get('ciudad', '')}", "Edificio", edi.get("nombre")],
        ["Torre / Nº de ascensor", eq.get("identificacion"), "Identificación (serial)", eq.get("numero_serie") or "NI"],
        ["Conservación de la información", insp.conservacion_informacion, "Tipo de acrílico", insp.tipo_acrilico or "NI"],
    ], [4 * cm, 5.5 * cm, 4 * cm, 5.5 * cm]), Spacer(1, 4)]

    h += [_seccion("DATOS DE LA EMPRESA DE MANTENIMIENTO E INSTALACIÓN"), _grilla([
        ["Nombre de la empresa", insp.empresa_mantenimiento or "NI", "Último mantenimiento", _fecha(insp.fecha_ultimo_mantenimiento)],
        ["Nombre del técnico", insp.tecnico_mantenimiento or "NI", "Puesta en marcha", _fecha(insp.fecha_puesta_marcha)],
        ["Última inspección", _fecha(insp.fecha_ultima_inspeccion), "", ""],
    ], [4 * cm, 5.5 * cm, 4 * cm, 5.5 * cm]), Spacer(1, 4)]

    h += [_seccion("DATOS DE LA INSPECCIÓN"), _grilla([
        ["Inspector 1ª visita", insp.inspector.nombre_completo, "Atestador", director],
        ["Fecha 1ª visita", _fecha(insp.fecha_inicio), "Fecha de emisión", _fecha(emision)],
        ["Inspector 2ª visita", inspector2.nombre_completo if (inspector2 and visita == 2) else "",
         "Fecha 2ª visita", _fecha(insp.fecha_visita2) if (insp.fecha_visita2 and visita == 2) else ""],
    ], [4 * cm, 5.5 * cm, 4 * cm, 5.5 * cm]), Spacer(1, 4)]

    def var(c):
        return variantes.get(c, "NI")

    h += [_seccion("CARACTERÍSTICAS TÉCNICAS"), _grilla([
        ["Tipo de accionamiento", var("ACCIONAMIENTO"), "Enhebrado", var("ENHEBRADO"), "Capacidad kg", insp.capacidad_kg or "NI"],
        ["Tipo de máquina", var("MAQUINA"), "Tracción por", var("TRACCION_POR"), "Capacidad personas", insp.capacidad_personas or "NI"],
        ["Cuarto de máquinas", var("CUARTO_MAQUINAS"), "Tipo de buffer", var("TIPO_BUFFER"), "Nº paradas", insp.numero_paradas or "NI"],
        ["Limitador cabina", var("LIMITADOR_CABINA"), "Limitador contrapeso", var("LIMITADOR_CONTRAPESO"), "Prof. foso mm", insp.profundidad_foso_mm or "NI"],
        ["Cuarto de poleas", var("CUARTO_POLEAS"), "Puerta de socorro", var("PUERTA_SOCORRO"), "Tipo de puerta", var("TIPO_PUERTA")],
        ["Mirilla de puertas", var("MIRILLA_PUERTAS"), "", "", "", ""],
    ], [3.2 * cm, 3.3 * cm, 3.2 * cm, 3.3 * cm, 3 * cm, 3 * cm]), Spacer(1, 4)]

    # Resumen con tiempos de solución por calificación
    plazos = {c: parametro(db, f"PLAZO_DIAS_{c}", d) for c, d in (("LEVE", "180"), ("GRAVE", "30"), ("MUY_GRAVE", "0"))}
    nc = [(it, res[it.id_item]) for it in items if it.id_item in res and res[it.id_item].resultado == "NO_CUMPLE"]
    na = [(it, res[it.id_item]) for it in items if it.id_item in res and res[it.id_item].resultado == "NO_APLICA"]
    cuenta = {c: sum(1 for it, _ in nc if it.calificacion == c) for c in ("LEVE", "GRAVE", "MUY_GRAVE")}
    filas_r = [[_p("TIPO DE HALLAZGO", PB), _p("Cantidad", PB), _p("TIEMPOS DE SOLUCIÓN Y CONVENCIÓN DEL INFORME", PB)]]
    for c, nombre in (("LEVE", "LEVES"), ("GRAVE", "GRAVES"), ("MUY_GRAVE", "MUY GRAVES")):
        filas_r.append([_p(f"Cantidad de ítems NO cumplidos {nombre}"), _p(cuenta[c], PC),
                        _p(_texto_plazo(plazos[c]) if cuenta[c] else "")])
    filas_r.append([_p("CANTIDAD TOTAL NO APLICA: " + str(len(na)), PB), _p(f"TOTAL {len(nc)}", PC), _leyenda()])
    concepto = informe.concepto if visita == informe.visita_actual else (informe.concepto_visita1 or informe.concepto)
    extra = f"Concepto: <b>{(concepto or '').replace('_', ' ')}</b>"
    if visita == 1 and (informe.concepto_visita1 or informe.concepto) == "NO_CONFORME" and informe.plazo_dias is not None \
            and informe.visita_actual == 1:
        extra += f" · Plazo para corregir y solicitar la 2ª visita: hasta <b>{_fecha(informe.fecha_limite_correccion)}</b>"
    if visita == 2:
        extra += f" · 2ª visita: {informe.total_corregidos} corregidos, {informe.total_no_corregidos} no corregidos"
    filas_r.append([_p(extra), "", ""])
    resumen_t = Table(filas_r, colWidths=[7 * cm, 2.5 * cm, 9.5 * cm])
    resumen_t.setStyle(TableStyle([("GRID", (0, 0), (-1, -1), 0.4, colors.grey), ("BACKGROUND", (0, 0), (-1, 0), GRIS),
                                   ("SPAN", (0, len(filas_r) - 1), (-1, len(filas_r) - 1)), ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]))
    h += [_seccion("RESUMEN DE HALLAZGOS"), resumen_t, Spacer(1, 4)]
    h += [_seccion("ATESTACIÓN"), _p(informe.atestacion or parametro(db, "TEXTO_ATESTACION")), Spacer(1, 4)]
    h += [_seccion("SECCIÓN DE NOTAS Y OBSERVACIONES"), _p(insp.observaciones_generales or " "), Spacer(1, 6)]

    # Hallazgos identificados: solo los No cumple, con su foto y las columnas de 2ª visita
    ph = ParagraphStyle("ph", parent=PB, fontSize=6.5, leading=7.5, alignment=TA_CENTER)
    filas = [[_p("ÍTEM", ph), _p("DEFECTO", ph), _p("DEFE", ph), _p("ESTADO", ph), _p("OBSERVACIONES", ph),
              _p("REGISTRO FOTOGRÁFICO", ph), _p("2ª VISITA", ph), ""],
             ["", "", "", "", "", "", _p("CORREGIDO", ph), _p("NO<br/>CORREGIDO", ph)]]
    for it, r in nc:
        fotos = fotos_por_res.get(r.id_resultado, [])
        v1 = [f for f in fotos if not es_foto_v2(f)]
        v2 = [f for f in fotos if es_foto_v2(f)] if visita == 2 else []
        celdas_foto = []
        for f in (v1[:1] + v2[:1]) or []:
            celdas_foto.append(_imagen(f.ruta_miniatura or f.ruta_archivo, 4.2 * cm, 3.2 * cm))
            if f in v2:
                celdas_foto.append(_p("<i>Corrección 2ª visita</i>", PC))
        if len(fotos) > 2:
            celdas_foto.append(_p(f"<i>+{len(fotos) - len(v1[:1] + v2[:1])} foto(s) en el anexo</i>", PC))
        foto = Table([[c] for c in celdas_foto], colWidths=[4.4 * cm]) if celdas_foto else _p("Sin foto", PC)
        obs = f'<font color="#C0392B"><b>{(r.observacion or "").upper()}</b></font>'
        if r.valor_medido:
            obs += f"<br/>Medida: {r.valor_medido} {r.unidad_medida or ''}"
        if visita == 2 and r.observacion_segunda_visita:
            obs += f"<br/><i>2ª visita: {r.observacion_segunda_visita}</i>"
        corr = r.estado_segunda_visita if visita == 2 else None
        filas.append([_p(it.numero, PC), _p(it.descripcion), _p(CALIF_CORTA[it.calificacion], PC), _marca("no"),
                      _p(obs, PC), foto, _marca("si") if corr == "CORREGIDO" else _p(""),
                      _marca("no") if corr == "NO_CORREGIDO" else _p("")])
    if not nc:
        filas.append([_p("Sin hallazgos: el equipo cumple con los ítems aplicables.", PC), "", "", "", "", "", "", ""])
    th = Table(filas, colWidths=[1.1 * cm, 4.3 * cm, 1.1 * cm, 1.4 * cm, 3.3 * cm, 4.4 * cm, 1.7 * cm, 1.7 * cm], repeatRows=2)
    estilos = [("GRID", (0, 0), (-1, -1), 0.4, colors.grey), ("BACKGROUND", (0, 0), (-1, 1), GRIS),
               ("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("ALIGN", (0, 0), (-1, -1), "CENTER"), ("SPAN", (6, 0), (7, 0))]
    for c in range(6):
        estilos.append(("SPAN", (c, 0), (c, 1)))
    if not nc:
        estilos.append(("SPAN", (0, 2), (-1, 2)))
    th.setStyle(TableStyle(estilos))
    h += [_seccion("HALLAZGOS IDENTIFICADOS"), th, Spacer(1, 8)]

    # Evidencia fotográfica de equipos de medición
    med = []
    for it in items:
        r = res.get(it.id_item)
        if not it.requiere_foto_medicion or not r or r.resultado == "NO_APLICA":
            continue
        fotos_m = [f for f in insp.fotos if f.id_resultado == r.id_resultado and f.incluir_en_informe
                   and (visita == 2 or not es_foto_v2(f))]
        if r.resultado != "NO_CUMPLE" and fotos_m:  # las de No cumple ya salen en hallazgos
            med.append((it, r, fotos_m[0]))
    if med or insp.mediciones or insp.instrumentos:
        bloque = [_seccion("EVIDENCIA FOTOGRÁFICA EQUIPOS DE MEDICIÓN")]
        if med:
            celdas = [Table([[_p(f"<b>Ítem {it.numero}</b>" + (f" · {r.valor_medido} {r.unidad_medida or ''}" if r.valor_medido else ""), PC)],
                             [_imagen(f.ruta_miniatura or f.ruta_archivo, 5.8 * cm, 4 * cm)]], colWidths=[6.2 * cm])
                      for it, r, f in med]
            filas_m = [celdas[i:i + 3] for i in range(0, len(celdas), 3)]
            filas_m[-1] += [""] * (3 - len(filas_m[-1]))
            tm = Table(filas_m, colWidths=[6.3 * cm] * 3)
            tm.setStyle(TableStyle([("GRID", (0, 0), (-1, -1), 0.3, colors.grey), ("VALIGN", (0, 0), (-1, -1), "TOP")]))
            bloque.append(tm)
        for m in insp.mediciones:
            bloque.append(_p(f"<b>{m.concepto}:</b> {m.valor} {m.unidad or ''} {m.resultado or ''} {m.detalle or ''}"))
        instr = " · ".join(f"{i.instrumento.tipo.replace('_', ' ').title()} <b>{i.instrumento.codigo}</b>" for i in insp.instrumentos)
        bloque.append(_p(f"<b>Equipos utilizados en la inspección / código interno:</b> {instr or 'NI'}"))
        h += [PageBreak()] + bloque + [Spacer(1, 8)]

    # Firmas: primera visita | segunda visita (lado a lado, como en la plantilla)
    def bloque_firma(etiqueta, f=None, ruta=None, nombre=None):
        ruta = ruta if ruta is not None else (f.ruta_firma if f else None)
        nombre = nombre if nombre is not None else ((f.nombre + (f" - {f.cargo}" if f.cargo else "")) if f else "")
        t = Table([[_p(etiqueta, PB)], [_imagen(ruta, 5.5 * cm, 1.8 * cm) if ruta else _p("")], [_p(f"NOMBRE: {nombre}")]],
                  colWidths=[9.1 * cm], rowHeights=[None, 2 * cm, None])
        t.setStyle(TableStyle([("ALIGN", (0, 1), (0, 1), "CENTER")]))
        return t

    filas_f = [[_p("FIRMAS PARA LA PRIMERA VISITA", PB), _p("FIRMAS PARA LA SEGUNDA VISITA / CIERRE DE HALLAZGOS", PB)]]
    for tipo, etiqueta in (("TECNICO_MANTENIMIENTO", "FIRMA DEL TÉCNICO"),
                           ("REPRESENTANTE_EDIFICIO", "FIRMA DEL REPRESENTANTE DEL EDIFICIO"),
                           ("INSPECTOR", "FIRMA DEL INSPECTOR")):
        filas_f.append([bloque_firma(etiqueta, firmas.get((1, tipo))),
                        bloque_firma(etiqueta, firmas.get((2, tipo)) if visita == 2 else None)])
    firma_v1 = informe.ruta_firma_director_v1 or informe.ruta_firma_director
    filas_f.append([bloque_firma("RESPONSABLE DE REVISIÓN / ATESTACIÓN", ruta=firma_v1, nombre=director),
                    bloque_firma("RESPONSABLE DE REVISIÓN / ATESTACIÓN",
                                 ruta=informe.ruta_firma_director if visita == 2 else "", nombre=director if visita == 2 else "")])
    tf = Table(filas_f, colWidths=[9.5 * cm, 9.5 * cm])
    tf.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.5, colors.grey), ("INNERGRID", (0, 0), (-1, -1), 0.3, colors.grey),
                            ("BACKGROUND", (0, 0), (-1, 0), GRIS), ("VALIGN", (0, 0), (-1, -1), "TOP")]))
    h += [KeepTogether([_seccion("EMPRESA DE MANTENIMIENTO: " + (insp.empresa_mantenimiento or "NI")), tf]), Spacer(1, 8)]

    # Ítems que no aplican
    if na:
        filas_na = [[_p("ÍTEM", PB), _p("DEFECTO", PB), _p("Defe", PB), _p("Estado", PB), _p("OBSERVACIONES", PB)]]
        for it, r in na:
            filas_na.append([_p(it.numero, PC), _p(it.descripcion), _p(CALIF_CORTA[it.calificacion], PC), _p("N/A", PC),
                             _p('<font color="#C0392B"><b>NO APLICA</b></font>', PC)])
        tna = Table(filas_na, colWidths=[1.2 * cm, 10.3 * cm, 1.3 * cm, 1.6 * cm, 4.6 * cm], repeatRows=1)
        tna.setStyle(TableStyle([("GRID", (0, 0), (-1, -1), 0.3, colors.grey), ("BACKGROUND", (0, 0), (-1, 0), GRIS),
                                 ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]))
        h += [PageBreak(), _seccion(f"LISTA DE ÍTEMS QUE NO APLICAN ({len(na)})"), tna]

    # Anexo: resto del registro fotográfico
    usadas = set()
    for it, r in nc:
        fotos = fotos_por_res.get(r.id_resultado, [])
        v1 = [f for f in fotos if not es_foto_v2(f)][:1]
        v2 = [f for f in fotos if es_foto_v2(f)][:1] if visita == 2 else []
        usadas.update(f.id_foto for f in v1 + v2)
    usadas.update(f.id_foto for _, _, f in med)
    resto = [f for f in insp.fotos if f.incluir_en_informe and f.id_foto not in usadas and (visita == 2 or not es_foto_v2(f))]
    if resto:
        num_item = {r.id_resultado: r.item.numero for r in insp.resultados}
        celdas_f = []
        for f in resto:
            pie = f"Ítem {num_item[f.id_resultado]}. " if f.id_resultado in num_item else ""
            if es_foto_v2(f):
                pie = "<b>2ª visita</b> · " + pie
            celdas_f.append(Table([[_imagen(f.ruta_miniatura or f.ruta_archivo, 6 * cm, 6 * cm)],
                                   [_p(f"{pie}{f.descripcion or ''}", PC)]], colWidths=[6.2 * cm]))
        filas_x = [celdas_f[i:i + 3] for i in range(0, len(celdas_f), 3)]
        filas_x[-1] += [""] * (3 - len(filas_x[-1]))
        tfo = Table(filas_x, colWidths=[6.3 * cm] * 3)
        tfo.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                                 ("BOTTOMPADDING", (0, 0), (-1, -1), 8)]))
        h += [PageBreak(), _seccion(f"ANEXO: REGISTRO FOTOGRÁFICO ({len(resto)} fotos)"), Spacer(1, 4), tfo]

    pie = _pie(db, f"{informe.numero_informe}-{sufijo}", borrador)
    doc.build(h, onFirstPage=pie, onLaterPages=pie)
    return rel


# ============================================
# CERTIFICADO
# ============================================
def generar_certificado(db: Session, cert: Certificado) -> str:
    informe = cert.informe
    insp = informe.inspeccion
    snap = json.loads(insp.datos_equipo_json or "{}")
    cli, edi, eq = snap.get("cliente", {}), snap.get("edificio", {}), snap.get("equipo", {})
    variantes = {v.tipo.codigo: v.opcion.nombre for v in insp.variantes}
    empresa = parametro(db, "EMPRESA_NOMBRE", "ServiLift")

    rel = _destino("certificados", cert.numero_certificado)
    doc = SimpleDocTemplate(ruta_absoluta(rel), pagesize=letter, leftMargin=2 * cm, rightMargin=2 * cm,
                            topMargin=2 * cm, bottomMargin=2 * cm, title=cert.numero_certificado)
    grande = ParagraphStyle("g", parent=PT, fontSize=18, leading=22, alignment=TA_CENTER)
    centro = ParagraphStyle("c", parent=P, fontSize=11, leading=15, alignment=TA_CENTER)

    url = f"{settings.URL_VERIFICACION.rstrip('/')}/{cert.codigo_verificacion}"
    qr = QrCodeWidget(url)
    x1, y1, x2, y2 = qr.getBounds()
    dib = Drawing(4 * cm, 4 * cm, transform=[4 * cm / (x2 - x1), 0, 0, 4 * cm / (y2 - y1), 0, 0])
    dib.add(qr)

    h = [_p(empresa, ParagraphStyle("e", parent=PB, fontSize=14, alignment=TA_CENTER, textColor=AZUL)), Spacer(1, 16),
         _p("CERTIFICADO DE INSPECCIÓN", grande), _p("NTC 5926-1:2012", centro), Spacer(1, 10),
         _p(f"No. <b>{cert.numero_certificado}</b>", centro), Spacer(1, 18),
         _p(f"Se certifica que el equipo descrito a continuación fue inspeccionado conforme a la norma "
            f"NTC 5926-1:2012 y obtuvo concepto <b>{(informe.concepto or '').replace('_', ' ')}</b>, "
            f"según el informe <b>{informe.numero_informe}</b>.", centro), Spacer(1, 16),
         _grilla([
             ["Cliente", cli.get("razon_social"), "NIT / C.C.", f"{cli.get('tipo_documento', '')} {cli.get('numero_documento', '')}"],
             ["Edificio", edi.get("nombre"), "Dirección", f"{edi.get('direccion', '')}, {edi.get('ciudad', '')}"],
             ["Equipo", eq.get("identificacion"), "Serial", eq.get("numero_serie") or "NI"],
             ["Accionamiento", variantes.get("ACCIONAMIENTO", "NI"), "Capacidad", f"{insp.capacidad_kg or 'NI'} kg / {insp.capacidad_personas or 'NI'} personas"],
             ["Cotización", snap.get("numero_cotizacion"), "Fecha de inspección", _fecha(insp.fecha_inicio)],
             ["Fecha de emisión", _fecha(cert.fecha_emision), "Válido hasta", _fecha(cert.fecha_vencimiento)],
         ], [3 * cm, 5.5 * cm, 3 * cm, 5.5 * cm]),
         Spacer(1, 24)]
    firma = Table([[_imagen(informe.ruta_firma_director, 6 * cm, 2.5 * cm), dib],
                   [_p(f"{informe.director.nombre_completo if informe.director else ''}<br/>Director técnico", PC),
                    _p(f"Verifique este certificado:<br/>{url}", PC)]],
                  colWidths=[8.5 * cm, 8.5 * cm])
    firma.setStyle(TableStyle([("ALIGN", (0, 0), (-1, -1), "CENTER"), ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]))
    h.append(firma)
    doc.build(h, onFirstPage=_pie(db, cert.numero_certificado))
    return rel
