# ADR-0006 — Ledger Cuenta × Sobre

Dos dimensiones independientes, transacción auto-balanceada, costo real + valoración overlay.

**Estado:** aceptada (2026-06-09)

**Modelo estructural.** Dos dimensiones **independientes** (no una matriz conjunta
`celda[Cuenta][Sobre]`). Se proyectan dos vectores marginales: saldo por **Cuenta** y saldo por
**Sobre**, que comparten un gran total. No se rastrea qué porción de una cuenta pertenece a cada
sobre (un sobre puede vivir repartido en varias cuentas; el invariante es solo sobre los
totales).

**Regla de oro — transacción auto-balanceada.** Cada transacción (evento de dominio) debe
cumplir por sí sola:
`Σ postings.usd[dimensión Cuenta] == Σ postings.usd[dimensión Sobre]`.
El dominio **rechaza** transacciones que no la cumplan. Como cada transacción preserva el
invariante por separado, **cualquier orden de fusión de transacciones lo preserva por
inducción** → merge multi-dispositivo offline seguro por construcción. Esta es la pieza que
hace que event sourcing + offline + invariante encajen.

Efecto por tipo: Ingreso (+X,+X) · Gasto (−X,−X) · Transferencia (−X+X en Cuentas, 0 en Sobres)
· Distribución (0 en Cuentas, mueve entre Sobres) · Conversión P2P/FX (−X USD Cuenta, +X USD
Cuenta-Bs valorada; 0 en Sobres) · Conciliación y realización (δ en Cuenta y δ en un Sobre tipo
"Ajustes").

**Forma del evento.** Transacción = evento inmutable con `tipo`, metadatos (`occurred_at`,
`recorded_at`, `device_id`, `source`, `schema_version`) y `postings[]`. Cada posting:
`(dimensión: Cuenta|Sobre, target_id, amount_native, currency, amount_usd, rate_ref?)`.

**Costo real congelado.** `amount_usd` se **snapshotea** al momento de la transacción (lo que
realmente entró/salió) y no se recalcula. `rate_ref` apunta al hecho de tasa usado, para el
campo opcional de diferencial BCV.

**Valoración a mercado = overlay de solo-lectura.** El ledger se mantiene a **costo real**; el
invariante se cumple a costo base. El **valor actual** y la **P&L no realizada** se calculan al
vuelo en Patrimonio/Portafolio (`cantidad × tasa/precio actual` de la serie de Tasas), **sin
postear** transacciones. Solo al **realizar** (Bs→USD a nueva tasa, venta de cripto, gasto de
Bs) se postea la transacción real que materializa la diferencia. Patrimonio neto mostrado =
saldos del ledger + overlay; la diferencia ES la P&L no realizada.

**Alternativa rechazada:** eventos de valoración posteados periódicamente — inflan el log y
mezclan no-realizado con movimientos reales.

**Etiqueta fuente/cliente.** Las transacciones de Ingreso llevan `source` (cliente) como
dimensión → habilita la proyección de flujo de caja por cliente.

**Preparación Portafolio Nivel 2.** Los postings/holdings capturan `instrument_id`, `quantity`
y los eventos de adquisición append-only desde el MVP, aunque Nivel 1 solo use valoración
actual. Así Nivel 2 (PNL/cost basis por lote) se computa después sin reescritura, donde haya
datos.

**Proyecciones (read models) derivadas del log:** saldo por Cuenta · saldo por Sobre ·
patrimonio en el tiempo · flujo de caja por fuente/cliente · gasto por sobre/categoría ·
progreso de Sobres vs meta · balance de deuda por persona · diferencial cambiario capturado.
