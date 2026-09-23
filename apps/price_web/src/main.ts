import './style.css';

type PriceRow = {
  product_name: string;
  normalized_name?: string;
  category?: string;
  store_name: string;
  store_slug?: string;
  price: number;
  currency?: string;
  available?: boolean;
  source?: string;
  captured_at?: string;
  freshness?: string;
  days_old?: number;
  store_product_url?: string;
  observation_url?: string;
  image_url?: string;
  presentation?: string;
};

type ProductGroup = {
  name: string;
  category: string;
  prices: PriceRow[];
  best: PriceRow;
};

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.replace(/\/$/, '') ?? '';
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? '';
const pageSize = 100;
let currentPage = 1;
let currentQuery = '';
let currentRows: PriceRow[] = [];
let hasMore = true;

const app = document.querySelector<HTMLDivElement>('#app')!;

app.innerHTML = `
  <main class="shell">
    <header class="topbar">
      <a class="brand" href="/" aria-label="Tiago Market inicio">
        <img class="brand-logo" src="/tiago-market-navbar.svg" alt="" />
        <span>Tiago Market</span>
      </a>
      <span class="status-pill"><i></i> precios observados</span>
    </header>

    <section class="hero">
      <div class="hero-copy">
        <p class="eyebrow">Compra con criterio</p>
        <h1>El precio justo<br /><em>se encuentra.</em></h1>
        <p class="intro">Busca un producto y descubre en qué tienda conviene comprarlo hoy.</p>
      </div>
      <div class="hero-note"><span>↓</span><p>Comparación<br />en tiempo real</p></div>
    </section>

    <section class="search-panel" aria-label="Buscar productos">
      <form id="search-form">
        <label class="search-box">
          <span aria-hidden="true">⌕</span>
          <input id="search-input" type="search" placeholder="¿Qué estás buscando? Ej. leche, jabón, café..." autocomplete="off" />
          <button type="submit">Buscar</button>
        </label>
      </form>
      <div class="toolbar">
        <div id="result-summary">Todos los productos</div>
        <label class="sort-control">Ordenar por
          <select id="sort-select">
            <option value="best">Mejor precio</option>
            <option value="stores">Más tiendas</option>
            <option value="name">Nombre</option>
          </select>
        </label>
      </div>
    </section>

    <section id="feedback" class="feedback" role="status"></section>
    <section id="product-grid" class="product-grid" aria-live="polite"></section>
    <button id="load-more" class="load-more" type="button">Cargar más productos</button>

    <footer><span>TIAGO MARKET</span></footer>
  </main>
`;

const form = document.querySelector<HTMLFormElement>('#search-form')!;
const input = document.querySelector<HTMLInputElement>('#search-input')!;
const sort = document.querySelector<HTMLSelectElement>('#sort-select')!;
const grid = document.querySelector<HTMLElement>('#product-grid')!;
const feedback = document.querySelector<HTMLElement>('#feedback')!;
const summary = document.querySelector<HTMLElement>('#result-summary')!;
const loadMore = document.querySelector<HTMLButtonElement>('#load-more')!;

form.addEventListener('submit', (event) => {
  event.preventDefault();
  currentQuery = input.value.trim();
  currentPage = 1;
  currentRows = [];
  hasMore = true;
  void loadProducts(false);
});

sort.addEventListener('change', () => renderProducts());
loadMore.addEventListener('click', () => void loadProducts(true));

async function loadProducts(append: boolean): Promise<void> {
  setLoading(true);
  showFeedback('');
  try {
    const rows = await fetchPrices(currentQuery, currentPage);
    currentRows = append ? [...currentRows, ...rows] : rows;
    hasMore = rows.length === pageSize;
    renderProducts();
    if (hasMore) currentPage += 1;
  } catch (error) {
    showFeedback(error instanceof Error ? error.message : 'No pudimos cargar los precios.');
    if (!currentRows.length) renderEmpty('No hay productos para mostrar.');
  } finally {
    setLoading(false);
  }
}

