# ADR-0008 — Integraciones: lo observado propone conciliación, nunca escribe al ledger

**Estado:** aceptada (2026-06-09)

**Patrón:** cada Proveedor tiene un adaptador de sync **opcional** detrás de un puerto
(polimórfico, principio 5). Los workers son tontos (ADR-0003/0004) y todo lo externo entra como
**hecho observado** (ADR-0002).

**Interacción con el ledger (decisión clave):** cuando un saldo observado (p. ej. Funding de
Binance) difiere del saldo del ledger, el worker **nunca escribe al ledger**. Anexa el hecho;
el cliente muestra el **diff** y ofrece una **conciliación de un toque** que postea el evento
Conciliación/Ajuste (Cuenta + Sobre "Ajustes", auto-balanceada). El usuario confirma.

**Por qué:** respeta *cliente-autoritativo* (ADR-0001), *conciliación como ritual* (principio
8) y *automatización honesta: menos acciones, no cero* (principio 6). Evita ajustes erróneos
por lecturas parciales/temporales de la API.

**Secretos:** claves API **solo-lectura** (Binance read sin permisos de retiro, token
Splitwise, OAuth PayPal) en **GitHub Actions encrypted secrets**, nunca en el cliente.

**Alcance MVP de integraciones (roadmap, no arquitectura):** (1) Binance read + Tasas primero;
(2) on-chain/Ledger (direcciones públicas + explorers + precios) y Splitwise (saldo neto por
persona → ajuste a cuenta por cobrar/pagar) después; (3) PayPal manual por ahora (API parcial).
Splitwise y PayPal con callback OAuth podrían motivar adoptar Cloud Run (diferido en ADR-0004).
