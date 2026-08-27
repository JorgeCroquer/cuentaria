# ADR-0023 — Copia en la nube del usuario: sin servidor, sin cuenta, sin frase secreta

**Estado:** aceptada (2026-08-27) — nace de la sesión `grill-with-docs` de detalle de **F3**. **Supersede a [ADR-0004](ADR-0004-hosting-casi-gratis.md)** en el renglón de Supabase como destino de sync/backup, y a **[ADR-0009](ADR-0009-seguridad-e2ee.md)** en sus párrafos de E2EE de sincronización, Auth y recuperación de llave. No toca el cifrado local ([ADR-0014](ADR-0014-persistencia-f2-cifrado-local.md)) ni el respaldo manual ([ADR-0021](ADR-0021-respaldo-portable-en-claro.md)), que siguen intactos.

## Contexto

ADR-0004/0009 diseñaron F3 para un solo usuario: una base Supabase mía, login por email, blobs cifrados con una DEK envuelta por passphrase (Argon2id) y código de recuperación. En la sesión de F3 cambió la premisa del producto: **Cuentaria apunta a ser pública y gratuita** — primero yo, después amigos, después cualquiera —, y su autor **no puede ni quiere financiar ni custodiar datos ajenos**. Con esa premisa, el diseño anterior falla en tres puntos:

- Supabase free pausa a los 7 días y tiene 500 MB; con N usuarios el techo y la pausa los ve otro, y el costo cae en mí.
- Custodiar blobs ajenos, aunque no pueda leerlos, me hace responsable de su disponibilidad.
- La passphrase obligatoria convierte un olvido en pérdida total **para un extraño**, que no entiende ni aceptó ese modelo. Un respaldo que se pierde por olvido es peor que ninguno (mismo argumento de ADR-0021 §3).

## Decisión

1. **La copia vive en la nube del propio usuario** (*Cloud Copy*): la carpeta privada de aplicación de su Google Drive (`appDataFolder`, invisible para el usuario y para otras apps). Cuentaria **no tiene servidor, ni base, ni cuentas**: el usuario entra a *su* Google, no a nosotros. Costo cero a cualquier escala.

2. **La unidad que viaja es el Archivo de Respaldo de F4, entero, uno por aparato** (`<device_id>.ndjson`). Subir = escribir el archivo propio; bajar = leer los archivos de los otros aparatos y pasarlos por el `Restore` existente. No hay motor push/pull, ni deltas, ni cursores: la mezcla (duplicados ignorados por `event_id`, config LWW por `updatedAt`) ya la resolvió ADR-0021 §7. Techo: el archivo se reescribe entero cada vez; con años de uso son pocos MB.

3. **Sin frase secreta ni código de recuperación.** El dato queda protegido por la cuenta Google del usuario, un modelo que ya entiende. "Que ni Google pueda leerlo" pasa a ser una capa **opcional futura**, no la base: nada que olvidar, nada que perder. El "gancho" del producto queda literal y verificable: *no guardamos nada tuyo en ningún lado*.

4. **Automático, con cartel; nunca silencioso.** Al abrir la app y tras cada movimiento (agrupado) se sube lo propio y se baja lo ajeno. Una etiqueta permanente dice *"Copia en Drive: hace N"* o *"falló hace N: causa — tocá para reintentar"*. Se invierte ADR-0021 §4 (que rechazó lo automático) porque acá no hay carpeta que el usuario borre ni permiso de archivos que caduque callado; la condición de ADR-0021 — que el fallo se vea — se mantiene con la etiqueta.

5. **Optativo por diseño.** Un aparato que nunca conecta una nube funciona exactamente como hoy (local manda, ADR-0001) más el respaldo manual de F4, que sigue siendo la salida sin lock-in. La nube entra por un puerto y el dominio solo sabe si la carpeta está disponible o no.

