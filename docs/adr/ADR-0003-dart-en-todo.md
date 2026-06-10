# ADR-0003 — Dart en todo el sistema, incluidos los workers de integración

**Estado:** aceptada (2026-06-09)

Un solo lenguaje: **Dart** para el core de dominio (forzado por ADR-0001, corre en el cliente
Flutter) **y** para los workers de integración. Los workers se compilan **AOT** a binario
nativo y se despliegan como **contenedor scale-to-zero** (Cloud Run / Fly.io).

**Por qué:** los workers son *I/O-bound* (esperan a Binance/BCV/explorers), así que rendimiento
y memoria entre Dart y Node son irrelevantes a esta escala. Lo que pesa es la **coherencia de
un solo lenguaje** y poder **reusar los modelos del core** sin re-modelar tipos. Dart AOT da
arranque rápido y memoria baja, y corre como función efímera de primera clase (custom runtime
en AWS Lambda, o contenedor en Cloud Run/Fly).

**Alternativas rechazadas:**

- **TypeScript en edge functions (Supabase/Cloudflare):** menor fricción al free tier y
  ecosistema serverless más maduro (SDKs JS para toda API, más ejemplos, más data para
  agentes). Rechazada por introducir un segundo lenguaje y obligar a re-modelar tipos fuera del
  core. Costo asumido al elegir Dart: a veces no hay SDK oficial en Dart (Binance/PayPal) y se
  llama el REST crudo; y se arma el contenedor en vez de pegar una función gestionada.

**Reversibilidad:** baja-riesgo. Un fetcher individual puede moverse a TS más adelante sin
tocar el dominio (los workers son tontos: fetch → normaliza → anexa hecho observado).

**Implicación de hosting (alimenta ADR-0004):** el "backend" se reduce a contenedor(es) Dart
scale-to-zero + Supabase Postgres. **No hay servidor web de aplicación → Vercel queda sin rol
de cómputo**; a lo sumo hospeda el build estático de Flutter Web.
