# ADR-0014 — F2 local persistence: native-only encrypted store, web deferred, local key separate from the sync DEK

**Status:** accepted (2026-06-15) — **refines [ADR-0009](ADR-0009-seguridad-e2ee.md)** for the F2 (local persistence) milestone; does not supersede it.

F2 makes the local store the durable source of truth (Drift + SQLCipher, ADR-0001/0002). Two questions ADR-0009 left open for F2 are resolved here.

## 1. Native-only encrypted store; web persistence deferred to F3

The encrypted Drift/SQLCipher store ships on **native (Android primary)**. The **web target gets no durable store in F2**: it stays the F1 shell (still compiles and deploys to GitHub Pages) wired to the **in-memory (ephemeral) adapters**, and becomes data-bearing only at **F3** (read-mostly view via encrypted sync).

**Why:** **SQLCipher does not exist on web** — Drift's WASM SQLite persists to IndexedDB with no transparent encryption, and any key would live readable inside the browser (ADR-0009's "weakest threat model"). Moreover, **sync is F3**: until then the web has no way to obtain the phone's data, so a web store would be an **isolated, plaintext silo of financial data** — all cost, no value. The product thesis is mobile offline capture (ADR-0001); the phone is primary, and a PC-only user typing finances into a browser store is not the target.

## 2. Local-at-rest key separate from the sync DEK

F2 must encrypt the local DB **from day one** (retrofitting plaintext→encrypted later is a painful migration; shipping plaintext "until F3" violates ADR-0009). But passphrase→KEK→DEK + recovery code are scoped to F3. So F2 generates a **random 256-bit, per-install SQLCipher key stored in OS secure storage** (Android Keystore / iOS Keychain). It only encrypts the local file and **never leaves the device**. The **sync DEK, passphrase, KEK and recovery code remain entirely F3**, layered on top.

**Rejected alternatives:**

- **drift-wasm/IndexedDB persistence on web now** — plaintext financial data in an isolated silo with no safe data source before F3. All cost, no value.
- **Remove the web target** — walks back the F1 decision to keep web as the "PC of the MVP"; keeping it as a shell costs nothing.
- **Unify the SQLCipher key with the future sync DEK** — couples F2 to F3's recovery architecture and forces the key to be recoverable/exportable prematurely. Layering at-rest encryption (local) separately from transport E2EE (sync) is the standard design and keeps F2 minimal.
- **Biometric / app-lock in F2** — deferred; the key is already protected by the OS keystore, and the lock is a thin UX gate (U1/product or a later minor slice).

## Consequence

- At-rest encryption (F2) and transport E2EE (F3) are **independent layers**. On reinstall+recovery (F3), the fresh local DB uses a **new local key**; the recovered DEK only decrypts server blobs.
- **Web has no durable storage until F3** — accepted, given the mobile-first thesis.
- The Drift adapter is **platform-agnostic** (it implements C1's `EventStore`/`CatalogRepository` ports): desktop and iOS are addable later by injecting an encrypted `QueryExecutor`, with no rewrite (ADR-0001).
- F2 owns one new local-only artifact — the per-install SQLCipher key in secure storage — plus a `device_id` in a non-synced `app_meta` table.
