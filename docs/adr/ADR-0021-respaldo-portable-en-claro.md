# ADR-0021 — Respaldo portable en claro: el log solo no restaura, y el archivo sale sin cifrar

**Estado:** aceptada (2026-08-07) — nace de la sesión `grill-with-docs` de detalle de **F4**, la tercera de la Ola 2. **Refina a [ADR-0009](ADR-0009-seguridad-e2ee.md)** en su párrafo de backup/export; no lo supersede: E2EE de sincronización, passphrase, KEK y código de recuperación siguen siendo F3, intactos.

ADR-0009 (2026-06-09) afirmó que *"siendo event-sourced, exportar el log de eventos (NDJSON) = exportar todo (reconstruye el estado al reimportar)"*. **Esa frase es falsa contra el código de hoy**, y lo es desde que existen C1 y C2:

- `accounts` y `envelopes` son configuración **last-write-wins**, no eventos (`cuentaria_database.dart`). `CreateAccount` escribe el catálogo y *aparte* postea el Opening.
- `cascade_config` es un documento LWW de una sola fila (ADR-0015).
- Las `rate_observations` viven en **otra base, sin cifrar**, y son hechos observados, no eventos.

Replayar solo el log da saldos correctos colgando de UUIDs anónimos: sin nombres de cuenta, sin sobres propios, sin cascada. Restaura nada usable.

El otro supuesto de ADR-0009 —*"Supabase ya es el respaldo en la nube del log"*— tampoco aplica todavía: **F3 es Ola 3**. Hoy los datos viven en un solo sitio, cifrados con una llave del Keystore que **no sale del aparato por diseño** ([ADR-0014](ADR-0014-persistencia-f2-cifrado-local.md)), así que el backup de Android no salva: copia el archivo cifrado, no la llave. Perder el teléfono, resetearlo o **desinstalar la app para instalar un APK** borra todo. Lo último no es hipotético: es exactamente lo que se hace en cada verificación en dispositivo, y ya pasó tres veces. Con S1 dentro arranca el mes de dogfooding, y desde hoy sí hay algo que perder.

## Decisión

1. **El Archivo de Respaldo lleva las cuatro cosas, no solo el log.** Eventos + Catálogo (cuentas y sobres, con su `meta`: color, rol, Meta de Financiamiento) + Cascada + Serie de Tasas. Un renglón por cosa, cada uno etiquetado por su clase, más un renglón de encabezado con la versión del formato. **Un solo archivo**, no cuatro sueltos: cuatro archivos en Drive es una forma garantizada de perder uno y descubrirlo el día que hace falta.

2. **Formato NDJSON, y el evento viaja sin tocarse.** `events.payload` ya es JSON canónico de una línea —claves ordenadas, sin espacios, dinero como string de unidades mínimas (`EventCodec`)—, así que el envoltorio se pega por concatenación de texto y el evento respaldado es **byte-idéntico** al guardado. Cero serialización nueva en el camino del dinero, cero manera de que el respaldo difiera del original. Las tasas usan el mismo formato de línea que ya publica el worker de S1, de modo que reimportarlas es reusar `InMemoryRateFeed` + `SyncRateSeriesUseCase` con su dedup por `(currency, source, observedAt)` incluido — sin escribir mezcla nueva.

3. **El archivo sale en claro, y la app lo dice al compartir.** Este es el punto que contradice la postura de ADR-0009 y por eso está acá. Cifrarlo exige una contraseña que el usuario tiene que recordar; un respaldo que se pierde por olvido es **peor que ninguno**, porque da falsa tranquilidad. Y el `.csv` cifrado no lo abre Excel, con lo cual la mitad "para mirar" del principio 9 muere. La advertencia va **en el momento de compartir**, no enterrada en ajustes: el archivo lleva tus finanzas legibles, no lo mandes a un grupo.

4. **A mano, con cartel de antigüedad.** Nada de respaldo automático. Para sobrevivir a desinstalar, el archivo tiene que escribirse **fuera** de la carpeta de la app, y eso obliga a elegir carpeta con el selector del sistema y a guardar ese permiso: más plomería y más maneras de fallar en silencio. Un respaldo automático que falló callado es peor que no tenerlo. El "no me acuerdo" se resuelve con una etiqueta —*"último respaldo: hace N días"*, sello guardado en `app_meta`— no con un scheduler.

5. **Sale por la hoja de compartir del sistema; entra por el selector de archivos.** Un toque, sin permisos, y te deja mandarlo a Drive, a correo o **a vos mismo por WhatsApp**, que es el canal de respaldo que la gente ya usa todos los días. Los dos plugins elegidos cubren Android **e iOS**; en iPad la hoja de compartir necesita el punto de origen o falla solo ahí.

