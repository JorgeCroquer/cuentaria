# ADR-0011 — Conciliación operativa: la tolerancia configurable gobierna la fricción

**Estado:** aceptada (2026-06-09)

**"Conciliado":** una Cuenta está conciliada en T si su saldo de ledger == saldo real dentro de
una **tolerancia**. El saldo real lo **propone la integración** en cuentas con API (ADR-0008) o
lo **declara el usuario** en bancos VE/efectivo.

**Comportamiento:** conciliar **siempre lleva el ledger al saldo real** vía evento
Conciliación/Ajuste (Cuenta + Sobre "Ajustes", auto-balanceado, ADR-0006), absorbiendo el
buffer del hábito de redondeo conservador. La **tolerancia gobierna la fricción, no si se
ajusta**:

- diferencia **dentro de tolerancia** → conciliación de un toque / auto-aceptada;
- diferencia **fuera de tolerancia** → se **avisa para revisar** antes (quizá faltó registrar
  un movimiento real en vez de absorberlo).

**Tolerancia configurable:** por Cuenta, con un **default global sobreescribible** por cada
Cuenta (ej. Bs: redondeo al entero / umbral pequeño; USD: ~$0.50).

**Ritmo y recordatorios:** **cadencia por Cuenta** (semanal para uso intenso como BdV; mensual
para frío/poco uso) + on-demand; cada Cuenta lleva `última conciliación`. Recordatorio
**suave**: badge/lista de "cuentas por conciliar" según cadencia y fecha de última
conciliación; notificación opcional, sin acoso (la disciplina es el riesgo).

**Por qué:** alinea con *automatización honesta: menos acciones, no cero* (principio 6) y
*conciliación como ritual* (principio 8), sin imponer fricción sobre el redondeo cotidiano.
