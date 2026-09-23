# Tiago Market Price Web

Sitio web separado para consultar los precios online publicados por Tiago Market y ver la opción más barata por producto.

## Desarrollo local

```bash
npm install
cp .env.example .env
# Completa VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY en .env
npm run dev
```

La clave debe ser la publishable/anon de Supabase. Nunca uses `service_role` en este proyecto.

## Publicar en Cloudflare Pages

```bash
npx wrangler login
npm run build
npx wrangler pages project create tiago-market-price-web
npx wrangler pages deploy dist --project-name tiago-market-price-web
```

Para que el build remoto tenga datos, configura las variables `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY` como variables de entorno de Pages, o construye localmente con `.env` y publica `dist`.

El sitio llama directamente al RPC público `online_prices_v2` de Supabase. El RPC ya limita los resultados a precios disponibles, recientes y con evidencia de tienda.