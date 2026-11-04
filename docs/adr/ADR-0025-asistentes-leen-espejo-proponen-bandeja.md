# ADR-0025 — Asistentes de IA: leen un espejo visible y proponen en una bandeja, nunca escriben

**Estado:** aceptada (2026-11-03) — nace de la sesión `grill-with-docs` de la feature "la IA lee y escribe en Cuentaria" (feedback de dogfooding, punto 4, con el punto 3 montado encima). **Refina** a [ADR-0008](ADR-0008-integraciones.md) (extiende "integraciones proponen, no escriben" a los asistentes) y a [ADR-0023](ADR-0023-copia-en-la-nube-del-usuario.md) (suma una carpeta **visible** junto a la Copia en la nube, que sigue invisible e intacta). No supersede a ninguno.

## Contexto

Tras dos meses de uso, el autor exporta a mano el Archivo de Respaldo y se lo pasa a Claude para pedir recomendaciones, diagnosticar errores de captura y hacer preguntas sobre su estado. Quiere dos cosas: que Claude o Gemini **lean** sin ese paso, y que puedan **cambiar** cosas (registrar un movimiento a partir de un screenshot o una narración, corregir un error, ajustar la Cascada).

Tres restricciones condicionan el diseño:

- **Sin servidor ni custodia** (ADR-0023). Meter un LLM dentro de la app exigiría una API key o un servidor.
- La Copia en la nube vive en `appDataFolder` (scope `drive.appdata`), que **ningún conector de terceros ve**.
- Con el scope `drive.file`, la app **solo ve los archivos que ella misma creó** (o que el usuario eligió con el Picker). Un archivo nuevo creado por un asistente le resulta invisible.

## Decisión

1. **Assistant Mirror: una copia legible del estado, en una carpeta visible del Drive del usuario**, con scope `drive.file`.
   - **Uno por usuario, no uno por aparato.** Lo escribe el último aparato que sincronizó, porque tras el pull de la Copia en la nube todos convergen.
   - **Contiene dos piezas:**
     - el **Archivo de Respaldo sin Observaciones de Tasa**, que es lo que más pesa y no hace falta para diagnosticar: cada evento ya trae su `amount_usd` congelado y su `rate_ref`;
     - un **Resumen** como Google Doc, con saldos por Cuenta y Sobre con nombre e ID, la tasa de valoración, la fecha de corte y los movimientos recientes.
   - **Por qué un Doc:** Gemini solo lee Docs, Sheets, Slides y PDF, no `.json` ni `.ndjson`.
   - **No restaura nada y la app nunca lo lee de vuelta.**

2. **El espejo es optativo y se activa explícitamente.**
   - Tiene su propio interruptor en la pantalla de la Copia en la nube.
   - El scope `drive.file` se pide al encenderlo, con una advertencia: cualquier asistente con acceso a tu Drive podrá leer tus finanzas.
   - Al apagarlo, la app borra los archivos que creó.
   - Nosotros seguimos sin custodiar nada. La exposición es una decisión del usuario, avisada en el momento de tomarla.

3. **Los asistentes nunca escriben: dejan Assistant Proposals en una bandeja.**
   - La **Bandeja** es un único `.ndjson` **creado por la app** (la restricción de `drive.file` impide que la cree el asistente). Lleva una propuesta por línea, cada una con su `id` y su `schema: N`.
   - Todo lo que está en la Bandeja está pendiente. Al aceptar o descartar una propuesta, la app la quita del archivo.

4. **Siete clases de propuesta. Pueden modificar lo que ya existe, nunca crear.**
   - **Movimientos:** Gasto, Ingreso, Mover, y Reverso de un evento existente.
   - **Saldo observado de una Cuenta:** entra al ritual de Conciliación de ADR-0019, que enruta o absorbe el delta como siempre.
   - **Configuración:**
     - **Cascada** completa, que indica sobre qué versión se basó y se marca *vencida* si la Cascada cambió desde entonces;
     - **Meta de Financiamiento** de un Sobre existente.
   - **Prohibido:** crear, renombrar o archivar Cuentas y Sobres, porque crear es lo que produce los duplicados irreparables de ADR-0023 §6. Tampoco Distribución, Apertura ni Ajuste directo.

5. **Aceptar una propuesta abre la captura o el editor de siempre, prellenados.** No hay un segundo camino de escritura: los guards, la valoración (ADR-0018) y la conciliación enrutada son los mismos que en una captura a mano.

