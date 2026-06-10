# ADR-0007 — Servicio de Tasas: Binance P2P canónico, multi-fuente, ingesta vía agregador

**Estado:** aceptada (2026-06-09)

**Tasa paralela canónica = Binance P2P** (mediana del libro), guardando los **dos lados**
(vender ~745 / cambiar ~760) — es donde el usuario transacciona, la más veraz para su costo
real. **BCV oficial** como serie aparte para el diferencial. Se **guardan varias fuentes en
paralelo** (BCV, Binance vender/cambiar, banca) como serie **append-only** (hecho observado,
ADR-0002).

**Camino de ingesta:** **agregador primario** (ej. Cotizave: BCV + paralelo + USDT/VES
multi-exchange en un JSON normalizado, sin scraper propio) con **endpoint P2P de Binance
directo como fallback y cross-check**. Si ambos fallan, se arrastra el último valor conocido
con bandera de "obsoleto".

**Frecuencia:** worker en GitHub Actions 2–3×/día (ADR-0004); cada corrida anexa una
observación.

**Por qué:** el costo real por transacción usa la tasa **ejecutada** que el usuario ingresa; el
servicio de Tasas alimenta el **overlay de valoración, el diferencial y los reportes**, que
toleran lag. Por eso se prioriza bajo mantenimiento (agregador) sobre máxima frescura.

**Reversibilidad:** alta. El camino de ingesta es un adaptador detrás de un puerto; cambiar de
agregador o pasar a Binance-directo no toca el dominio.

**Contexto VE (2026-06-09):** USDT en Binance P2P ≈ 767 VES; es el indicador de referencia de
facto del país.
