# ADR-0005 — Monolito modular: estructura, integración entre módulos y mapa de contextos

**Estado:** aceptada (2026-06-09)

**Estructura.** Monorepo **Melos**, un paquete Dart por bounded context. Cada paquete es
internamente hexagonal: `domain/` (agregados, eventos, value objects, puertos), `application/`
(handlers de comando/query), `infrastructure/` (adaptadores: Drift, Supabase, APIs externas).
Un paquete **`shared_kernel`** con solo value objects puros compartidos (`Money`,
`CurrencyCode`, `AccountId`, `EnvelopeId`, `EventId`, marcas de tiempo) — sin comportamiento de
ningún contexto.

**Integración entre módulos.** Solo dos vías: **eventos de dominio publicados** y una **API de
aplicación delgada** (comandos/queries). Prohibido importar el `domain/` de otro contexto; se
referencian **por ID**. Los eventos usan un **`EventBus` en proceso con despacho síncrono**: el
contrato ya tiene forma de mensaje, pero sin consistencia eventual dentro del cliente de un
solo usuario. **Partir a microservicios = sustituir el bus en-proceso por uno de red, sin tocar
contratos.** Enforcement de fronteras con límites de paquete + reglas de lint de imports.

**Alternativas de integración rechazadas:**

- *Bus asíncrono en proceso:* introduce consistencia eventual y reintentos que el cliente no
  necesita aún.
- *Llamadas síncronas directas entre app-services:* más simple hoy pero acopla por llamada y
  exige reescribir integraciones al partir.

**Mapa de contextos (MVP).**

| Contexto | Rol | Posee agregados |
|----------|-----|-----------------|
| **Contabilidad / Cash** | Núcleo write: agregados **Cuenta** (tipos: líquida, por cobrar/pagar, activo-diferido) y **Sobre**, log de eventos, todos los tipos de transacción (incl. Conciliación y P2P/FX) | Sí |
| **Tasas** | Transversal: hechos observados (BCV, paralelo) + serie temporal; publica `RateObserved` y un read-model de serie consultable por puerto | No (hechos observados, ADR-0002) |
| **Portafolio** | Write propio: holdings, valoración Nivel 1, ingresos pasivos; datos listos para Nivel 2 (PNL/cost basis) | Sí |
| **Patrimonio** | **Proyección de solo-lectura**: "dónde está el dinero" y patrimonio neto en USD sobre Cuentas + Tasas + holdings. Orquesta el ritual de conciliación emitiendo comandos a Contabilidad | No |
| **Deudas** | **Proyección de solo-lectura**: balance por persona sobre cuentas por cobrar/pagar de Contabilidad. Saldos netos de Splitwise se importan como ajustes a esas cuentas | No (MVP) |

**Por qué Patrimonio y Deudas como proyección:** evita duplicar el concepto de saldo (causa
raíz del "no cuadra" original) → **una sola fuente de verdad de saldo: el ledger**. No rompe el
objetivo de microservicios: Deudas puede **promoverse** a contexto write el día que se
construya el splitting nativo que reemplace Splitwise (diferido).
