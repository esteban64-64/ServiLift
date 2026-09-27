"""Prueba de punta a punta del flujo ServiLift contra una base servilift_db recién creada
(01_schema.sql + 02_seed.sql). Crea sus propios usuarios y datos.

    python -m tests.test_flujo
"""
import base64
import io
import os
import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient
from PIL import Image

from app.database import SessionLocal
from app.main import app
from app.models import Rol, Usuario
from app.security import hash_password

c = TestClient(app)
SUF = uuid.uuid4().hex[:6]
CLAVE = "Prueba123*"


def ok(r, codigo=200):
    assert r.status_code == codigo, f"{r.request.method} {r.request.url} -> {r.status_code}: {r.text[:800]}"
    return r.json() if r.content and r.headers.get("content-type", "").startswith("application/json") else r


def crear_interno(rol: str) -> str:
    db = SessionLocal()
    correo = f"{rol.lower()}_{SUF}@servilift-prueba.co"
    db.add(Usuario(id_rol=db.query(Rol).filter(Rol.codigo == rol).one().id_rol, nombre_completo=f"{rol.title()} Prueba",
                   correo=correo, contrasena_hash=hash_password(CLAVE)))
    db.commit()
    db.close()
    return correo


def login(correo):
    t = ok(c.post("/auth/login", json={"correo": correo, "contrasena": CLAVE}))
    return {"Authorization": f"Bearer {t['access_token']}"}


def png(color="black"):
    img = Image.new("RGB", (300, 120), "white")
    for x in range(20, 280):
        img.putpixel((x, 60 + (x % 20) - 10), (0, 0, 0))
    b = io.BytesIO()
    img.save(b, "PNG")
    return base64.b64encode(b.getvalue()).decode()


def jpg():
    b = io.BytesIO()
    Image.new("RGB", (1600, 1200), (120, 140, 160)).save(b, "JPEG")
    return b.getvalue()


