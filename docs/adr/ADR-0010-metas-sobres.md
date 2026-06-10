# ADR-0010 — Modelo unificado de metas/aportes de Sobres

**Estado:** aceptada (2026-06-09)

Un Sobre puede financiarse por una o varias reglas de la cascada: **aporte fijo recurrente que
acumula** (ahorro, sin tope), **llenar-hasta-meta con cap** (gasto), y/o **% del remanente**.
El **target es opcional** y polimórfico según el rol del sobre:

- Sobre de **gasto** → el target es un **cap** (tope de trabajo del período).
- Sobre de **ahorro** → el target es una **línea de meta** por **monto o fecha**: mide progreso
  y sugiere cuota, pero **no limita el crecimiento**.

**Por qué:** un Sobre es a veces un balde de gasto y a veces una alcancía; el sistema soporta
ambos en vez de imponer uno. Reconcilia la práctica real (aporte que acumula) con el
presupuesto de gasto con tope. Coincide con los tres tipos de paso de la cascada.

**Manejo de faltantes (mes flaco):**

1. *No alcanza para aportar:* la cascada **ordenada con preview + skip** llena primero lo
   esencial; los aportes de ahorro (más abajo) reciben menos o nada por falta de remanente.
   **Nunca se va a negativo**; no se fuerza dinero inexistente.
2. *Hay que gastar más de lo que entró (tirar de ahorros):* se hace con una transacción
   **Distribución** que **reetiqueta** del Sobre de ahorro al Sobre que lo necesita — el dinero
   real no se mueve, solo la intención; el invariante `Σ Cuentas == Σ Sobres` queda intacto.
   Luego se registra el Gasto normal.

**Consecuencia:** `Sobre.meta` se modela como value object con discriminador
`{ninguna | cap | linea_meta(monto|fecha)}` y `Sobre` referencia sus reglas de aporte de la
cascada.
