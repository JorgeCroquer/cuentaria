# ADR-0004 — Topología de hosting "casi gratis"

(Supabase free + GitHub Actions + Cloudflare Pages)

**Estado:** aceptada (2026-06-09)

El "backend" del MVP es:

- **DB + sync/backup:** **Supabase free** (500 MB Postgres, RLS atado al único usuario). El
  cliente Flutter sincroniza **directo** vía SDK Dart; no hay servidor de aplicación en medio.
  El free tier pausa el proyecto tras **7 días sin actividad** — mitigado por el uso diario y
  por el worker de tasas que actúa de *keep-alive*.
- **Workers de integración:** **GitHub Actions scheduled workflows** corren el binario Dart AOT
  en horario, escriben a Supabase y se apagan. ~Gratis (2000 min/mes en repo privado); un fetch
  de tasas/saldos un par de veces al día no roza ese techo y tolera los retrasos de 5–30 min
  del cron de GitHub.
- **Flutter Web estático:** **Cloudflare Pages** (free).

**Por qué:** como el cliente sincroniza directo a Supabase, los workers solo necesitan ser
**fetchers programados** → no hace falta hospedar ningún contenedor siempre-disponible. GitHub
Actions da cron + ejecución del binario Dart con cero infra propia.

**Alternativas rechazadas / diferidas:**

- **Cloud Run scale-to-zero desde el día 1:** capaz de HTTP on-demand (refrescar tasa,
  callbacks OAuth), pero exige cuenta GCP con tarjeta y más setup. **Diferida**: se adopta solo
  cuando aparezca una necesidad on-demand real (p. ej. callback OAuth de PayPal). El contenedor
  Dart de ADR-0003 sigue válido; cambia solo quién lo dispara.
- **Vercel:** **eliminado del diseño** — no hay cómputo de aplicación que hospedar; Cloudflare
  Pages cubre el estático.

**Consecuencia / límite a vigilar:** 500 MB de Postgres y la pausa por inactividad son los
topes a monitorear; migrar a Supabase Pro o a otro Postgres es directo si se exceden (el
dominio no depende de Supabase, es un adaptador — ADR-0001).
