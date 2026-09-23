# SQL recuperado el 18 de septiembre de 2026

> **Actualización 22/09/2026:** el remoto ahora registra 25 migraciones, incluidas `20260921121843` y `20260921122029`; las RPC v2 ya existen. Los conteos siguientes corresponden al rescate del 18/09. Ver [diagnóstico actual](../../../docs/estado-2026-09-22.md). Los SQL recuperados y sus checksums se conservan intactos.

Archivo histórico para revisión; **no es una secuencia de migraciones lista para ejecutar**.
No se aplicó SQL a Supabase durante la consolidación.

- `flutter-copy/`: 25 archivos de la antigua copia Flutter independiente.
- `local-main-root/`: 11 migraciones recuperadas de la rama local `main`, commit `1a32640`.
- Los archivos `001` a `014` de `flutter-copy/` son marcadores de historial, no contienen el DDL original. Para `001` a `011` se recuperó SQL en `local-main-root/`; no asumir que coincide exactamente con producción.
- `20260618195729_remote_schema.sql` es una captura histórica del esquema, no una migración incremental para aplicar a ciegas.
- Hay definiciones solapadas entre ambas carpetas. No concatenar ni ejecutar todo el archivo histórico.
- La migración de contrato v2 continúa en `apps/flutter_app/supabase/migrations/20260628055206_harden_public_price_contract.sql`.
- El reporte recuperado está en `apps/flutter_app/tools/ingestion/sql/source_coverage_report.sql`.

Antes del próximo despliegue: comparar esquema e historial remotos, reconstruir una secuencia coherente en un entorno de prueba y verificar dependencias, permisos y datos. No usar `migration repair` para marcar SQL como aplicado sin comprobarlo.

El historial remoto consultado el 18/09/2026 registra 23 migraciones, hasta `20260619022000`. No registra las versiones `20260620000000`, `20260624000000` ni `20260628055206`; podrían existir cambios manuales equivalentes, que esta consulta de historial no descarta.

Los archivos conservan sus bytes originales. `SHA256SUMS` permite comprobarlos desde esta carpeta con `sha256sum -c SHA256SUMS`.
