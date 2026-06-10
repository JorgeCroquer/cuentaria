# ADR-0007 — Rates Service: canonical Binance P2P, multi-source, ingestion via aggregator

**Status:** accepted (2026-06-09)

**Canonical parallel rate = Binance P2P** (median of the book), saving **both sides** (sell ~745 / buy ~760) — it's where the user transacts, the most truthful for their real cost. **Official BCV** as a separate series for the differential. **Several sources are saved in parallel** (BCV, Binance sell/buy, banking) as an **append-only** series (observed fact, ADR-0002).

**Ingestion path:** **primary aggregator** (e.g. Cotizave: BCV + parallel + USDT/VES multi-exchange in a normalized JSON, without custom scraper) with **direct Binance P2P endpoint as fallback and cross-check**. If both fail, the last known value is carried over with a "stale" flag.

**Frequency:** GitHub Actions worker 2–3×/day (ADR-0004); each run appends an observation.

**Why:** the real cost per transaction uses the **executed** rate that the user inputs; the Rates service feeds the **valuation overlay, the differential and reports**, which tolerate lag. Therefore, low maintenance (aggregator) is prioritized over maximum freshness.

**Reversibility:** high. The ingestion path is an adapter behind a port; changing aggregator or moving to direct Binance does not touch the domain.

**VE Context (2026-06-09):** USDT on Binance P2P ≈ 767 VES; it is the de facto benchmark indicator of the country.
