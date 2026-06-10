# ADR-0009 — Seguridad: E2EE por sobre, Supabase Auth, cifrado local y export sin lock-in

**Estado:** aceptada (2026-06-09)

**Cifrado de la sync (E2EE por sobre / envelope encryption):** una **DEK** aleatoria por
usuario cifra los payloads de eventos. La DEK se **envuelve** con una KEK derivada de la
**passphrase** (Argon2id) y la versión envuelta se sube a Supabase como blob opaco; además se
genera **una vez** un **código de recuperación** offline que envuelve la DEK por segunda vía.
Supabase guarda solo blobs opacos (no hace lógica → E2EE es casi gratis aquí, ADR-0001).

**Recuperación ante borrado de app:** el **log cifrado permanece en Supabase**; reinstalar y
escribir passphrase (o usar el código) **desenvuelve la DEK y restaura** — borrar la app no
pierde datos. Riesgo irreductible del E2EE: perder passphrase **y** código = datos
irrecuperables (el servidor no puede leerlos). Mitigación de producto: onboarding que obliga a
guardar el código; a futuro, guardar la llave envuelta en llavero de iCloud/Google.

**Consideración futura (SaaS):** la app es solo para un usuario ahora (probar valor), pero
podría venderse (suscripción/publicidad). El modelo de sobre **escala a multi-usuario sin
cambios**: cada usuario trae su propio sobre. Decisión tomada barata hoy para no bloquear ese
futuro.

**Auth:** una sola cuenta con **Supabase Auth** (email + magic link/password), que integra con
RLS de forma natural. **Clerk descartado** (su valor es multi-usuario/social/orgs; dependencia
que no se gana su lugar para un usuario).

**Datos locales:** SQLite cifrada en reposo con **SQLCipher** en nativo (Android/desktop) +
bloqueo biométrico/app-lock. **Web = modelo de amenaza más débil** (storage del navegador no se
cifra bien): documentado; la web puede quedar como vista más ligera.

**Backup/export (principio 9, sin lock-in):** al ser event-sourced, **exportar el log de
eventos (NDJSON) = exportar todo** (reconstruye el estado al reimportar), más CSV de
transacciones/saldos para humanos. Formato abierto y documentado. Supabase ya es el backup en
nube del log.