async function fetchPrices(query: string, page: number): Promise<PriceRow[]> {
  if (!supabaseUrl || !supabaseKey) {
    throw new Error('Configura VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY para conectar los precios.');
  }
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/online_prices_v2`, {
    method: 'POST',
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      search_query: query,
      limit_count: pageSize,
      page_number: page,
      category_filter: null,
      only_available: true,
    }),
  });
  if (!response.ok) throw new Error(`Supabase respondió ${response.status}. Revisa la URL y la clave pública.`);
  return (await response.json()) as PriceRow[];
}

function groupProducts(rows: PriceRow[]): ProductGroup[] {
  const groups = new Map<string, ProductGroup>();
  for (const row of rows) {
    const key = (row.normalized_name || row.product_name).trim().toLowerCase();
    const group = groups.get(key) ?? { name: row.product_name, category: row.category || 'Otros', prices: [], best: row };
    group.prices.push(row);
    if (row.price < group.best.price) group.best = row;
    groups.set(key, group);
  }
  return [...groups.values()].sort((a, b) => {
    if (sort.value === 'name') return a.name.localeCompare(b.name);
    if (sort.value === 'stores') return b.prices.length - a.prices.length || a.best.price - b.best.price;
    return a.best.price - b.best.price;
  });
}

function renderProducts(): void {
  const products = groupProducts(currentRows);
  summary.textContent = currentQuery ? `${products.length} productos para “${currentQuery}”` : `${products.length} productos disponibles`;
  if (!products.length) {
    renderEmpty(currentQuery ? 'No encontramos ese producto todavía.' : 'No hay precios publicados todavía.');
    return;
  }
  grid.innerHTML = products.map(renderProduct).join('');
  loadMore.hidden = !hasMore;
}

function renderProduct(product: ProductGroup): string {
  const initial = product.name.trim().charAt(0).toUpperCase() || 'T';
  const imageUrl = product.best.image_url?.trim() || '';
  const image = imageUrl
    ? `<img src="${escapeHtml(imageUrl)}" alt="${escapeHtml(product.name)}" loading="lazy" referrerpolicy="no-referrer" onerror="this.hidden=true; this.nextElementSibling.hidden=false;" />`
    : '';
  const fallback = `<span class="image-placeholder" ${imageUrl ? 'hidden' : ''}>${escapeHtml(initial)}</span>`;
  const prices = [...product.prices].sort((a, b) => a.price - b.price).slice(0, 4);
  return `<article class="product-card">
    <div class="product-image">${image}${fallback}<span class="category">${escapeHtml(product.category)}</span></div>
    <div class="product-body">
      <p class="product-category">${escapeHtml(product.category)}</p>
      <h2>${escapeHtml(product.name)}</h2>
      ${product.best.presentation ? `<p class="presentation">${escapeHtml(product.best.presentation)}</p>` : ''}
      <div class="best-price"><span>Mejor precio</span><strong>${formatPrice(product.best.price, product.best.currency)}</strong></div>
      <p class="best-store">en <b>${escapeHtml(product.best.store_name)}</b></p>
      <div class="price-list">${prices.map(renderPrice).join('')}</div>
      <p class="store-count">${product.prices.length} ${product.prices.length === 1 ? 'opción disponible' : 'opciones disponibles'}</p>
    </div>
  </article>`;
}

function renderPrice(row: PriceRow): string {
  const link = row.store_product_url || row.observation_url;
  const store = link ? `<a href="${escapeHtml(link)}" target="_blank" rel="noreferrer">${escapeHtml(row.store_name)} ↗</a>` : escapeHtml(row.store_name);
  return `<div class="price-row"><span>${store}</span><b>${formatPrice(row.price, row.currency)}</b></div>`;
}

function renderEmpty(message: string): void {
  grid.innerHTML = `<div class="empty-state"><span>◌</span><h2>${escapeHtml(message)}</h2><p>Prueba con otra búsqueda o vuelve a intentarlo más tarde.</p></div>`;
  loadMore.hidden = true;
}

function formatPrice(value: number, currency = 'MXN'): string {
  return new Intl.NumberFormat('es-MX', { style: 'currency', currency, maximumFractionDigits: 2 }).format(value);
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character] ?? character);
}

function setLoading(loading: boolean): void {
  loadMore.disabled = loading;
  if (loading) {
    loadMore.hidden = false;
    loadMore.textContent = 'Cargando precios...';
  } else {
    loadMore.textContent = 'Cargar más productos';
  }
}

function showFeedback(message: string): void {
  feedback.textContent = message;
  feedback.hidden = !message;
}

void loadProducts(false);