# ADR-0019 — Conciliación enrutada: el tamaño decide, no el signo; el sobrante se registra, no se absorbe

**Estado:** aceptada (2026-08-04) — nace de la sesión `grill-with-docs` de detalle de C3, la primera de la Ola 2. Refina [ADR-0011](ADR-0011-conciliacion.md) (que se escribió antes de que existiera la app) y aplica la regla de [ADR-0018](ADR-0018-valoracion-sin-contraparte-observada.md) a una fila más.

[ADR-0017](ADR-0017-sobregiro-registrable.md) legalizó el saldo negativo y delegó explícitamente en la conciliación la reconstrucción de la historia; [ADR-0018](ADR-0018-valoracion-sin-contraparte-observada.md) repitió esa delegación para el costo congelado de un ingreso registrado tarde. Ninguna de las dos definió el ritual. `RecordAdjustment` existe en el ledger desde C1 con tests, pero **sin ninguna pantalla que lo invoque**, y su guard `ForeignCurrencyPositiveAdjustmentNotAllowed` remitía a "regístralo como ingreso" — un camino que no existió hasta que #119 legalizó el Ingreso en cuenta extranjera. Este ADR define el ritual.

## Decisión

1. **El destino del delta lo decide su tamaño, no su signo.** `delta = saldoRealDeclarado − saldoProyectado`. Por debajo de la Tolerancia se **absorbe** contra el Sobre de sistema Ajustes en un toque; por encima se **enruta**: hacia arriba la app ofrece registrar el Ingreso que el delta implica, hacia abajo el Gasto. Declinar el enrutado absorbe igual — la Tolerancia gobierna fricción, jamás qué se postea. Es la doctrina de ADR-0011 ("la tolerancia gobierna la fricción, no si ajusta") extendida al signo positivo, que ADR-0011 no contemplaba.

2. **El sobrante grande se registra como Ingreso, no se absorbe.** Un Ajuste aterriza en el Sobre Ajustes, que nadie distribuye; un Ingreso aterriza en Stage y entra a la cascada. Absorber cada sobrante desfinancia los Sobres del usuario de forma crónica mientras Ajustes crece sin composición conocida — la app diría que el dinero está y ningún Sobre lo vería. El caso motivador de ADR-0017 (saldo negativo por un cobro sin registrar) es exactamente este, y así queda saldado: el sobregiro se cierra con el Ingreso que faltaba, no con un parche.

3. **La Tolerancia es un único umbral en USD, constante, sin pantalla de configuración.** Se compara convirtiendo el delta nativo a la tasa vigente. En USD porque cualquier cifra en bolívares se pudre con la inflación y el re-tuneo periódico es mantenimiento que se olvida. Una sola constante y no una cadencia por Cuenta: el número correcto es lo que el dogfooding debe enseñar, y elegir seis ahora sería adivinar.

4. **`ForeignCurrencyPositiveAdjustmentNotAllowed` desaparece.** La simetría del punto 1 exige poder absorber un sobrante chico en cuenta extranjera, y su valoración es la regla ya fijada: sin contraparte USD observada, el valor congelado sale de la última Observación de Tasa paralela (ADR-0018 §1). El guard era una reliquia de cuando el Ingreso en Bs era ilegal; su propia salida ("use an income") solo empezó a funcionar el 2026-08-04.

5. **La captura enrutada pregunta la fecha del hecho y valora con la Observación de Tasa más cercana a ella**, no con la de hoy. Sin esto la promesa de ADR-0018 ("la conciliación es quien lo corrige después") es circular: volvería a congelar con el mismo error que dice corregir. Si no existe observación de esa fecha se usa la más cercana disponible y **la app lo anuncia** — el costo se anuncia, jamás se inventa. `RateSeries.latestFor` gana un parámetro `asOf`; `QuickAddIncomeUseCase` ya acepta `occurredAt`.

6. **Sin cadencia ni recordatorios: cada Cuenta muestra hace cuánto se concilió.** El dato que hace falta para decidir, y nada más. Difiere deliberadamente la cadencia por Cuenta y el badge de vencidas de ADR-0011 §Ritmo.

**Alternativas rechazadas:**

- **Ajuste ciego en ambos sentidos** (lo que el código permitía hacia abajo) — un toque y cero fricción, pero entierra un gasto o un cobro real como "ajuste" y deja los Sobres mintiendo en la dirección contraria a la realidad.
- **Enrutar siempre, sin umbral** — máxima fidelidad contable, pero obliga a justificar cada comisión bancaria de dos bolívares; el ritual se vuelve tan pesado que se abandona, y la disciplina ya era el riesgo declarado en ADR-0011.
- **Umbral por moneda (Bs 500 · USD $0,50), como esbozaba ADR-0011** — comparar peras con peras sin convertir, a cambio de un número que caduca cada pocos meses.
- **Umbral como porcentaje del saldo** — se autoajusta a la inflación, pero en una cuenta de $5.000 toleraría $50 sin preguntar, justo el tamaño de error que hay que ver.
- **Preguntar la tasa del día del cobro en vez de la fecha** — sirve aunque nunca se haya registrado esa tasa, pero rompe la regla de que la app anuncia con qué valora y obliga a recordar un número de hace semanas.
- **Notificación push del ritual** — lo más difícil de ignorar, y lo primero que se silencia.

**Consecuencia:** `RecordAdjustment` deja de ser una factory huérfana y pasa a tener un único invocador, restringido a deltas por debajo de la Tolerancia. `ForeignCurrencyPositiveAdjustmentNotAllowed` sale del dominio junto con su test. `RateSeries` gana consulta histórica (`asOf`), que S1 y S5 heredan. ADR-0011 queda vigente en su definición de "conciliado" y en `última conciliación`; su cadencia por Cuenta y su tolerancia configurable por Cuenta quedan diferidas hasta que el uso real las pida. El delta enrutado hacia arriba propone un Ingreso cuyo monto es correcto en neto pero no necesariamente en composición (puede mezclar un cobro olvidado con gastos olvidados); se acepta porque el saldo queda correcto y la alternativa —reconstruir la composición— es adivinación.