6. **Dos historias independientes se juntan, no se fusionan.** Si un aparato con datos conecta una nube que ya tiene datos de otro, se avisa (*"se van a juntar; si creaste las mismas cuentas en ambos las vas a ver repetidas"*) y se sigue. Fusionar cuentas exigiría reescribir IDs en el log (rompe ADR-0002). Se mitiga por orden: conectar la nube es lo primero que la app ofrece en un aparato vacío.

7. **Transparencia en dos lugares:** la pantalla que conecta la nube dice en una frase qué se guarda, dónde y que nosotros no podemos verlo ni recuperarlo; y la política de privacidad pública dice lo mismo (Google la exige para aprobar la app).

8. **Puerto `CloudFolder`** en el paquete `backup` (que solo depende de `shared_kernel`): `list()`, `read(name)`, `write(name, content)`. Dos adapters — Google Drive (app) y en memoria (tests) — con **un contract test compartido**. Fallos del proveedor (sesión vencida, sin red, cuota) se traducen a un error del puerto para que la etiqueta lo muestre. iCloud, Dropbox o un servidor propio son adapters futuros del mismo puerto.

9. **Web queda fuera de F3**, con razón: el navegador no cifra en reposo (ADR-0014), hoy es target de desarrollo, y no hay demanda antes de que la app Android esté publicada. No se descarta: es el mismo puerto con un adapter web y restore en memoria, cuando alguien lo pida.

**Alternativas rechazadas:**

- **Supabase multi-usuario con cuotas** (lo que decían 0004/0009) — funciona técnicamente y el sobre criptográfico escala; se descarta porque pone el costo, la disponibilidad y la custodia en mí, para un producto que quiere ser gratuito y no custodiar nada.
- **Drive + passphrase obligatoria** (E2EE sobre el Drive del usuario) — máxima privacidad, a cambio de que un olvido borre los datos de alguien que no entendió el trato. Queda como capa opcional futura.
- **Motor push/pull por evento** — más eficiente en red; mucho más código y nada de lo actual lo necesita. El archivo entero alcanza.
- **Solo manual** (botón subir/bajar, como F4) — cero sorpresas, pero "otra cosa que acordarse" y diluye el valor de "si pierdo el teléfono no pierdo nada".
- **Fusión asistida de cuentas duplicadas** — reescribe el log.
- **Web read-mostly dentro de F3** (promesa de ADR-0014) — diferida, ver §9.

## Consecuencia

- **F3 deja de llamarse "Sync + Auth + E2EE + recuperación de llave"** y pasa a ser **"F3 — Copia en tu nube"**: F4 automático hacia Drive en las dos direcciones. Sin Auth propio, sin KEK/DEK, sin código de recuperación, sin proyecto Supabase, sin keep-alive. La única credencial en el código es el client ID de Google, público por diseño.
- **F3 no desbloquea I1.** Sin un servidor mío no hay "bandeja de entrada" donde un worker deje saldos ajenos. I1 pasa a leer Binance/Splitwise **desde el teléfono** cuando la app está abierta (los precios públicos siguen yendo como asset, ADR-0020); para el autor, un worker con sus propias llaves puede publicar a un lugar privado suyo como fuente alternativa del mismo puerto. Lo que se pierde es "que pase algo con el teléfono cerrado", que ADR-0008 ya prohíbe. A ratificar en el grill de I1.
- **Un saldo puede cambiar hacia atrás**: si B registró un gasto del lunes y A lo baja el jueves, el saldo de A del lunes cambia. Es correcto (cada transacción se auto-balancea sola, ADR-0006) y se acepta.
- La app estrena la dependencia de Google Sign-In + Drive API y un proyecto en Google Cloud (pantalla de consentimiento, verificación del scope `drive.appdata`) — trámite del autor, fuera del repo, **HITL** antes del drain.
- `docs/CONTEXT.md` estrena **Cloud Copy**; `Port / Adapter` deja de nombrar a Supabase. ADR-0004 y ADR-0009 quedan marcados como supersedidos en lo que este ADR cubre; sus párrafos de cifrado local y export siguen vigentes vía 0014 y 0021.
