# ADR-0003 — Dart everywhere, including integration workers

**Status:** accepted (2026-06-09)

A single language: **Dart** for the domain core (forced by ADR-0001, runs in the Flutter client) **and** for the integration workers. Workers are compiled **AOT** to native binaries and deployed as **scale-to-zero containers** (Cloud Run / Fly.io).

**Why:** workers are *I/O-bound* (waiting for Binance/BCV/explorers), so performance and memory differences between Dart and Node are irrelevant at this scale. What matters is the **coherence of a single language** and being able to **reuse core models** without re-modeling types. Dart AOT provides fast startup and low memory, and runs as a first-class ephemeral function (custom runtime on AWS Lambda, or container on Cloud Run/Fly).

**Rejected alternatives:**

- **TypeScript in edge functions (Supabase/Cloudflare):** less friction to the free tier and a more mature serverless ecosystem (JS SDKs for every API, more examples, more data for agents). Rejected for introducing a second language and forcing type re-modeling outside the core. Cost assumed by choosing Dart: sometimes there is no official Dart SDK (Binance/PayPal) and raw REST is called; and a container is built instead of pasting a managed function.

**Reversibility:** low-risk. An individual fetcher can be moved to TS later without touching the domain (workers are dumb: fetch → normalize → append observed fact).

**Hosting implication (feeds ADR-0004):** the "backend" is reduced to Dart scale-to-zero container(s) + Supabase Postgres. **There is no application web server → Vercel has no compute role**; at most it hosts the Flutter Web static build.