6. **Contrato de las propuestas:**
   - **Referencias por ID**, obligatorias y copiadas del espejo. El nombre es solo una etiqueta; un ID desconocido invalida esa propuesta a la vista.
   - **Monto decimal** en la moneda nativa de la Cuenta. Mover lleva los dos montos observados.
   - **`occurredAt` obligatoria.**
   - **Nunca `amount_usd`.**
   - **Validación por línea:** una línea inválida o de versión desconocida se rechaza sola y no tapa a las demás. Es lo contrario de la regla todo-o-nada del Restore, porque aquí cada línea es independiente.

7. **Idempotencia sin estado nuevo.** El `EventId` del movimiento aceptado se deriva del `id` de la propuesta (UUIDv5). Aceptar la misma propuesta en dos aparatos choca con el `INSERT OR IGNORE` por `event_id` (ADR-0021 §7). Una propuesta cuyo evento derivado ya está en el log se muestra como "ya aplicada".

8. **Las instrucciones para el asistente las genera la app**, dentro del Resumen, en cada sync: el esquema, un ejemplo por clase, las reglas y la versión. Así nunca quedan desfasadas respecto de la versión instalada.

9. **Escribe Claude; Gemini solo lee.** Verificado el 2026-11-03: el conector de Drive de Claude edita archivos existentes (`update_file`). Gemini en Android no tiene una vía documentada para editar un archivo de Drive, y los Docs que crea no quedan en una carpeta elegida ni son visibles para la app con `drive.file`.

10. **Antes de construir, se valida el supuesto de `drive.file`** (trámite HITL en la consola de Google Cloud). Hay que confirmar tres cosas:
    - que Claude edita la Bandeja creada por la app y la app lee el cambio;
    - que un segundo aparato ve los archivos que creó el primero;
    - que Claude lee el `.ndjson`.

## Alternativas rechazadas

- **Compartir o pegar en ambas direcciones** (el respaldo hacia la IA y un bloque de propuesta de vuelta hacia la app). Funciona con cualquier LLM, no necesita scope nuevo y no expone nada en claro. Se rechazó porque conserva justo el paso manual que motiva la feature. Si el supuesto de `drive.file` falla, es el plan B: mismo esquema, otro transporte.
- **Un archivo por propuesta.** Elimina la carrera de la Bandeja, pero con `drive.file` la app no ve archivos que no creó.
- **Que la IA escriba nombres en vez de IDs.** Es más natural para un LLM, pero ambiguo (dos "Efectivo") y obliga a resolver por aproximación. El espejo ya le da los IDs.
- **Montos en unidades mínimas o con `amount_usd` propuesto.** Un factor 100 mal puesto es el error clásico de un LLM, y el costo congelado lo decide la app, no un tercero.
- **Escritura de Gemini mediante MCP propio.** Exige un servidor (choca con ADR-0023) y hoy está limitada a EE. UU., mayores de edad, cuentas personales y uso en inglés.
- **Android AppFunctions.** Gemini solo las invoca en apps aceptadas en el programa de acceso anticipado de Google, no en cualquier app.
- **Espejo uno por aparato**, como la Copia en la nube. Obligaría al asistente a juntar archivos que la app ya juntó.
- **Espejo como respaldo completo, con tasas.** Pesa más, y las tasas no aportan nada al diagnóstico.
- **Permitir que el asistente cree Cuentas o Sobres.** Produce duplicados que el log append-only no puede fusionar.

## Consecuencias

- `docs/CONTEXT.md` incorpora **Assistant Mirror** y **Assistant Proposal**. Este último nombre evita el choque con *Distribution Proposal*.
- La app suma el scope `drive.file`, pedido de forma incremental. Con la pantalla de consentimiento en modo Testing basta un clic. Al publicar la app hay que confirmar que es un scope no sensible.
- **El esquema de la propuesta pasa a ser un contrato de compatibilidad** desde el día en que exista una Bandeja en el Drive de alguien. Por eso lleva `schema: N` por línea.
- **Limitación aceptada:** si el asistente reescribe la Bandeja mientras la app quita una línea resuelta, se puede perder una propuesta o reaparecer una ya resuelta. El daño es visible y barato con un solo usuario. Si llega a doler, la solución es versionar la Bandeja.
- **El espejo refleja el estado de la última vez que se abrió la app.** No hay escritura en segundo plano, igual que en la Copia en la nube.
- La feature 3 (detectar movimientos desde un screenshot o una narración) **no necesita un LLM dentro de la app**: entra como Assistant Proposal. La vía por APIs de proveedores sigue siendo I1.
