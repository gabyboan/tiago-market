# Tiago Market Flutter

Demo mínima del cliente Flutter. Incluye:

- búsqueda de productos;
- accesos rápidos;
- comparación ordenada por precio;
- cadena, sucursal, fuente y fecha de observación;
- datos demo cuando no se configura una API pública.

## Ejecutar demo

```bash
flutter pub get
flutter run -d chrome
```

## Conectar API

```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=https://api.example.com
```

La URL no debe terminar en `/`. Flutter consultará
`/api/v1/compare?query=...`.

La aplicación nunca debe incluir claves de Supabase ni ejecutar scraping.