def main():
    H = {r: login(crear_interno(r)) for r in ("ADMIN", "ASESOR", "PROGRAMACION", "INSPECTOR", "DIRECTOR_TECNICO", "CERTIFICADOS")}
    yo_inspector = ok(c.get("/auth/me", headers=H["INSPECTOR"]))

    # 1. Asesor: cliente -> edificio con 3 ascensores -> equipos
    cli = ok(c.post("/clientes", headers=H["ASESOR"], json={"numero_documento": f"900{SUF}", "razon_social": f"Conjunto Prueba {SUF}"}), 201)
    edi = ok(c.post(f"/clientes/{cli['id_cliente']}/edificios", headers=H["ASESOR"],
                    json={"nombre": "Torre A", "direccion": "Cra 1 # 2-3", "ciudad": "Bogotá", "numero_equipos": 3,
                          "empresa_mantenimiento": "Mantenimientos XYZ"}), 201)
    equipos = ok(c.post(f"/edificios/{edi['id_edificio']}/equipos/generar", headers=H["ASESOR"]), 201)
    assert len(equipos) == 3
    ok(c.put(f"/equipos/{equipos[0]['id_equipo']}", headers=H["ASESOR"],
             json={"capacidad_kg": 630, "capacidad_personas": 8, "numero_paradas": 10, "numero_serie": "SN-1"}))
    # Solo el administrador crea usuarios
    assert c.post(f"/clientes/{cli['id_cliente']}/usuarios", headers=H["ASESOR"],
                  json={"nombre_completo": "x", "correo": f"x_{SUF}@servilift-prueba.co", "contrasena": CLAVE}).status_code == 403
    ok(c.post(f"/clientes/{cli['id_cliente']}/usuarios", headers=H["ADMIN"],
              json={"nombre_completo": "Administradora", "correo": f"cliente_{SUF}@servilift-prueba.co", "contrasena": CLAVE}), 201)
    H["CLIENTE"] = login(f"cliente_{SUF}@servilift-prueba.co")

    # 2. Cotización solo con 2 de los 3 equipos
    cot = ok(c.post("/cotizaciones", headers=H["ASESOR"], json={"id_edificio": edi["id_edificio"], "equipos": [
        {"id_equipo": equipos[0]["id_equipo"], "valor": 450000}, {"id_equipo": equipos[2]["id_equipo"], "valor": 450000}]}), 201)
    num = cot["numero_cotizacion"]
    assert num.startswith("COT-") and float(cot["total"]) == 1071000.0, cot
    assert ok(c.get("/cotizaciones", headers=H["CLIENTE"])) == []  # borrador invisible al cliente
    ok(c.post(f"/cotizaciones/{cot['id_cotizacion']}/enviar-cliente", headers=H["ASESOR"]))
    seg = ok(c.get("/seguimiento", headers=H["CLIENTE"], params={"numero_cotizacion": num}))
    assert {s["estado_equipo"] for s in seg} == {"PENDIENTE_APROBACION"}
    ok(c.post(f"/cotizaciones/{cot['id_cotizacion']}/responder", headers=H["CLIENTE"], json={"aprobada": True}))
    r = c.post(f"/cotizaciones/{cot['id_cotizacion']}/responder", headers=H["ASESOR"], json={"aprobada": True})
    assert r.status_code == 403
    ok(c.post(f"/cotizaciones/{cot['id_cotizacion']}/enviar-programacion", headers=H["ASESOR"]))

    # 3. Programación
    pend = ok(c.get("/programacion/pendientes", headers=H["PROGRAMACION"]))
    mia = next(p for p in pend if p["numero_cotizacion"] == num)
    ids_ce = [e["id_cotizacion_equipo"] for e in mia["equipos_por_programar"]]
    prog = ok(c.post("/programacion", headers=H["PROGRAMACION"], json={
        "id_cotizacion": cot["id_cotizacion"], "id_inspector": yo_inspector["id_usuario"],
        "fecha_programada": str(date.today() + timedelta(days=1)), "hora_inicio": "08:00", "ids_cotizacion_equipo": ids_ce}), 201)
    notifs = ok(c.get("/notificaciones", headers=H["INSPECTOR"]))
    assert any(num in n["titulo"] for n in notifs), notifs

    # 4. Inspector
    agenda = ok(c.get("/inspecciones/agenda", headers=H["INSPECTOR"]))
    assert any(a["id_programacion"] == prog["id_programacion"] for a in agenda)
    insp = ok(c.post("/inspecciones/iniciar", headers=H["INSPECTOR"], json={
        "id_programacion": prog["id_programacion"], "id_cotizacion_equipo": ids_ce[0], "uuid_offline": str(uuid.uuid4())}), 201)
    assert insp["datos_equipo"]["edificio"]["nombre"] == "Torre A" and insp["capacidad_kg"] == 630
    assert insp["empresa_mantenimiento"] == "Mantenimientos XYZ"
    iid = insp["id_inspeccion"]
    # El inspector completa los datos del ascensor verificados en sitio
    eqd = ok(c.put(f"/inspecciones/{iid}/equipo", headers=H["INSPECTOR"],
                   json={"marca": "Marca X", "numero_serie": "SER-99", "capacidad_kg": 800, "velocidad_ms": 1.5}))
    assert eqd["datos_equipo"]["equipo"]["numero_serie"] == "SER-99" and eqd["capacidad_kg"] == 800, eqd
    assert c.put(f"/inspecciones/{iid}/equipo", headers=H["ASESOR"], json={"marca": "Y"}).status_code == 403

    cat = ok(c.get("/catalogos/variantes", headers=H["INSPECTOR"]))
    elegir = {"ACCIONAMIENTO": "ELECTRICO", "ENHEBRADO": "1_1", "MAQUINA": "GEARLESS", "TRACCION_POR": "CABLE",
              "CUARTO_MAQUINAS": "CON_CUARTO", "TIPO_BUFFER": "RESORTE_CAUCHO", "LIMITADOR_CABINA": "SI",
              "LIMITADOR_CONTRAPESO": "NO", "CUARTO_POLEAS": "NO", "PUERTA_SOCORRO": "NO", "TIPO_PUERTA": "BATIENTE",
              "MIRILLA_PUERTAS": "NO"}
    sel = [{"id_variante_tipo": t["id_variante_tipo"],
            "id_variante_opcion": next(o["id_variante_opcion"] for o in t["opciones"] if o["codigo"] == elegir[t["codigo"]])}
           for t in cat]
    d = ok(c.put(f"/inspecciones/{iid}/variantes", headers=H["INSPECTOR"], json=sel))
    assert d["resumen"]["no_aplica"] == 23, d["resumen"]

    val = ok(c.get(f"/inspecciones/{iid}/validar", headers=H["INSPECTOR"]))
    assert not val["puede_finalizar"]
    r = c.post(f"/inspecciones/{iid}/finalizar", headers=H["INSPECTOR"])
    assert r.status_code == 422

    chk = ok(c.get(f"/inspecciones/{iid}/checklist", headers=H["INSPECTOR"]))
    items = [it for cg in chk["categorias"] for it in cg["items"]]
    assert len(items) == 169
    lote = []
    for it in items:
        if it["resultado"]:  # precargado NA
            continue
        res = "NO_CUMPLE" if it["numero"] in (28, 38, 71) else "CUMPLE"
        lote.append({"id_item": it["id_item"], "resultado": res, "observacion": "Hallazgo de prueba" if res == "NO_CUMPLE" else None,
                     "valor_medido": "12" if it["requiere_medicion"] else None, "unidad_medida": "mm" if it["requiere_medicion"] else None})
    ok(c.put(f"/inspecciones/{iid}/resultados", headers=H["INSPECTOR"], json=lote))

    fotos = ok(c.post(f"/inspecciones/{iid}/fotos", headers=H["INSPECTOR"],
                      files=[("archivos", (f"f{i}.jpg", jpg(), "image/jpeg")) for i in range(5)],
                      data={"descripcion": "Cuarto de máquinas"}), 201)
    assert len(fotos) == 5
    ok(c.post(f"/inspecciones/{iid}/fotos", headers=H["INSPECTOR"], files=[("archivos", ("h.jpg", jpg(), "image/jpeg"))],
              data={"id_item": str(next(i["id_item"] for i in items if i["numero"] == 28)), "descripcion": "Guardaescoba"}), 201)
    assert c.get(fotos[0]["url_miniatura"]).status_code == 200
    # Sin foto de evidencia en los ítems 38 y 71 (No cumple) no se puede finalizar
    assert any("sin foto de evidencia" in p for p in ok(c.get(f"/inspecciones/{iid}/validar", headers=H["INSPECTOR"]))["pendientes"])
    for n in (38, 71):
        ok(c.post(f"/inspecciones/{iid}/fotos", headers=H["INSPECTOR"], files=[("archivos", (f"nc{n}.jpg", jpg(), "image/jpeg"))],
                  data={"id_item": str(next(i["id_item"] for i in items if i["numero"] == n)), "descripcion": f"Evidencia ítem {n}"}), 201)

    ok(c.put(f"/inspecciones/{iid}/mediciones", headers=H["INSPECTOR"],
             json=[{"concepto": "DESLIZAMIENTO", "valor": 0.33, "resultado": "CUMPLE", "detalle": "Enhebrado 1:1, recorrido 15"}]))
    for tipo, nombre in (("INSPECTOR", "Inspector Prueba"), ("TECNICO_MANTENIMIENTO", "Técnico XYZ"),
                         ("REPRESENTANTE_EDIFICIO", "Administradora")):
        ok(c.post(f"/inspecciones/{iid}/firmas", headers=H["INSPECTOR"],
                  json={"tipo_firmante": tipo, "nombre": nombre, "firma_base64": png()}), 201)
    fin = ok(c.post(f"/inspecciones/{iid}/finalizar", headers=H["INSPECTOR"]))
    assert fin["estado"] == "FINALIZADA" and fin["informe"]["estado"] == "PENDIENTE_REVISION"

    # 5. Director técnico: devuelve, el inspector corrige, aprueba
    inf = fin["informe"]
    ok(c.post(f"/informes/{inf['id_informe']}/devolver", headers=H["DIRECTOR_TECNICO"], json={"observaciones": "Falta foto del foso"}))
    assert ok(c.get(f"/inspecciones/{iid}", headers=H["INSPECTOR"]))["estado"] == "DEVUELTA"
    ag = ok(c.get("/inspecciones/agenda", headers=H["INSPECTOR"]))
    assert any(e["inspeccion"] and e["inspeccion"]["estado"] == "DEVUELTA" for a in ag for e in a["equipos"]), ag
    ok(c.post(f"/inspecciones/{iid}/fotos", headers=H["INSPECTOR"], files=[("archivos", ("foso.jpg", jpg(), "image/jpeg"))]), 201)
    ok(c.post(f"/inspecciones/{iid}/finalizar", headers=H["INSPECTOR"]))
    assert c.get(f"/informes/{inf['id_informe']}", headers=H["CLIENTE"]).status_code == 404  # aún no visible
    # Vista previa (borrador) antes de decidir: no cambia el informe
    vp = ok(c.get(f"/informes/{inf['id_informe']}/vista-previa", headers=H["DIRECTOR_TECNICO"]))
    assert c.get(vp["url"]).content[:4] == b"%PDF"
    assert ok(c.get(f"/informes/{inf['id_informe']}", headers=H["DIRECTOR_TECNICO"]))["estado"] == "PENDIENTE_REVISION"
    assert c.get(f"/informes/{inf['id_informe']}/vista-previa", headers=H["CLIENTE"]).status_code == 403
    apr = ok(c.post(f"/informes/{inf['id_informe']}/aprobar", headers=H["DIRECTOR_TECNICO"], json={"firma_base64": png()}))
    assert apr["estado"] == "APROBADO" and apr["concepto"] == "NO_CONFORME", apr
    assert (apr["total_leves"], apr["total_graves"], apr["total_muy_graves"], apr["total_no_aplica"]) == (1, 1, 1, 23), apr
    pdf_v1 = ok(c.get(f"/informes/{inf['id_informe']}/pdf", headers=H["CLIENTE"]))
    assert pdf_v1.content[:4] == b"%PDF"

    # 5b. No conforme: el certificado queda bloqueado hasta la segunda visita
    seg = ok(c.get("/seguimiento", headers=H["CLIENTE"], params={"numero_cotizacion": num}))
    assert "NO_CONFORME" in {s["estado_equipo"] for s in seg}
    assert not any(p["id_informe"] == inf["id_informe"] for p in ok(c.get("/certificados/pendientes", headers=H["CERTIFICADOS"])))
    assert c.post("/certificados", headers=H["CERTIFICADOS"], json={"id_informe": inf["id_informe"]}).status_code == 409

    # Plazo: el hallazgo más exigente (MG = corrección inmediata, 0 días) manda; el cliente solicita la 2ª visita
    fila_nc = next(s for s in seg if s["estado_equipo"] == "NO_CONFORME")
    assert fila_nc["plazo_dias"] == 0 and fila_nc["dias_restantes"] == 0, fila_nc
    assert fila_nc["hora_inicio"] == "08:00:00", fila_nc["hora_inicio"]
    assert not any(p["numero_cotizacion"] == num and p["equipos_segunda_visita"]
                   for p in ok(c.get("/programacion/pendientes", headers=H["PROGRAMACION"])))
    assert c.post(f"/seguimiento/equipo/{ids_ce[0]}/solicitar-segunda-visita", headers=H["PROGRAMACION"], json={}).status_code == 403
    ok(c.post(f"/seguimiento/equipo/{ids_ce[0]}/solicitar-segunda-visita", headers=H["CLIENTE"],
              json={"comentario": "Ya se corrigieron los hallazgos"}))
    pend = ok(c.get("/programacion/pendientes", headers=H["PROGRAMACION"]))
    mia = next(p for p in pend if p["numero_cotizacion"] == num)
    assert [e["id_cotizacion_equipo"] for e in mia["equipos_segunda_visita"]] == [ids_ce[0]]
    assert mia["equipos_segunda_visita"][0]["dias_restantes"] == 0
    prog2 = ok(c.post("/programacion", headers=H["PROGRAMACION"], json={
        "id_cotizacion": cot["id_cotizacion"], "id_inspector": yo_inspector["id_usuario"], "tipo_visita": "SEGUNDA",
        "fecha_programada": str(date.today() + timedelta(days=30)), "hora_inicio": "09:00",
        "ids_cotizacion_equipo": [ids_ce[0]]}), 201)
    v2 = ok(c.post("/inspecciones/iniciar", headers=H["INSPECTOR"], json={
        "id_programacion": prog2["id_programacion"], "id_cotizacion_equipo": ids_ce[0]}), 201)
    assert v2["id_inspeccion"] == iid and v2["estado"] == "EN_SEGUNDA_VISITA", v2
    assert c.put(f"/inspecciones/{iid}/resultados", headers=H["INSPECTOR"], json=lote[:1]).status_code == 409
    assert c.post(f"/inspecciones/{iid}/finalizar", headers=H["INSPECTOR"]).status_code == 422
    hallazgos = [i["id_item"] for i in items if i["numero"] in (28, 38, 71)]
    ok(c.put(f"/inspecciones/{iid}/segunda-visita", headers=H["INSPECTOR"],
             json=[{"id_item": x, "estado_segunda_visita": "CORREGIDO", "observacion_segunda_visita": "Corregido por mantenimiento"}
                   for x in hallazgos]))
    ok(c.post(f"/inspecciones/{iid}/fotos", headers=H["INSPECTOR"], files=[("archivos", ("cierre.jpg", jpg(), "image/jpeg"))],
              data={"descripcion": "Cierre de hallazgos"}), 201)
    for tipo, nombre in (("INSPECTOR", "Inspector Prueba"), ("TECNICO_MANTENIMIENTO", "Técnico XYZ"),
                         ("REPRESENTANTE_EDIFICIO", "Administradora")):
        ok(c.post(f"/inspecciones/{iid}/firmas", headers=H["INSPECTOR"],
                  json={"tipo_firmante": tipo, "nombre": nombre, "firma_base64": png(), "numero_visita": 2}), 201)
    fin2 = ok(c.post(f"/inspecciones/{iid}/finalizar", headers=H["INSPECTOR"]))
    assert fin2["informe"]["estado"] == "PENDIENTE_REVISION" and fin2["informe"]["visita_actual"] == 2
    apr = ok(c.post(f"/informes/{inf['id_informe']}/aprobar", headers=H["DIRECTOR_TECNICO"], json={"firma_base64": png()}))
    assert apr["concepto"] == "CONFORME" and apr["concepto_visita1"] == "NO_CONFORME" and apr["total_corregidos"] == 3, apr
    pdf_inf = ok(c.get(f"/informes/{inf['id_informe']}/pdf", headers=H["CLIENTE"]))

    # 6. Certificados
    pend_c = ok(c.get("/certificados/pendientes", headers=H["CERTIFICADOS"]))
    assert any(p["id_informe"] == inf["id_informe"] for p in pend_c)
    cert = ok(c.post("/certificados", headers=H["CERTIFICADOS"], json={"id_informe": inf["id_informe"]}), 201)
    assert c.get(f"/certificados/{cert['id_certificado']}/pdf", headers=H["CLIENTE"]).status_code == 404  # aún no enviado
    ok(c.post(f"/certificados/{cert['id_certificado']}/enviar", headers=H["CERTIFICADOS"]))
    pdf_cer = ok(c.get(f"/certificados/{cert['id_certificado']}/pdf", headers=H["CLIENTE"]))
    assert pdf_cer.content[:4] == b"%PDF"
    ver = ok(c.get(f"/verificar/{cert['codigo_verificacion']}"))
    assert ver["estado"] == "VIGENTE"

    # 7. Portal del cliente: estado por equipo
    seg = ok(c.get("/seguimiento", headers=H["CLIENTE"], params={"numero_cotizacion": num}))
    estados = {s["codigo_servicio"]: s["estado_equipo"] for s in seg}
    assert sorted(estados.values()) == ["CERTIFICADO_LISTO", "PROGRAMADO"], estados
    listo = next(s for s in seg if s["estado_equipo"] == "CERTIFICADO_LISTO")
    assert listo["pdf_informe"] and listo["pdf_certificado"]
    for rol in ("ASESOR", "PROGRAMACION", "INSPECTOR", "DIRECTOR_TECNICO", "CERTIFICADOS"):
        hr = ok(c.get(f"/seguimiento/equipo/{ids_ce[0]}/historial", headers=H[rol]))
        assert any("Certificado" in (e["estado_etiqueta"] or "") for e in hr["historial"]), (rol, hr)
    assert len(ok(c.get("/seguimiento", headers=H["INSPECTOR"]))) >= 1
    hist = ok(c.get(f"/seguimiento/equipo/{ids_ce[0]}/historial", headers=H["CLIENTE"]))
    print("Historial:", " -> ".join(h["estado_etiqueta"] for h in hist["historial"]))

    # Página de inicio de cada rol
    for rol, hh in H.items():
        dsh = ok(c.get("/dashboard", headers=hh))
        assert dsh["kpis"] and dsh["graficas"] is not None, (rol, dsh)
    # Informe de 1ª visita y de 2ª visita por separado (el cliente ve ambos)
    u1 = ok(c.get(f"/informes/{inf['id_informe']}/enlace-pdf", headers=H["CLIENTE"], params={"visita": 1}))["url"]
    u2 = ok(c.get(f"/informes/{inf['id_informe']}/enlace-pdf", headers=H["CLIENTE"], params={"visita": 2}))["url"]
    assert u1 != u2, (u1, u2)
    pdf_v1b, pdf_v2 = c.get(u1).content, c.get(u2).content
    assert pdf_v1b[:4] == b"%PDF" and pdf_v2[:4] == b"%PDF"
    os.makedirs("tests/salida", exist_ok=True)
    open("tests/salida/informe_1V.pdf", "wb").write(pdf_v1b)
    open("tests/salida/informe_2V.pdf", "wb").write(pdf_v2)
    open("tests/salida/informe_prueba.pdf", "wb").write(pdf_inf.content)
    open("tests/salida/certificado_prueba.pdf", "wb").write(pdf_cer.content)
    print(f"OK flujo completo {num}: informe {apr['numero_informe']}, certificado {cert['numero_certificado']}")


if __name__ == "__main__":
    main()
