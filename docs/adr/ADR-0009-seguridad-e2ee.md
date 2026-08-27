# ADR-0009 — Security: Envelope E2EE, Supabase Auth, local encryption and lock-in-free export

**Status:** accepted (2026-06-09) — **partially superseded by [ADR-0023](ADR-0023-copia-en-la-nube-del-usuario.md)** (2026-08-27)

**Sync encryption (Envelope E2EE / envelope encryption):** a random **DEK** per user encrypts event payloads. The DEK is **wrapped** with a KEK derived from the **passphrase** (Argon2id) and the wrapped version is uploaded to Supabase as an opaque blob; additionally, an offline **recovery code** is generated **once** that wraps the DEK a second way. Supabase only stores opaque blobs (no logic → E2EE is almost free here, ADR-0001).

**Recovery upon app deletion:** the **encrypted log remains in Supabase**; reinstalling and entering the passphrase (or using the code) **unwraps the DEK and restores** — deleting the app does not lose data. Irreducible E2EE risk: losing passphrase **and** code = unrecoverable data (the server cannot read it). Product mitigation: onboarding that forces saving the code; in the future, saving the wrapped key in iCloud/Google Keychain.

**Future consideration (SaaS):** the app is single-user for now (to prove value), but could be sold (subscription/ads). The envelope model **scales to multi-user without changes**: each user brings their own envelope. Decision made cheaply today to avoid blocking that future.

**Auth:** a single account with **Supabase Auth** (email + magic link/password), which integrates with RLS naturally. **Clerk discarded** (its value is multi-user/social/orgs; a dependency that doesn't earn its place for a single user).

**Local data:** SQLite encrypted at rest with **SQLCipher** natively (Android/desktop) + biometric/app-lock. **Web = weaker threat model** (browser storage doesn't encrypt well): documented; web can remain as a lighter view.

**Backup/export (principle 9, no lock-in):** being event-sourced, **exporting the event log (NDJSON) = exporting everything** (reconstructs state upon reimport), plus CSV of transactions/balances for humans. Open and documented format. Supabase is already the cloud backup of the log.
