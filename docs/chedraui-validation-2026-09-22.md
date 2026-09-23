# Validación de Chedraui por sucursal — 22/09/2026

## Resultado: `blocked`

El experimento terminó en el preflight. No se confirmó una fuente utilizable
para Tiago Market ni se habilitó Chedraui como integración local.

Se hicieron dos solicitudes directas, sin credenciales: `robots.txt` y los
términos de plataformas digitales. Ambas respondieron HTTP 200. La consulta
de términos mediante búsqueda web sirvió además para localizar y corroborar
la página oficial; no se incluye en el contador de esas dos capturas directas.

La sección **2.- DE LA LICENCIA** limita la copia a uso personal no comercial
y exige autorización escrita previa para otros usos. Fragmentos identificadores:
“exclusivamente para uso personal, no comercial” y “a menos que Chedraui le haya
otorgado su autorización previamente y por escrito”. El cliente confirmó que
no dispone de acceso o acuerdo autorizado. Por esa combinación se cerró el
experimento, conforme al alcance acordado. `robots.txt` no equivale a una
licencia de reutilización.

Fuente: [términos oficiales](https://www.chedraui.com.mx/terminos-y-condiciones/plataformas-digitales),
capturados a las 11:21:29 UTC. La página informa actualización del 12/05/2025.
La sección 6 también distingue precios online de precios en tiendas físicas:
seleccionar una sucursal de entrega no bastaría para demostrar precio de góndola.

## Evidencia y alcance ejecutado

| Paso | Resultado |
|---|---|
| GET `https://www.chedraui.com.mx/robots.txt` | HTTP 200, 11:20:39 UTC. Reglas guardadas; no hay prohibición explícita de las dos rutas previstas en el grupo general. |
| GET de términos de plataformas digitales | HTTP 200, 11:21:29 UTC. Metadatos y SHA-256 de la respuesta guardados; revisión de licencia bloqueante. |
| Ficha del SKU `3061483` | No solicitada durante este experimento. |
| POST `/api/sessions` | No ejecutado. |
| Buen Tono `chedraui-mx:013` y Ánfora `chedraui-mx:016` | Targets históricos previstos; sin observaciones nuevas ni revalidación actual de sus identificadores/domicilios. |
| Repetición al día siguiente / NDJSON | No corresponde: no se cumplió la dependencia de evidencia local suficiente. |
| Supabase / publicación | Cero escrituras, importaciones o cambios de clasificación. |

El [probe existente](../apps/flutter_app/tools/ingestion/bin/chedraui_branch_probe.dart)
no se ejecutó: su preflight revisa robots pero no la licencia, y podría continuar
a producto/sesión sin resolver esta condición. Se conserva sin modificar.
Su clasificación automática no debe confundirse con este veredicto de preflight
basado en la revisión de las condiciones. No se comprobó hoy si `/api/sessions` sigue devolviendo
429; ese resultado pertenece al [experimento de junio](../apps/flutter_app/docs/second-chain-evaluation.md).

Los [artefactos](evidence/chedraui-2026-09-22/) incluyen las reglas recibidas,
metadatos con fecha UTC, revisión de términos, resultado estructurado,
reproducción pasiva y checksums. No contienen claves ni cookies. No se conserva
el HTML completo de términos: su hash identifica la respuesta recibida, pero
el paquete permite verificar únicamente los fragmentos y la revisión guardados.

## Qué permitiría continuar

Obtener autorización escrita o un feed/API oficial que permita a Tiago Market
consultar y reutilizar SKU, presentación, precio MXN, disponibilidad, sucursal,
fecha y evidencia. Debe especificar frecuencia y canal del precio: tienda física
o compra online surtida desde una sucursal. No se contactó a Chedraui.

Una vez documentado ese acceso, revalidar los dos establecimientos y recién
entonces ejecutar el probe existente, manteniendo sus límites: una observación
por tienda, detenerse ante bloqueo, sin evasión. Si hay atribución local suficiente,
repetir al día siguiente y validar la muestra con `stage_ndjson --validate-only`,
sin publicación automática. Un precio igual en dos tiendas no debe alterarse
para forzar una comparación; el probe actual lo considera ambiguo si también
coincide la disponibilidad.

## Entrega y verificación

- Entregado: evidencia del acceso y restricciones, clasificación `blocked` y
  requisito concreto para retomar.
- Etapas de captura y repetición: no ejecutadas por dependencia incumplida;
  no se promete integración ni demostración con precios de supermercado.
- Estado del proyecto y deuda de entrega: [diagnóstico actualizado](estado-2026-09-22.md).
- Los cambios locales preexistentes se registraron por SHA-256 en
  `local-baseline.json`; esta entrega no los modifica ni aplica SQL.

Para verificar integridad sin red, desde la raíz del repositorio:

```bash
cd docs/evidence/chedraui-2026-09-22
sha256sum --check SHA256SUMS
```

Para una futura revisión pasiva, usar `recheck_preflight.py` como se indica en
el README de los artefactos. Solo descarga robots/términos y exige revisión
manual; no habilita la captura de productos.
