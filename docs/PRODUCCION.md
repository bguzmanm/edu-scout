# Producción — EduScout

> Decisiones de arquitectura y despliegue en producción.
> Actualizado: 2026-09-12.

## 1. Objetivo

Pasar la app a producción con **costo $0**, dominio propio en `.cl`, deploy automatizado y scraping confiable, sin depender de la Mac del desarrollador.

## 2. Decisiones clave

| Tema | Decisión |
|---|---|
| Hosting | **Oracle Cloud Always Free**, todo en un solo VPS |
| Región | **Santiago, Chile** (`sa-santiago-1`) |
| Shape | ARM Ampere A1 (4 OCPU / 24 GB) |
| Dominio | `eduscout.cl` en **nic.cl** ($9.990 CLP/año, exento de IVA) |
| TLS | Let's Encrypt (certbot) vía nginx |
| Frontend | En el mismo VPS con nginx (no Vercel — un subdominio `*.vercel.app` resta seriedad). |
| Backend | NestJS + API + Swagger, con cron de scraping controlado por flag |
| Scraping | **En Oracle primero**; la Mac como plan B (fase 2b) |
| Deploy | **GitHub Actions → GHCR → pull en el VPS** (timer systemd) |
| Trigger | Push a `main` |
| BD | PostgreSQL 17 en Docker Compose |
| Secretos | Solo en `.env` del VPS (jamás en imágenes ni en GitHub) |
| Backups | `pg_dump` nightly → OCI Object Storage |
| Monitoreo | Ping HTTP gratis (UptimeRobot) |

## 3. Arquitectura

```
Visitantes ──► eduscout.cl (nic.cl) ──► nginx (HTTPS)
                                         ├── /   → Frontend (Next.js standalone)
                                         └── /api → Backend (NestJS)
                                                     │
                                      PostgreSQL 17 ◄─┼── (docker network interna)
                                                     │
                                  pg_dump nightly ──► OCI Object Storage

  Si Fase 2b (fallback): Mac con IP chilena ── Tailscale/SSH ──► PostgreSQL
     launchd 06:00 y 18:00 → scripts/scrape.ts
```

- El puerto **5432 nunca se expone al mundo**. Solo red interna de Docker + (si 2b) túnel Tailscale/SSH.

## 4. Scraping (decisión crítica)

- La IP del VPS de Santiago es geográficamente chilena → resuelve bloqueos por país.
- **Riesgo abierto**: reputación de IP de datacenter (AS31898 Oracle) ante Cloudflare/WAF; algunas bases geoIP podrían mapear el bloque a EE. UU.
- **Método de decisión (fase 2)**: scrape manual de prueba desde el VPS midiendo las 12 fuentes.
  - **2a** pasar todas (o casi todas) → cron nativo en Oracle (`SCRAPING_CRON_ENABLED=true`), la Mac queda fuera de operación. ✅
  - **2b** fallar alguna → esa fuente se scrapea desde la Mac (IP residencial) con túnel; cron desactivado para ella en Oracle.

## 5. Deploy automatizado (CI/CD)

- **Workflows por repo** (`eduscout-back`, `eduscout-front`), ambos en `push a main`.
- Build multi-stage → imagen → `ghcr.io/<org>/<repo>:<git-sha>` y `:latest`.
- **VPS**: `docker compose pull && up -d` vía **timer systemd** (cada ~5 min).
  - Se elige timer systemd sobre Watchtower para no montar `docker.sock` dentro de un contenedor.
- **Migrations**: el entrypoint del contenedor backend ejecuta `db:migrate` (idempotente) antes de `start:prod`.
- **Rollback**: apuntar `.env` del VPS a un tag anterior → `docker compose up -d`.

## 6. Cambios de código previstos

**Backend**
- Guard `SCRAPING_CRON_ENABLED` en `ScrapingScheduler` (ConfigService; default `true`).
- Dockerfile multi-stage (`oven/bun`).
- *(Solo 2b)* `scripts/scrape.ts` con `createApplicationContext` + LaunchAgent de macOS.

**Frontend**
- Build con `NEXT_PUBLIC_API_URL=''` (mismo origen vía nginx `/api`).
- Dockerfile multi-stage Next.js standalone.

**Docs**
- Este documento en `docs/PRODUCCION.md` (repo raíz).

*(Hecho)*: `jobCount` por fuente y filtro `?source=` en `/ofertas`.

## 7. Límites gratuitos Oracle (cuidado)

4 OCPU ARM + 24 GB RAM totales, ~200 GB disco, 10 TB salida. La shape A1 a veces sale **"sin capacidad"** → reintentar la creación de la VM.

## 8. Roadmap de implementación

1. **F0** Verificar disponibilidad e inscribir `eduscout.cl` (nic.cl).
2. **F1** Cuenta Oracle → VM ARM Santiago → Docker + Compose (Postgres + back + front + nginx) → migraciones + seed.
3. **F2** Scrape de prueba desde el VPS (12 fuentes) → **decisión 2a/2b**.
4. **F3** CI/CD: Dockerfiles, workflows push → GHCR, timer systemd, migrations en entrypoint.
5. **F4** Backups nightly + monitor UptimeRobot + TLS/DNS apuntando (certbot).
6. **F5** Corte: apagar ngrok/local, verificación final (buscador, conteos, Swagger).

## 9. Riesgos y mitigaciones

- **Punto único de falla** (1 VM) → backups + monitor + doc de recuperación.
- **IP de datacenter bloqueada** → la Fase 2 decide; fallback Mac (2b).
- **La Mac apagada** → solo aplica en 2b; mitigado con 2 corridas al día.

## 10. Decisiones pendientes

- Confirmar la disponibilidad de `eduscout.cl` en nic.cl (F0).
- Túnel fallback 2b: Tailscale (preferido) o SSH.