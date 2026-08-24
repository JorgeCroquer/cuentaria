# ADR-0022 — Deudas sin Persona: una Cuenta por persona, el signo cuenta la historia

**Estado:** aceptada (2026-08-24) — nace de la sesión `grill-with-docs` de detalle de **S3 — Deudas**. Ratifica la fila "Debts" de [ADR-0005](ADR-0005-monolito-modular.md) y anota una errata de [ADR-0002](ADR-0002-append-only.md).

El ledger tiene exactamente dos dimensiones — Cuenta y Sobre (`posting_target.dart`) — y ninguna es una persona. ADR-0005 decidió en junio que Deudas es una **proyección de solo lectura** sobre "cuentas por cobrar/pagar", pero ese tipo de cuenta nunca se construyó: el catálogo no tiene tipos, solo el mapa `meta` como vía de extensión (patrón FundingTarget/color/lastReconciledAt). Este ADR fija cómo se cierra ese hueco sin tocar el ledger.

## Decisión

1. **La persona no existe como entidad ni como dimensión: es una etiqueta sobre una Cuenta de Deuda.** Una Cuenta de Deuda es una Cuenta del Catálogo marcada en su `meta` con la persona contraparte. Para el motor es una cuenta más — mismos postings, misma invariante de auto-balanceo, misma participación en el patrimonio. El "balance por persona" es el saldo de su(s) cuenta(s), gratis, como anticipó la nota de dominio de junio. La UI las segrega siempre (pantalla Deudas propia; jamás mezcladas con Efectivo/Banco).

2. **Un solo tipo, el signo cuenta la historia.** No hay tipos "por cobrar" y "por pagar": saldo positivo = te deben (activo), negativo = debés (pasivo). El caso real lo exige — un saldo de Splitwise cruza el cero todo el tiempo — y el sobregiro registrable ([ADR-0017](ADR-0017-sobregiro-registrable.md)) ya hace legal ese cruce. "Por cobrar/pagar" quedan como lecturas del signo, no como modelo.

3. **La deuda vive en la moneda del pacto**, que es la moneda nativa de la cuenta, elegida por deuda: "me debés los dólares" → cuenta USD (la devaluación es problema del deudor); "me debés los bolívares" → cuenta VES, que se comporta exactamente como cualquier cuenta en Bs — el overlay de Patrimonio la revaloriza a paralelo ([ADR-0016](ADR-0016-tasas-manuales-valoracion-patrimonio.md)) y el diferencial se realiza al cobrar. Una persona que debe en dos monedas son dos cuentas; la UI las agrupa bajo la persona.

4. **Los movimientos de deuda son piezas que ya existen; S3 no estrena factories.** Prestar y cobrar son **Transferencias** (−X +X en Cuentas, cero en Sobres: prestar no es un gasto, es cambiar efectivo por un "me deben" — los sobres no se enteran). Condonar es un **Gasto** contra la cuenta de la persona. Que te presten es una transferencia desde la cuenta de la persona (queda negativa, legal por ADR-0017). El saldo de Splitwise entra por el **ritual de Conciliación de C3** ([ADR-0019](ADR-0019-conciliacion-enrutada.md)): el usuario mira Splitwise, declara el neto de la persona, y la conciliación postea el ajuste. Cuando exista I1, su worker anexará el saldo observado y propondrá **exactamente el mismo evento** con un toque ([ADR-0008](ADR-0008-integraciones.md)) — la coexistencia con Splitwise es de diseño, no un parche.

5. **Deudas sigue siendo proyección de solo lectura, y la contradicción documental muere acá.** ADR-0002 listó a Deudas entre los contextos event-sourced; ADR-0005, del mismo día y con razón escrita (una sola fuente de verdad de saldo: el ledger), la definió como proyección. Se ratifica ADR-0005; la mención en ADR-0002 es una **errata** (los ADRs no se reescriben — quede anotado acá). La puerta de ADR-0005 sigue abierta: Deudas se promueve a contexto write el día que el splitting nativo reemplace a Splitwise.

**Alternativas rechazadas:**

- **Tercera dimensión "persona" en el ledger** — la respuesta honesta si las cuentas-por-persona no escalaran, pero toca la invariante de auto-balanceo (ADR-0006), exige migración de eventos y del Archivo de Respaldo (`format: 1` ya publicado), y el caso de uso real (decenas de personas, no miles) no lo justifica.
- **Entidad Persona/Contacto en el catálogo** — un catálogo nuevo con un solo consumidor; el precedente vigente para identificar terceros es el `source` de los ingresos (texto libre con sugerencias, U1-6) y nada pide más estructura todavía. Si S5 o el splitting nativo la piden, se extrae entonces.
- **Dos tipos de cuenta (por cobrar / por pagar)** — solo aportaría si cruzar el cero fuera ilegal, y el vaivén de Splitwise demuestra que cruzar el cero es el comportamiento correcto.
- **Todas las deudas en USD** — más simple, pero miente en el pacto "me debés los Bs": mostraría el nominal congelado cuando lo cobrable se devaluó. Ese "número que no cuadra con la realidad" es la causa raíz que el proyecto nació para matar.
- **Factory de gasto compartido ("pagué la cena, me deben la mitad")** — transacción mixta mitad gasto/mitad préstamo que ninguna factory produce; el splitting se queda en Splitwise (D8) y esta factory solo tiene sentido cuando se construya el reparto nativo.

**Consecuencia:**

- `docs/CONTEXT.md` estrena **Debt Account** (persona = etiqueta, signo único, moneda del pacto, segregación visual).
- **S3 queda desbloqueada de I1**: todo lo que escribe existe (Transferencia, Gasto, Conciliación) y el import de Splitwise es conciliación manual hasta que I1 la automatice. El bloqueo escrito en el mapa de PRDs era falso, como lo fue el de S1.
- El respaldo no se toca: las Cuentas de Deuda viajan en el Catálogo y sus movimientos en el log (`format: 1` intacto).
- Patrimonio muestra las deudas como **una línea neta** ("Deudas"); el detalle por persona vive en la pantalla de S3.
- S5 hereda la respuesta: su reporte "deuda por persona" lee esta proyección; "cliente" sigue siendo el `source` de texto libre — son conceptos distintos hasta que un caso real los una.
