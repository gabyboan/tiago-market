# Criterio de publicación

El repositorio público contiene código fuente, tests, lockfiles, assets
necesarios, migraciones de esquema y documentación seleccionada. Los archivos
de ejemplo usan marcadores sin acceso real a servicios.

## Documentación seleccionada

`docs` usa una lista explícita de archivos permitidos en `.gitignore`:
índice, arquitectura, desarrollo, contrato HTTP y esta guía.
En `apps/flutter_app/docs` se publica únicamente el contrato técnico de envío
y pagos. Los README de cada componente describen su uso.

Los informes fechados, conversaciones, entregas de clientes, comprobantes,
capturas, respuestas HTML/JSON, dumps y archivos de evidencias permanecen
locales. Para publicar una nueva guía, revisarla y agregar una excepción
específica. Evitar `git add -f` para saltarse esta selección.

## Configuración privada

Se excluyen `.env`, configuración local de Dart, descargas OAuth, credenciales
de cuentas de servicio, claves de firma, configuración Firebase, archivos de
herramientas y editores, instaladores y exportaciones de bases de datos.
Los secretos de workflows se configuran en GitHub Actions; no se escriben en
YAML ni se incluyen en sus artefactos.

## Controles

`python3 scripts/check_publication.py` revisa archivos versionados y candidatos
nuevos: detecta archivos ignorados que Git siga siguiendo y archivos de más de
10 MiB. No reemplaza un detector de secretos.

El hook opcional de `pre-commit` escanea commits con Gitleaks. El workflow de
calidad revisa el historial completo disponible y los límites de publicación,
además de compilar y probar los componentes.

`.gitleaksignore` identifica cuatro falsos positivos históricos concretos:
el valor ficticio `chedraui-sucursal-123` en un test. Las excepciones se limitan
a esos commits y líneas; no desactivan la detección en los demás tests.

## Historial ya publicado

Excluir un archivo y quitarlo del índice evita incluirlo en commits nuevos;
el contenido de commits anteriores sigue disponible en el historial.
Los informes internos que ya estaban versionados se retiran del árbol público
actual, conservando sus copias locales.

Si alguna vez se detecta una credencial real publicada, primero revocarla o
rotarla en el proveedor. Reescribir el historial requiere una operación
coordinada aparte y no garantiza eliminar copias o forks.