6. **Restaurar es todo o nada, con el error nombrado.** El archivo pasó por WhatsApp o Drive: puede llegar cortado o editado a mano. Se parsea y valida **todo** antes de escribir una sola fila; si un renglón no se entiende, no se toca la base y se dice cuál y por qué. Un import a medias deja saldos que no cuadran sin que el ledger pueda saberlo, y el usuario no tiene cómo distinguir "me faltan 2 movimientos" de "esto está mal".

7. **Restaurar sobre una base con datos ya es gratis y no se le pone freno.** `DriftEventStore.append` usa `INSERT OR IGNORE` por `event_id` y devuelve `false` sin excepción ante un duplicado; el catálogo ya mezcla por LWW sobre `updatedAt`. Restaurar es "anexar todo, lo repetido se ignora solo". No se agrega ni un modo "solo en aparato limpio" ni un diálogo de conflictos.

8. **El `.csv` es un segundo archivo, desechable, con un botón propio.** Una fila por **Posting** —fecha, tipo, memo, dimensión, nombre, monto nativo, moneda, monto USD, tasa usada, id de evento—, no una fila por movimiento: una Transacción del Ledger puede tocar una cuenta y varios sobres a la vez (una Distribución no toca ninguna cuenta), así que "una fila por movimiento" obliga a decidir cuál es *la* cuenta y *el* sobre de cada tipo y se rompe con el primero que no encaje. Botón separado para que respaldar no mande un CSV redundante cada vez y para que, al restaurar, el `.ndjson` sea siempre el único candidato.

**Alternativas rechazadas:**

- **Respaldo cifrado con contraseña** — coherente con ADR-0009 y protege el archivo en tránsito, a cambio de convertir el olvido de una contraseña en pérdida total de los datos. El activo a proteger acá es *no perder*, y el cifrado ataca el otro riesgo.
- **Cifrarlo con la llave del Keystore** — no existe: la llave no sale del aparato por diseño (ADR-0014), y un archivo que solo puede leer el teléfono que lo escribió no es un respaldo.
- **Solo el log de eventos (lo que decía ADR-0009)** — el export más chico y el más "puro" event-sourcing, pero restaura saldos sin nombres. Es la frase que este ADR corrige.
- **ZIP con cuatro archivos adentro** — separa limpio las cuatro clases, a cambio de una dependencia nueva y de esconder el contenido de un formato que se eligió por ser legible.
- **Respaldo automático a una carpeta elegida una vez** — resuelve el "no me acuerdo" de verdad, a cambio de permisos persistentes del sistema de archivos, una carpeta que el usuario puede borrar o mover, y fallas silenciosas justo en el camino que nadie mira.
- **Guardar en la carpeta de la app con `path_provider`** (ya es dependencia, cero plugins) — **inservible**: esos directorios se borran al desinstalar, que es el escenario exacto que motiva F4.
- **Importar todo lo válido y reportar lo descartado** — te salva algo el día que el archivo llegó cortado, y el reimport idempotente deja completarlo después; se descartó porque deja saldos a medias que la app no puede detectar, y el usuario prefiere un error claro a un número silenciosamente incorrecto.
- **Dejar las tasas afuera** — casi no duele (el `amount_usd` está congelado en el evento y `rate_ref` viaja como texto, `'36.50 VES/USD'`, no como referencia a la serie; las automáticas vuelven solas del release de GitHub). Se descartó igual: las manuales no viven en ningún otro lado y el costo de incluirlas es una clase de renglón más.
- **Una fila por movimiento en el CSV** — se lee como un extracto bancario, pero exige decidir cuál es la cuenta y el sobre de cada tipo de transacción y no tiene respuesta para las Distribuciones.

## Consecuencia

- **`docs/CONTEXT.md` estrena `Catalog`**, el término que faltaba para nombrar lo que el log no contiene, más `Backup File`, `Restore` y `Spreadsheet Export`.
- El **formato del archivo pasa a ser un contrato de compatibilidad** el día que exista un archivo en el Drive de alguien. Por eso el renglón de encabezado con versión, y por eso una versión desconocida rechaza el archivo entero en vez de adivinar.
- La app estrena **dos plugins** (hoja de compartir y selector de archivos) y su primera escritura de archivo fuera del sandbox.
- `app_meta` —hasta hoy solo `device_id`— estrena su segunda clave: el sello del último respaldo. Sigue siendo local-only y fuera del respaldo: identifica *este install*, no un hecho del usuario.
- **Nada de esto es iOS verificado.** Los plugins se eligieron para no cerrarle la puerta, pero no hay CI de iOS ni forma de compilar desde WSL; el criterio de dispositivo sigue siendo Android.
- Cuando llegue **F3**, el respaldo manual no se tira: sigue siendo la salida sin lock-in del principio 9. Lo que F3 le saca de encima es ser el *único* respaldo.
