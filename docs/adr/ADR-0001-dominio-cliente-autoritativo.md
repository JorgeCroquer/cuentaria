# ADR-0001 — Dominio cliente-autoritativo, offline-first

**Estado:** aceptada (2026-06-09)

El dominio autoritativo (el que garantiza los invariantes, p. ej. `Σ Cuentas(USD) == Σ
Sobres(USD)`) corre **en el cliente Flutter** como paquetes Dart puros (hexagonal/DDD/CQRS). El
almacén local (SQLite/Drift) es la **fuente de verdad**; Supabase Postgres actúa como destino
de **sync + backup**, no como backend con lógica. Las integraciones (Binance, tasas, on-chain)
corren en **workers serverless mínimos**.

**Por qué:** es una app de **un solo usuario** con necesidad de **captura móvil offline**. Un
dominio residente en el cliente es lo más barato (sin servidor siempre encendido), hace el
offline-first natural, y mantiene el dominio puro y portable.

**Alternativas rechazadas:**

- **Servidor-autoritativo (monolito propio):** DDD más "de libro" y separación a microservicios
  más directa, pero exige hosting casi-siempre-encendido (no gratis-para-siempre) y *aun así*
  requiere capa de sync para offline. Rechazada por costo y por no aportar al MVP de un solo
  usuario.
- **Supabase-as-backend (lógica en PostgREST/RLS/edge):** infra más barata y MVP más rápido,
  pero dispersa el dominio en SQL/RLS, intestable y difícil de partir. Rechazada por romper
  hexagonal/DDD/CQRS.

**Consecuencia:** "listo para microservicios" significa hoy **higiene de módulos** (bounded
contexts como paquetes Dart con fronteras explícitas), no topología desplegada. Izar un módulo
a un servidor es un trabajo futuro habilitado, no hecho.
