# ADR-0016 — Manual rates as observed facts; parallel values, BCV informs

**Estado:** aceptada (2026-07-23) — nace en la sesión `grill-with-docs` de detalle de S2 (Patrimonio). Adelanta una porción mínima de [ADR-0007](ADR-0007-servicio-tasas.md) (el almacén de la serie) sin modificarlo.

S2 (Patrimony) promises "where the money is" + net worth in USD + the valuation overlay (ADR-0006), but the Rates service (S1, ADR-0007) is scheduled *after* S2. The MVP plan said "manual rate" without defining it. This ADR fixes what that means and the valuation semantics of the Venezuelan multi-rate reality.

## 1. The manual rate is an Observed External Fact, not config

Each manually entered rate is **appended** to a local time series (`(currency, nativePerUsd, observedAt, source)`), never overwritten. S2 reads "latest observation ≤ now" through the `RateService` port. When S1 arrives, its worker appends to the **same series** with automatic sources (`bcv`, `cotizave`) — ingestion gets automated, the model does not change.

**Why:** the rate is the canonical example of an observed fact (ADR-0002); an LWW "today's rate" field would destroy the history that the exchange-differential report and "net worth over time" (S5) need, and would be thrown away when S1 lands.

## 2. The series lives in a new minimal `tasas` package — the embryo of S1

`packages/tasas`: `RateObservation` VO, `RateSeries` port (`append`, `latestFor(currency)`), a Drift adapter, and the "record manual rate" use case. The orphan `RateService` port currently in `contabilidad/domain/ports/` moves here. Neither `contabilidad` (works at frozen real cost, never consults today's rate) nor `patrimonio` (read-only projection context, owns no stores by definition) may own the series.

## 3. Own Drift database, **unencrypted**

The series is stored in its own small Drift database inside `tasas/infrastructure/`, **without SQLCipher**. Market rates are public data — encrypting "BCV closed at 40.10" protects nothing personal, and skipping SQLCipher avoids all key plumbing. ADR-0014's invariant stays intact: there is exactly **one** encrypted database (the financial one), with one key.

## 4. Dual manual capture (BCV + parallel) — temporary until S1

The MVP captures **both** rates for VES (BCV and parallel), each as its own observation with its `source`. This is explicitly a stopgap: the double manual entry disappears when S1's worker brings both automatically.

## 5. Valuation semantics: **the parallel rate values, the BCV informs**

- **Net worth and unrealized P&L are computed with the parallel rate only** — it is the rate at which money can actually be converted (liquidation value). One number rules the header.
- **The BCV value is shown as a labeled reference line** ("sticker" purchasing power against official prices), per account and in the header. It never enters net worth nor unrealized P&L.
- The **executed rate** of a past operation never participates in today's valuation — it lives frozen in the ledger as real cost (ADR-0006); realization compares executed rate vs average base cost, not today's rates.
- **No observation for a currency → that account shows real cost**, with a visible "no rate" indicator and the header flagged as partial. A silent 1:1 fallback is forbidden.
- **Staleness is visible**: the overlay shows the observation date.
- Arithmetic: `Decimal` for rates, integer minor units for money, a **single rounding per account** (`round(native / rate)`), totals sum already-rounded integers.

**Alternativas rechazadas:**

- **S2 without overlay (real cost only)** — empties the PRD: the devaluation effect on net worth is half the reason the app exists.
- **Manual rate as LWW config** — violates ADR-0002; loses the series; migration debt for S1.
- **Series inside `contabilidad` or `patrimonio`** — inflates the write context with data it never uses / contradicts the read-only projection identity; both would force an extraction when S1 grows.
- **Rates table inside the encrypted `CuentariaDatabase`** — entangles another context's table and migrations into `contabilidad`'s schema and forces cross-boundary access to the DB instance.
- **Single "effective rate" in the MVP** — rejected by product: both BCV and parallel must be visible from day 1; the cost is double manual capture, accepted as temporary.
- **Averaging/mixing both rates in the header** — a blended net worth means nothing actionable.

**Consecuencia:** S1's `to-prd` shrinks to: worker + automatic sources + fallback doctrine over an existing store. The F4 export and F3 sync may exclude the series (public, reconstructible data). S2 consumes `RateSeries`/`RateService` by port; the UI offers a minimal "record today's rates" action (two fields, BCV + parallel), no rate-management screen.
