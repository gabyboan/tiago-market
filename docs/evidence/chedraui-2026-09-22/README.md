# Evidencia del preflight Chedraui

Resultado revisado: `blocked`. Ver el [informe](../../chedraui-validation-2026-09-22.md).

- `robots.txt`: cuerpo de la respuesta pública, sin transformación.
- `robots.metadata.json` / `terms.metadata.json`: URL, estado HTTP, fecha UTC,
  cabeceras seleccionadas y hash de las respuestas directas.
- `terms-review.json`: revisión manual y fragmentos breves de la sección de licencia.
  No se conserva el HTML completo de términos ni cookies/tokens.
- `summary.json`: resultado de este preflight manual; no es una salida del probe Dart.
- `local-baseline.json`: hashes de cinco archivos con cambios previos, sin su contenido
  ni configuraciones privadas de VS Code. Permite comprobar que quedaron intactos.
- `SHA256SUMS`: integridad de los archivos de este directorio, salvo el propio listado.
- `verification.json`: comprobaciones locales de integridad y del script con
  respuestas simuladas; no constituye una segunda captura del sitio.

Verificar sin red desde este directorio:

```bash
sha256sum --check SHA256SUMS
```

Reproducir las dos consultas pasivas desde la raíz del repositorio:

```bash
python3 docs/evidence/chedraui-2026-09-22/recheck_preflight.py \
  --out-dir /tmp/tiago-chedraui-preflight-nueva-revision
```

El directorio debe ser nuevo. El script se preparó después de las capturas
documentadas usando las mismas URLs y User-Agent; no se volvió a consultar el
sitio para probarlo. No sigue redirecciones ni reintenta; se detiene ante una
respuesta distinta de 200 o un error. El resultado requiere revisar manualmente
las condiciones actuales: no clasifica ni autoriza automáticamente una fuente.
Las fechas, hashes y reglas pueden cambiar en una revisión futura.

El probe Dart de sucursales queda condicionado a resolver el permiso de
reutilización. No ejecutar sus peticiones a producto/sesión como parte de esta
reproducción. No hay una segunda captura diaria pendiente: esa etapa dependía
de obtener evidencia local suficiente, condición que no se cumplió.
