# ADR-0024 — Reportes en costo real: mes calendario, flujo por rol de sobre, sin snapshots

**Estado:** aceptada (2026-09-05) — nace de la sesión `grill-with-docs` de detalle de **S5 Reportes**, la última pendiente de la Ola 2. No supersede a nadie: aplica [ADR-0006](ADR-0006-transaccion-autobalanceada.md) (costo real congelado), [ADR-0002](ADR-0002-append-only.md) (proyección recomputable) y [ADR-0018](ADR-0018-valoracion-sin-contraparte-observada.md)/[ADR-0020](ADR-0020-ingesta-de-tasas-sin-servidor.md) (anunciar la tasa) al terreno de la lectura a través del tiempo.

## Contexto

Hasta hoy la app solo muestra el presente: saldos, cascada, patrimonio de hoy, deuda de hoy. S5 es la primera lectura **a través del tiempo y de contextos**: gasto por sobre, ingreso por fuente, patrimonio, diferencial cambiario, aportes a metas y deuda por persona, por mes. Un reporte que mezcla monedas, cuenta transferencias como gasto o revalúa el pasado con la tasa de hoy miente con números bonitos, y en la realidad venezolana la mentira es de dos dígitos por mes.

## Decisión

1. **Una sola moneda de reporte: el costo real congelado (`amount_usd`).** Sin selector. Es la única suma honesta entre Bs, USD y cripto, es comparable mes contra mes y no cambia hacia atrás. La nativa solo aparece cuando el reporte está filtrado a una moneda. Revaluar el pasado a tasa de hoy queda para el overlay de patrimonio, nunca para un reporte de flujo.

2. **Flujo del usuario se define por el rol del sobre tocado, no por el tipo de evento.** Un movimiento cuyas patas caen todas en bolsillos propios (Transfer, Distribution, Conversion, Opening) o en un Sobre de Sistema (Adjustment, Diferencial) no es flujo. Gasto = movimientos hacia sobres del usuario; ingreso = movimientos desde afuera, agrupados por la etiqueta `source`. Ajustes y diferencial tienen su propio renglón: una conciliación de −$0,60 no es comida.

3. **Un Reversal resta en el mes del movimiento original.** Corregir un error en septiembre no mueve el gasto de agosto a septiembre; la historia queda como fue.

4. **Mes calendario, hora local, contra el mes anterior completo.** Sin «últimos 30 días» ni rango libre. El corte en hora local del dispositivo evita que un gasto de las 10 pm del 31 caiga en el mes siguiente por estar guardado en UTC.

5. **Las series son proyecciones recomputadas, no snapshots.** Un punto mensual = el log reproducido hasta el fin de mes con el motor existente (patrimonio, deudas) y la Cadena de Resolución de tasas `asOf` esa fecha. Doce reproducciones cuestan milisegundos y nunca desincronizan. Cuentas archivadas cuentan en los meses en que tenían saldo.

6. **Hueco honesto.** Si una moneda no tiene observación de tasa en o antes de una fecha, el overlay de ese punto queda en blanco; el costo real sigue. Una tasa vieja se usa y se anuncia con su fecha. Nunca se interpola ni se rellena hacia atrás.

7. **El motor es puro y la vista es una entrada.** Paquete `reportes` que solo depende de `shared_kernel`, alimentado por la app con vistas, igual que `patrimonio` y `deudas`. Una sola pantalla «Reportes» con el mes como estado compartido; gráficos con `fl_chart`, elegida por el autor sobre barras a mano.

**Alternativas rechazadas:**

- **Selector de moneda (USD / Bs / nativa)** — flexible, pero sumar Bs con USD es inventar y un reporte en Bs de hace seis meses no significa nada hoy.
- **USD a tasa de hoy para reportes de flujo** — «cuánto vale eso ahora»; es exactamente lo que ADR-0006 prohíbe como dato y haría que agosto cambie cada vez que se mira.
- **Clasificar por tipo de evento** — funciona hoy y se rompe con el próximo tipo; el rol del sobre ya es el criterio del resto del sistema.
- **Reversal en el mes del reversal** — más «contable», a cambio de un agosto que engorda y un septiembre con un gasto negativo.
- **Últimos 30 días / rango libre** — más botones, y «este mes» deja de coincidir con el mes que el usuario recuerda.
- **Snapshots mensuales persistidos** — más rápido en teoría; una tabla que puede divergir del log y viola la definición de Projection de ADR-0002.
- **Interpolar tasas faltantes** — curva continua a cambio de un patrimonio inventado en los meses sin señal.
- **Repartir los reportes por contexto** — seis puntos de entrada y ningún «cómo voy».

**Consecuencia:** `docs/CONTEXT.md` estrena **User Flow**, **Report Month** y **Net Worth Point**. La app estrena su primera librería de gráficos. Nace `packages/reportes`. Ningún evento nuevo, ninguna tabla nueva, ningún HITL. La pantalla de la serie histórica de tasas que ADR-0020 difirió a S5 entra como sección de Reportes. Exportar o compartir un reporte queda fuera hasta que alguien lo pida.
