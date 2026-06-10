# ADR-0002 — Append-only en todo el sistema, con dos arquetipos de evento

**Estado:** aceptada (2026-06-09)

Todo el almacenamiento es **append-only** (auditoría y *time-travel* uniformes), pero se
distinguen **dos arquetipos**:

1. **Evento de dominio (command-sourced):** Contabilidad/Cash, Deudas y Distribución usan
   **event sourcing de verdad** — agregado, comando, validación de invariantes y proyecciones.
   El ledger es un log de eventos inmutables; la *Conciliación/Ajuste* es un evento de reverso,
   no una edición.
2. **Hecho externo observado (log de ingesta, sin agregado):** Tasas, precios de mercado y
   saldos on-chain (Binance/Ledger) se anexan como observaciones inmutables que alimentan
   proyecciones, **sin** comando ni invariante.

**Por qué:** la contabilidad es naturalmente append-only (se revierte, no se borra), lo que da
auditoría, time-travel (reporte "patrimonio en el tiempo") y P&L no realizada como proyección,
y vuelve **trivial el merge multi-dispositivo** (dos logs se fusionan por orden de eventos).
Pero montarle agregado/comando a datos que solo se *observan* (tasas, precios) sería ceremonia
sin retorno.

**Primitiva de sync:** push/pull del log de eventos hacia Supabase Postgres; merge por orden de
eventos. La **config mutable** (metadatos de Sobres, settings) usa *last-write-wins* por fila.

**Read models / proyecciones:** saldo por Cuenta, saldo por Sobre, flujo de caja por
fuente/cliente, progreso de Sobres vs. meta — todos recomputables desde el log.

**Consecuencia:** se asume el costo de mantener proyecciones y de versionar el esquema de
eventos.
