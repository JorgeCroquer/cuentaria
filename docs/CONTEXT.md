# Cuentaria — CONTEXT (Lenguaje de Arquitectura)

> Glosario del **lenguaje ubicuo de arquitectura** (no de implementación). Es la fuente de
> verdad del vocabulario que usamos en código, PRDs, issues y conversaciones con agentes.
> Complementa el glosario de **dominio** (ver `docs/DOMAIN.md` cuando se transfiera la nota 02).
> Las decisiones que justifican estos términos viven en `docs/adr/`.
>
> Se actualiza en línea a medida que las decisiones cristalizan. Si introduces un concepto
> nuevo o renombras uno, edítalo aquí primero.

## Lenguaje

**Core de dominio**
Paquetes Dart puros (hexagonal/DDD) que contienen los agregados, invariantes y lógica.
Corren en el cliente Flutter; reutilizables en un futuro servidor.
_Evitar_: "backend", "API" (esos son adaptadores, no el core).

**Cliente-autoritativo**
El dispositivo es la fuente de verdad; el almacén local (SQLite/Drift) manda. El servidor
solo sincroniza y respalda.
_Evitar_: "servidor-autoritativo" (rechazado, ver [ADR-0001](adr/ADR-0001-dominio-cliente-autoritativo.md)).

**Evento de dominio (command-sourced)**
Hecho inmutable producido al ejecutar un comando que pasó las invariantes de un agregado
(p. ej. un asiento del ledger). Es la unidad del event sourcing real.
_Evitar_: "registro", "fila" (esos son proyecciones).

**Hecho externo observado**
Observación inmutable ingerida de afuera (tasa BCV/paralelo, precio de mercado, saldo
on-chain). Append-only, **sin** agregado ni comando.
_Evitar_: tratarlo como evento de dominio.

**Proyección / read model**
Vista materializada recomputable desde el log de eventos (saldo por Cuenta, saldo por Sobre,
flujo de caja). Desechable y reconstruible.
_Evitar_: "tabla de saldos" como si fuera fuente de verdad.

**Puerto / Adaptador**
Frontera hexagonal: el core define puertos (interfaces); los adaptadores (Drift, Supabase,
Binance, BCV) los implementan. Supabase Postgres es un adaptador de persistencia/sync, nunca
el backend con lógica.

**Worker de integración**
Función serverless mínima **en Dart** (AOT, contenedor scale-to-zero) que ejecuta sync con
APIs externas (Binance, tasas, on-chain). Vive fuera del cliente por secretos/scheduling. Es
**tonto**: fetch → normaliza → anexa hecho observado; cero lógica de dominio. Ver
[ADR-0003](adr/ADR-0003-dart-en-todo.md).

**Scale-to-zero**
Modo de hosting donde la plataforma (Cloud Run / Fly.io) mantiene cero instancias sin tráfico
(≈ gratis) y enciende una por disparo. Costo: arranque en frío de 1–3 s, irrelevante para sync
en segundo plano.

**Shared kernel**
Paquete Dart con value objects puros compartidos por todos los contextos (`Money`,
`CurrencyCode`, `AccountId`, `EnvelopeId`, `EventId`). Sin comportamiento de ningún contexto.

**EventBus en proceso**
Puerto que entrega eventos de dominio entre módulos de forma **síncrona** dentro del cliente.
Contrato con forma de mensaje hoy; se sustituye por un bus de red al partir a microservicios.
Ver [ADR-0005](adr/ADR-0005-monolito-modular.md).

**Referencia por ID**
Un contexto referencia entidades de otro solo por su identificador (p. ej. Portafolio usa
`AccountId`), nunca importando su `domain/`. Frontera de bounded context.

**Proyección de solo-lectura (contexto)**
Contexto que no posee agregados; deriva vistas de otros (Patrimonio, Deudas en el MVP). Puede
orquestar emitiendo comandos al contexto dueño, pero no guarda saldo propio.

**Posting**
Línea de una transacción que afecta a una dimensión (Cuenta o Sobre):
`(dimensión, target_id, amount_native, currency, amount_usd, rate_ref?)`.

**Transacción auto-balanceada**
Transacción que por sí sola cumple `Σ usd[Cuenta] == Σ usd[Sobre]`. El dominio la exige;
garantiza el invariante global bajo cualquier orden de merge. Ver
[ADR-0006](adr/ADR-0006-ledger-cuenta-sobre.md).

**Costo real (snapshot)**
`amount_usd` congelado al momento de la transacción; no se recalcula. Verdad contable.
_Evitar_: recomputar el USD histórico desde la tasa actual.

**Valoración overlay / P&L no realizada**
Valor de hoy calculado al vuelo (`cantidad × tasa/precio actual`) mostrado en Patrimonio, sin
postear al ledger. La diferencia con el costo real es la P&L **no realizada**; se vuelve
**realizada** solo al convertir/vender/gastar.

## Relaciones

- Un **Comando** sobre un **Agregado** produce uno o más **Eventos de dominio**.
- Las **Proyecciones** se derivan del log de **Eventos de dominio** + **Hechos externos observados**.
- El **Core de dominio** depende de **Puertos**; los **Adaptadores** dependen del core
  (inversión de dependencias).

## Ambigüedades resueltas

- "Backend" se usaba para dos cosas: el **core de dominio** (vive en el cliente) y la **infra
  de sync/integración** (Supabase + workers). Resueltas como conceptos distintos.
- "Event sourcing en todo" se afinó: append-only en todo, pero **dos arquetipos** (evento de
  dominio vs hecho externo observado). Ver [ADR-0002](adr/ADR-0002-append-only.md).
