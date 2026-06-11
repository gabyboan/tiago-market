import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import test from "node:test";
import { createApi } from "./server.js";

type Row = Record<string, unknown>;

class FakeQuery {
  private currentRows: Row[];

  constructor(rows: Row[]) {
    this.currentRows = [...rows];
  }

  select() {
    return this;
  }

  ilike(column: string, pattern: string) {
    const value = pattern.replaceAll("%", "").toLowerCase();
    this.currentRows = this.currentRows.filter((row) =>
      String(row[column] ?? "")
        .toLowerCase()
        .includes(value),
    );
    return this;
  }

  eq(column: string, value: unknown) {
    this.currentRows = this.currentRows.filter((row) => row[column] === value);
    return this;
  }

  order(column: string, { ascending = true } = {}) {
    this.currentRows.sort((a, b) => {
      const result = Number(a[column]) - Number(b[column]);
      return ascending ? result : -result;
    });
    return this;
  }

  range(from: number, to: number) {
    this.currentRows = this.currentRows.slice(from, to + 1);
    return this;
  }

  async single() {
    return { data: this.currentRows[0] ?? null, error: null };
  }

  then(
    onfulfilled: (value: {
      data: Row[];
      error: null;
      count: number;
    }) => unknown,
  ) {
    return Promise.resolve(
      onfulfilled({
        data: this.currentRows,
        error: null,
        count: this.currentRows.length,
      }),
    );
  }
}

const priceRows = [
  {
    product_name: "Coca Cola 600 ml",
    source_product_name: "REFRESCO, COCA COLA, BOTELLA 600 ML",
    normalized_name: "coca cola 600 ml",
    store_name: "Tienda B",
    branch_name: "Sucursal Norte",
    price: 20,
    currency: "MXN",
    source: "profeco",
    captured_at: "2026-06-10T12:00:00.000Z",
    freshness: "fresh",
    days_old: 1,
    distance_km: 5.2,
    best_price: 18,
    price_rank: 2,
  },
  {
    product_name: "Coca Cola 600 ml",
    source_product_name: "REFRESCO, COCA COLA, BOTELLA 600 ML",
    normalized_name: "coca cola 600 ml",
    store_name: "Tienda A",
    branch_name: "Sucursal Centro",
    price: 18,
    currency: "MXN",
    source: "profeco",
    captured_at: "2026-06-09T12:00:00.000Z",
    freshness: "fresh",
    days_old: 2,
    distance_km: 2.1,
    best_price: 18,
    price_rank: 1,
  },
];

const tables: Record<string, Row[]> = {
  latest_prices: priceRows,
  compare_prices: priceRows,
  coverage_summary: [
    {
      total_products: 10,
      total_stores: 4,
      total_branches: 8,
      total_price_snapshots: 30,
      latest_snapshot_at: "2026-06-10T12:00:00.000Z",
      oldest_snapshot_at: "2026-05-01T12:00:00.000Z",
      snapshots_by_source: { profeco: 30 },
      products_by_source: { profeco: 10 },
      stores_by_source: { profeco: 4 },
    },
  ],
  branch_coverage_summary: [
    {
      total_normalized_branches: 8,
      total_geocoded_branches: 3,
      total_pending_geocoding: 5,
      total_city_codes: 1,
    },
  ],
  source_stats: [
    {
      source: "profeco",
      latest_snapshot_at: "2026-06-10T12:00:00.000Z",
      total_snapshots: 30,
    },
  ],
  branches: [
    {
      id: "branch-a",
      name: "Sucursal Centro",
      city_code: "0901",
      latitude: 19.4326,
      longitude: -99.1332,
      geocoding_status: "manual",
    },
  ],
};

async function withApi(run: (baseUrl: string) => Promise<void>) {
  const database = {
    from: (table: string) => new FakeQuery(tables[table] ?? []),
    rpc: (name: string) =>
      new FakeQuery(name === "nearby_prices" ? priceRows : []),
  } as unknown as Parameters<typeof createApi>[0];
  const server = createApi(database).listen(0);
  await new Promise<void>((resolve) => server.once("listening", resolve));
  const port = (server.address() as AddressInfo).port;

  try {
    await run(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  }
}

test("/api/v1/prices devuelve freshness y days_old", async () => {
  await withApi(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/api/v1/prices?query=coca`);
    const body = (await response.json()) as { data: Row[] };
    assert.equal(body.data[0]?.freshness, "fresh");
    assert.equal(typeof body.data[0]?.days_old, "number");
  });
});

test("/api/v1/prices permite listar catálogo sin query", async () => {
  await withApi(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/api/v1/prices?limit=50`);
    const body = (await response.json()) as { data: Row[] };
    assert.equal(response.status, 200);
    assert.equal(body.data.length, 2);
  });
});

test("/api/v1/compare ordena por precio y conserva sucursal", async () => {
  await withApi(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/api/v1/compare?query=coca`);
    const body = (await response.json()) as { data: Row[] };
    assert.deepEqual(
      body.data.map((row) => row.price),
      [18, 20],
    );
    assert.equal(body.data[0]?.branch_name, "Sucursal Centro");
  });
});

test("/api/v1/coverage devuelve métricas reales", async () => {
  await withApi(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/api/v1/coverage`);
    const body = (await response.json()) as { data: Row };
    assert.equal(body.data.total_price_snapshots, 30);
    assert.equal(body.data.total_geocoded_branches, 3);
    assert.deepEqual(body.data.snapshots_by_source, { profeco: 30 });
    assert.equal(body.data.city_code, "0901");
  });
});

test("/api/v1/sources lista fuentes habilitadas y deshabilitadas", async () => {
  await withApi(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/api/v1/sources`);
    const body = (await response.json()) as { data: Row[] };
    assert.equal(body.data.length, 6);
    assert.equal(
      body.data.find((row) => row.source === "profeco")?.enabled,
      true,
    );
    assert.equal(
      body.data.find((row) => row.source === "walmart")?.enabled,
      false,
    );
  });
});

test("/api/v1/nearby exige coordenadas", async () => {
  await withApi(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/api/v1/nearby?query=coca`);
    assert.equal(response.status, 400);
  });
});

test("/api/v1/nearby devuelve distancia y ordena por cercanía", async () => {
  await withApi(async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/api/v1/nearby?query=coca&lat=19.43&lng=-99.13&order_by=distance`,
    );
    const body = (await response.json()) as { data: Row[] };
    assert.deepEqual(
      body.data.map((row) => row.distance_km),
      [2.1, 5.2],
    );
  });
});

test("/api/v1/branches expone sucursales normalizadas", async () => {
  await withApi(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/api/v1/branches?city_code=0901`);
    const body = (await response.json()) as { data: Row[] };
    assert.equal(body.data[0]?.name, "Sucursal Centro");
    assert.equal(body.data[0]?.geocoding_status, "manual");
  });
});
