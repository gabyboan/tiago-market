# Desarrollo local

## Requisitos

- Node.js 20 o superior y npm.
- Flutter 3.41.7, versión fijada en CI, con Dart incluido.
- Python 3 para herramientas de ingesta y release.
- Un proyecto propio de Supabase para autenticación y consultas reales.

Instalar las dependencias con los lockfiles del repositorio. No copiar
credenciales de producción a fixtures, documentación o código.

## Backend Node

Desde la raíz:

```bash
npm ci
cp .env.example .env
npm run api
```

Completar `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` y `GOOGLE_CLIENT_ID` en
`.env`. La clave `service_role` se usa exclusivamente en el servidor. Los
valores de ejemplo no dan acceso a un servicio real.

```bash
npm run lint
npm run build
npm test
curl http://localhost:3000/api/v1/health
```

Los jobs `scrape:*` e `import:*` escriben datos. Revisar su configuración y la
fuente antes de ejecutarlos sobre una base remota. La geocodificación usa
`dry_run` por defecto; el modo real requiere un token autorizado.

## Flutter

```bash
cd apps/flutter_app
flutter pub get
cp config/dart_defines.example.json dart_defines.local.json
flutter run -d chrome --dart-define-from-file=dart_defines.local.json
```

Completar la URL y la clave pública de Supabase. `API_BASE_URL` apunta al
servicio auxiliar HTTP; la API Node y la Edge Function histórica no tienen
contratos idénticos. Google requiere además un proveedor configurado y URLs
de callback autorizadas. Ver [la guía Flutter](../apps/flutter_app/README.md).

Sin backend configurado se puede revisar la interfaz, pero las consultas de
precios y el inicio de sesión no tienen servicio real.

```bash
flutter analyze
flutter test
python3 -m unittest discover -s tools -p 'test_release_config.py'
python3 -m unittest discover -s tools/ingestion/python -p 'test_*.py'
```

## Web de precios

Desde `apps/price_web`:

```bash
npm ci
cp .env.example .env
# Completar VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY.
npm run dev
```

```bash
npm run typecheck
npm run build
```

Las variables `VITE_*` se incluyen en el JavaScript público. Usar únicamente
una clave pública; jamás `service_role`, contraseñas ni tokens privados.

## Demo sin servicios

La [demo pública](https://gabyboan.github.io/tiago-market/) usa el cliente
Flutter con ocho productos y dos comercios ficticios. No necesita Supabase,
OAuth ni una base de datos para explorar búsqueda, comparación y listas.

```bash
cd apps/flutter_app
flutter pub get
python3 tools/build_portfolio_demo.py --base-href=/
python3 -m http.server 8080 --directory build/portfolio-demo
```

Abrir `http://localhost:8080`. Para GitHub Pages, el script usa por defecto
`--base-href=/tiago-market/`; el workflow `portfolio-demo.yml` realiza la
publicación al actualizar el cliente en `main`.

Los datos ficticios viven en `lib/src/demo/demo_market_api.dart`, separados del
cliente de producción. La entrada `main_demo.dart` rechaza configuración de
servicios; no pasar archivos de Dart defines al construir la demo.

## Base de datos

Las migraciones están repartidas entre archivos históricos recuperados y
migraciones posteriores de Flutter. Hace falta reconciliar esa secuencia antes
de automatizar una instalación desde cero. No ejecutar todos los SQL
recuperados ni aplicar `supabase db push` sin revisar el historial de destino.

Los tests SQL bajo `apps/flutter_app/supabase/tests` son contratos para una
base aislada y descartable. No ejecutarlos en producción.

El refresco programado ejecuta mantenimiento antes de publicar: conserva 90 días
de cambios de precio/disponibilidad y siempre la última observación de cada
producto/sucursal/alcance. Dentro de un tramo sin cambios se mantienen la primera
y la última observación. Moneda, fuente, identidad, revisión, origen sintético
y vigencia también forman parte del estado: sus cambios se conservan.
Las repeticiones intermedias y los registros antiguos se guardan completos en el bucket **privado**
`catalog-private-archives`, como NDJSON comprimido y un manifiesto con SHA-256.
Se descargan y verifican ambos archivos antes de retirar las filas originales;
si cambia una fila, sus vecinos o falla la verificación, la limpieza se detiene.
Antes de retirar cada repetición se comprueba de nuevo que sus vecinos inmediatos
tengan el mismo estado. Las capturas intermedias siguen disponibles en los
archivos privados, junto con el texto JSON exacto de PostgreSQL para recuperar
valores numéricos sin pérdida de precisión. Los registros
pendientes de revisión y las copias de preparación que difieren del historial
se conservan. Las copias idénticas de preparación se eliminan tras publicarse.

El job necesita `SUPABASE_DB_URL`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` y
`SUPABASE_SERVICE_ROLE_KEY` en el runner. La clave de servicio permanece privada.
El límite preventivo es 400 MiB de base y 700 MiB de archivos: si se alcanza,
se detienen nuevas cargas para revisar capacidad. Una retención de 90 días no
garantiza entrar en el plan gratuito para cualquier volumen de cambios reales.
Los archivos privados se conservan hasta que se decida trasladarlos o retirarlos;
no se publican respaldos ni respuestas de comercios como artifacts de Actions.
Para ejecutar sólo mantenimiento y las comprobaciones públicas, usar la opción
`maintenance_only` del workflow manual. Las ejecuciones programadas mantienen
la captura habitual.

Para recuperar observaciones, descargar el `.ndjson.gz` y su `.manifest.json`
desde el bucket privado y ejecutar primero una prueba con rollback:

```bash
python3 apps/flutter_app/tools/ingestion/python/restore_catalog_archive.py \
  --archive /ruta/archivo.ndjson.gz --manifest /ruta/archivo.manifest.json \
  --work-dir /ruta/privada/restauracion
```

Agregar `--apply` únicamente para confirmar la restauración. El comando valida
checksum y cantidad de filas; los conflictos existentes se conservan.

## Antes de un commit

```bash
python3 scripts/check_publication.py
```

Para activar la detección local de secretos, instalar `pre-commit` y ejecutar
`pre-commit install`. El hook usa Gitleaks; CI también revisa el historial.
El [criterio de publicación](github-publication.md) detalla qué archivos se
incluyen y qué información debe permanecer local.
