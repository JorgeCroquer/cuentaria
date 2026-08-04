# ADR-0017 — Sobregiro registrable: el ledger admite saldos negativos y el exceso se valora a tasa de ejecución

**Estado:** aceptada (2026-08-04) — nace de la verificación humana del MVP (#110 → #113).

La verificación humana del MVP (#110→#113) mostró que un gasto en Bs mayor que el saldo conocido se rechazaba (`InsufficientBalance`), impidiendo registrar un hecho real; la causa típica de un saldo corto es un ingreso sin registrar. Además la misma acción validaba distinto según la moneda (USD no validaba; Bs sí), diferencia invisible para el usuario porque la factory se deriva de la moneda de la cuenta pagadora (doctrina U1: "el usuario jamás ve nombres de factories"). El costo real de una realización es proporcional al saldo ([ADR-0006](ADR-0006-ledger-cuenta-sobre.md), costo congelado); sobre el exceso esa proporción no está definida.

## Decisión

1. **Todo gasto/disposal se registra siempre.** El saldo puede quedar negativo; la UI lo señala como indicio de ingreso faltante, no como error.
2. **Regla única para todas las monedas.** `record_usd_expense` y las tres caras de `RecordRealization` (`foreignCurrencyExpense`, `disposalConversion`, `cryptoSale`) admiten saldo negativo — `record_usd_expense` nunca validó, así que la unificación es de comportamiento observable, no de código nuevo ahí.
3. **El costo base del exceso es su valor a la tasa de ejecución del propio movimiento ⇒ diferencial cero sobre el exceso.** Sobre dinero cuya entrada no se registró, el ledger declara ignorancia en vez de fabricar P&L (mismo espíritu de [ADR-0016](ADR-0016-tasas-manuales-valoracion-patrimonio.md): el costo se anuncia, nunca se inventa). La regla zero-native de C1-6 se conserva intacta para la parte cubierta. La transacción auto-balanceada Σ usd[Cuenta] == Σ usd[Sobre] ([ADR-0006](ADR-0006-ledger-cuenta-sobre.md)) se mantiene intacta.

Formalmente, para un disposal de `monto` contra un `saldoNativo` conocido:

```
cubierto = clamp(saldoNativo, 0, monto)
exceso   = monto - cubierto
costBasis = baseCostOf(cubierto) + round(exceso / tasaDeEjecución)
```

donde `tasaDeEjecución` es la que ese path ya resuelve (la tasa de mercado explícita en `foreignCurrencyExpense`; el precio implícito `usdAmountReceived / montoDispuesto` en `disposalConversion` y `cryptoSale`, que ya observan el proceeds real en vez de una tasa). Un único redondeo por término, `Decimal`/enteros, jamás `double`.

`record_adjustment` (C3) también usa `baseCostOf` pero queda **fuera de esta ADR** — su disposal es territorio de conciliación y se revisa en su propio PRD.

### Tabla de tests

| Escenario | cubierto | exceso | costBasis | Balanza |
|---|---|---|---|---|
| (a) Disponer exactamente el saldo | saldo completo | 0 | `baseCostOf(saldo)` (zero-native: barre todo el costo) | Σ cuadra |
| (b) Disponer más con saldo positivo | saldo | monto − saldo | `baseCostOf(cubierto) + market(exceso)` | Σ cuadra |
| (c) Disponer con saldo en cero | 0 | monto | `market(monto)`, diferencial 0 | Σ cuadra |
| (d) Disponer con saldo ya negativo | 0 (clamp) | monto | `market(monto)`, diferencial 0 | Σ cuadra |

## Señal de descuadre (UI)

Un saldo negativo se **muestra**, no se esconde: en Patrimonio (grupo de moneda) y en la pantalla de Cuentas (fila de la cuenta), con estilo de alerta y el texto "Saldo negativo — ¿falta registrar un ingreso?" — apunta a la causa probable en vez de un número rojo sin explicación.

**Alternativas rechazadas:**

- **Seguir bloqueando con mejor mensaje** — el hecho real queda sin registrar; no resuelve el problema, solo lo comunica mejor.
- **Tolerancia por umbral** — mete un número arbitrario en el dominio del dinero y hace el comportamiento impredecible.
- **Costo base cero para el exceso** — sobreestima la ganancia cambiaria sobre dinero del que el ledger no sabe nada.

**Consecuencia:** el saldo negativo (sobregiro) es un estado legal y visible del ledger. La conciliación (C3) es quien reconstruye la historia cuando aparece el ingreso faltante. `record_adjustment` queda fuera y se revisará en su propio PRD. `InsufficientBalance` desaparece del dominio — append-only no necesita reliquias de una regla que ya no existe.
