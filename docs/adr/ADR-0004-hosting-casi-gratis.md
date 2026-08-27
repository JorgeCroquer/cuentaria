# ADR-0004 — "Almost free" hosting topology

(Supabase free + GitHub Actions + Cloudflare Pages)

**Status:** accepted (2026-06-09) — **partially superseded by [ADR-0023](ADR-0023-copia-en-la-nube-del-usuario.md)** (2026-08-27)

The MVP "backend" is:

- **DB + sync/backup:** **Supabase free** (500 MB Postgres, RLS tied to the single user). The Flutter client syncs **directly** via Dart SDK; there is no application server in the middle. The free tier pauses the project after **7 days of inactivity** — mitigated by daily use and the rates worker acting as a *keep-alive*.
- **Integration workers:** **GitHub Actions scheduled workflows** run the Dart AOT binary on a schedule, write to Supabase, and spin down. ~Free (2000 mins/month in private repo); a rates/balances fetch a couple of times a day doesn't come close to that ceiling and tolerates the 5–30 min delays of GitHub's cron.
- **Static Flutter Web:** **Cloudflare Pages** (free).

**Why:** because the client syncs directly to Supabase, workers only need to be **scheduled fetchers** → there's no need to host any always-available container. GitHub Actions provides cron + Dart binary execution with zero proprietary infra.

**Rejected / deferred alternatives:**

- **Cloud Run scale-to-zero from day 1:** capable of HTTP on-demand (refresh rate, OAuth callbacks), but demands a GCP account with a card and more setup. **Deferred**: will be adopted only when a real on-demand need arises (e.g. PayPal OAuth callback). The Dart container from ADR-0003 remains valid; only what triggers it changes.
- **Vercel:** **eliminated from the design** — there's no application compute to host; Cloudflare Pages covers the static site.

**Consequence / limits to watch:** 500 MB of Postgres and the inactivity pause are the ceilings to monitor; migrating to Supabase Pro or another Postgres is straightforward if exceeded (the domain doesn't depend on Supabase, it's an adapter — ADR-0001).
