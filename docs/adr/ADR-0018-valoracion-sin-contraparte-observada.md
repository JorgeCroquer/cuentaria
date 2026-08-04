# ADR-0018 — Valoración sin contraparte observada: el costo congelado sale de la serie de tasas paralela

**Estado:** aceptada (2026-08-04) — nace de la sesión de doctrina no-USD (#110 → #119, #116, vecino de #120).

La doctrina de derivación de U1 (PRD #92) dice que el usuario solo ve **Gasto · Ingreso · Mover** y que la factory se deriva de las monedas involucradas, sin mostrarle jamás taxonomía contable. La verificación humana del MVP (#110) encontró que la doctrina estaba escrita solo para las filas con moneda USD y para el Gasto en Bs: **Ingreso en cuenta Bs** lanzaba `UsdOnlyOperation` (#119), **Mover Bs→USD** no estaba cableado pese a existir la factory (#116) y **Mover Bs↔Bs entre dos cuentas propias** era ilegal por un guard USD-only (`record_transfer.dart:44`, vecino de #120).

Al trazar las filas mudas aparece que no se distinguen por operación (Ingreso vs Mover) sino por si la operación tiene **contraparte USD observada**:

| | ¿Contraparte USD observada? | De dónde sale el valor congelado |
|---|---|---|
| Mover USD↔extranjera (P2P) | sí — el USD entregado/recibido es un hecho | ese número, tal cual |
| Venta de cripto | sí — el proceeds real | ese número, tal cual |
| Gasto en Bs | no | tasa paralela de la serie (ya lo hacía) |
| Ingreso en Bs | no | ← lo que decide este ADR |
| Exceso de un traspaso Bs↔Bs | no | ← lo que decide este ADR |

[ADR-0006](ADR-0006-ledger-cuenta-sobre.md) congela `amount_usd` al momento del hecho, pero no dice de dónde sale ese número cuando **no existe ningún USD observado**. [ADR-0016](ADR-0016-tasas-manuales-valoracion-patrimonio.md) dice que la tasa ejecutada vive congelada en el ledger y que el paralelo valora patrimonio — leído sin contexto, parece prohibir justo lo que aquí se decide. Este ADR resuelve esa aparente contradicción.

## Decisión

1. **Regla única: sin contraparte USD observada, el valor USD se congela con la última Observación de Tasa paralela** (`manual:paralelo`) de esa moneda. Es lo que `foreignCurrencyExpense` ya hacía por su cuenta; se eleva a doctrina y se aplica también al Ingreso en cuenta extranjera y al exceso del traspaso de misma moneda. Corolario a ADR-0016: **cuando no hubo tasa ejecutada, la tasa de liquidación _es_ el costo real** — cualquier otro número sería inventado. Con contraparte observada la regla no cambia: se usa el monto observado, nunca una tasa.

2. **El Ingreso en cuenta extranjera es one-sided.** El usuario teclea solo el monto nativo; la app lo valora. Postings: cuenta `(+nativo, amount_usd = round(nativo / tasa), rate_ref)` y Stage `(+amount_usd, USD)`. Σ usd[Cuenta] == Σ usd[Sobre] y **sin diferencial**: al entrar dinero no se realiza nada, la P&L aparece después al disponerlo. `RecordIncome` se ensancha; no nace factory nueva.

3. **El traspaso entre dos cuentas de la misma moneda no-USD es legal.** Mueve el costo congelado proporcional, con el exceso valorado igual que en [ADR-0017](ADR-0017-sobregiro-registrable.md):

   ```
   cubierto = clamp(saldoNativo, 0, monto)
   exceso   = monto - cubierto
   costo    = baseCostOf(cubierto) + round(exceso / tasaParalela)
   ```

   Ambos postings llevan **el mismo** `amount_usd` (uno negativo, otro positivo) ⇒ Σ = 0 en las dos dimensiones y **sin posting de diferencial**: mover etiquetas de sitio no realiza P&L. Es la fórmula de ADR-0017 con la tasa de la serie en lugar de la tasa de ejecución, porque en un traspaso no hay ejecución.

4. **La app anuncia con qué valora.** Toda operación valorada por la serie muestra la tasa usada y su fecha. Si la observación **no es de hoy** (día calendario local) lo advierte, sin bloquear. Si no existe ninguna observación para esa moneda, bloquea con un atajo para registrarla: el costo se anuncia, jamás se inventa. El umbral vive en la **presentación** y no altera ningún posting — no es la tolerancia que ADR-0017 rechazó, que cambiaba qué se postea o qué se rechaza.

5. **Extranjera ↔ otra extranjera distinta queda fuera de alcance**, y se impide en los selectores: el par no se puede formar, en vez de aceptarse y fallar al guardar. Ninguna combinación alcanzable desde la UI lanza una excepción sin postear.

6. **La resolución de tasa vive en la capa app.** `contabilidad` no puede importar el `domain/` de `tasas` ([ADR-0005](ADR-0005-monolito-modular.md)): las factories reciben `Decimal`, y los tres casos de uso de captura rápida (Gasto, Ingreso, Mover) viven juntos en `apps/cuentaria_app/lib/features/capture/application/`. `QuickAddMoverUseCase` se muda allí desde `contabilidad`.

### Matriz de derivación resultante (9 filas, ninguna muda)

| Operación | Cuenta origen | Destino | Factory |
|---|---|---|---|
| Gasto | USD | sobre | `RecordUsdExpense` |
| Gasto | extranjera | sobre | `RecordRealization.foreignCurrencyExpense` |
| Ingreso | — | cuenta USD | `RecordIncome` |
| Ingreso | — | cuenta extranjera | `RecordIncome` valorada a paralelo |
| Mover | USD | USD | `RecordTransfer` |
| Mover | USD | extranjera | `RecordAcquisitionConversion` |
| Mover | extranjera | USD | `RecordRealization.disposalConversion` |
| Mover | extranjera | misma extranjera | `RecordTransfer` con costo proporcional |
| Mover | extranjera | otra extranjera | — (par no formable) |

**Alternativas rechazadas:**

- **Ingreso en Bs two-sided (monto + tasa declarada por el usuario).** Sería más fiel a un cobro pactado a otra tasa, pero introduce un segundo mecanismo de valoración para el problema que el Gasto en Bs ya resuelve de un lado solo, y un cobro en Bs vale lo que vale al paralelo, no lo que dijo la factura.
- **Exceso a costo cero en el traspaso de misma moneda.** Deforma el costo promedio de la cuenta destino y fabrica una ganancia cambiaria al gastarlo después — la misma razón por la que ADR-0017 lo rechazó en los disposals.
- **Puerto de valoración dentro de `contabilidad`.** Inversión de dependencias de manual para una interfaz con una sola implementación; el Gasto en Bs ya demostró que basta con que la factory reciba un `Decimal`.
- **Umbral de antigüedad en horas o configurable.** Número arbitrario en el camino del dinero; "no es de hoy" es un límite natural del paralelo, que cotiza a diario.
- **Paliativo: filtrar los chips no-USD en Ingreso.** Deja de parecer un crash y deja el caso real (clientes que pagan en Bs) sin cubrir.

**Consecuencia:** la serie de tasas pasa de valorar una operación a valorar tres, así que sin una sola observación paralela se bloquean tres caminos de captura en vez de uno. El costo congelado de un ingreso en Bs depende de cuándo el usuario registró la tasa; la conciliación (C3) es quien lo corrige después. `RecordTransfer` gana `LedgerProjections` y un parámetro de tasa. `UsdOnlyOperation` desaparece de `RecordIncome` y de `RecordTransfer`; sobrevive en `RecordAcquisitionConversion`, donde expresa que el origen debe ser USD. `CrossCurrencyTransfer` sigue vivo: el traspaso exige misma moneda y es el caso de uso quien enruta lo demás.
