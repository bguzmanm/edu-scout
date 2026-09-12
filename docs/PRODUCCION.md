# Producción — EduScout

> Decisiones de arquitectura y despliegue en producción.
> Actualizado: 2026-09-12.

## 1. Objetivo

Pasar la app a producción con **costo $0**, dominio propio en `.cl`, deploy automatizado y scraping confiable, sin depender de la Mac del desarrollador.

## 2. Decisiones clave

| Tema | Decisión |
|---|---|
| Hosting | **Oracle Cloud Always Free**, todo en un solo VPS |
| Región | **Santiago, Chile** (`sa-santiago-1`, un solo AD) |
| Shape | ARM Ampere A1 (2 OCPU / 12 GB iniciales; tope free = 4 OCPU / 24 GB) |
| VM | **Provisionada con Terraform** (`deploy/terraform/`) + loop de reintentos por "out of host capacity" |
| Dominio | `eduscout.cl` en **nic.cl** ($9.990 CLP/año); DNS delegado a **Cloudflare** (frida/javier) |
| Cloudflare | Modo **DNS only** (gris); registro A cuando exista la IP del VPS |
| TLS | Let's Encrypt (certbot) vía nginx (`deploy/nginx.conf`, puerto 80 → ACME) |
| Frontend | En el mismo VPS con nginx (no Vercel — un subdominio `*.vercel.app` resta seriedad). |
| Backend | NestJS + API + Swagger, con cron de scraping controlado por flag |
| Scraping | **En Oracle primero**; la Mac como plan B (fase 2b) |
| Deploy | **GitHub Actions → GHCR → pull en el VPS** (timer systemd cada 5 min) |
| Trigger | Push a `main` |
| BD | PostgreSQL 17 en Docker Compose |
| Secretos | Solo en `.env` del VPS (jamás en imágenes ni en GitHub) |
| Backups | `pg_dump` nightly (F4) |
| Monitoreo | Ping HTTP gratis (UptimeRobot) (F4) |
| GHCR | Paquetes **públicos**; visibilidad se setea manual en la UI de GitHub (GITHUB_TOKEN no la cambia) |

## 3. Arquitectura

```
Visitantes ──► eduscout.cl (nic.cl/Cloudflare, DNS only) ──► nginx (HTTPS)
                                                              ├── /   → Frontend (Next.js standalone)
                                                              └── /api → Backend (NestJS)
                                                                          │
                                                           PostgreSQL 17 ◄─┼── (docker network interna)
                                                                          │
                                                       pg_dump nightly ──► (F4)

  Si Fase 2b (fallback): Mac con IP chilena ── Tailscale/SSH ──► PostgreSQL
     launchd 06:00 y 18:00 → scripts/scrape.ts
```

- Provisionamiento de la VM: `deploy/terraform/` (instancia A1 sobre la VCN/subred públicas
  existentes de OCI; `retry.sh` reintenta `terraform apply` cada 15 min hasta conseguir capacidad).
- Shell del VPS: instalar **Docker + Compose**, copiar `deploy/`, crear `deploy/.env`,
  montar timer systemd de deploy y levantar el stack.
- El puerto **5432 nunca se expone al mundo**. Solo red interna de Docker + (si 2b) túnel Tailscale/SSH.

## 4. Scraping (decisión crítica)

- La IP del VPS de Santiago es geográficamente chilena → resuelve bloqueos por país.
- **Riesgo abierto**: reputación de IP de datacenter (AS31898 Oracle) ante Cloudflare/WAF; algunas bases geoIP podrían mapear el bloque a EE. UU.
- **Método de decisión (fase 2)**: scrape manual de prueba desde el VPS midiendo las 12 fuentes.
  - **2a** pasar todas (o casi todas) → cron nativo en Oracle (`SCRAPING_CRON_ENABLED=true`), la Mac queda fuera de operación. ✅
  - **2b** fallar alguna → esa fuente se scrapea desde la Mac (IP residencial) con túnel; cron desactivado para ella en Oracle.

## 5. Deploy automatizado (CI/CD)

- **Workflows por repo** (`eduscout-back`, `eduscout-front`), ambos en `push a main`.
- Build multi-stage (amd64 + arm64) → imagen → `ghcr.io/<org>/<repo>:<git-sha>` y `:latest`.
- La imagen backend trae `scripts/` (necesario para el `db:seed` interno) y arranca con
  `bun run db:migrate` antes de `bun dist/src/main.js`.
- **VPS**: `docker compose pull && up -d` vía **timer systemd** (cada ~5 min).
  - Se elige timer systemd sobre Watchtower para no montar `docker.sock` dentro de un contenedor.
- **Migrations**: el entrypoint del contenedor backend ejecuta `db:migrate` (idempotente) antes de `start:prod`.
- **Rollback**: apuntar `.env` del VPS a un tag anterior → `docker compose up -d`.
- **GHCR público**: hecho manual en la UI de GitHub (los pasos con `GITHUB_TOKEN` no funcionan;
  se retiró del workflow). Pull anónimo requiere intercambiar bearer token (`/token?scope=repository:...:pull`).

## 6. Estado de implementación

**Hecho**
- Guard `SCRAPING_CRON_ENABLED` en `ScrapingScheduler` (ConfigService; default `true`).
- Dockerfiles multi-stage (`oven/bun` back, `oven/bun`→`node:22-alpine` front) con `output: standalone`.
- Workflows CI/CD por repo (push a main → GHCR amd64+arm64).
- `deploy/`: `docker-compose.prod.yml`, `nginx.conf` (80/ACME), `scripts/deploy.sh`,
  `systemd/eduscout-deploy.{service,timer}`, `.env.example`.
- `deploy/terraform/`: instancia A1 + retry loop (`retry.sh`).
- `docs/ORACLE_GUIA.md`: guía de cuenta Oracle + VM.
- F0: `eduscout.cl` registrado en nic.cl y zona activa en Cloudflare (NS delegados).
- Lint/typecheck: scripts `bun run typecheck` en ambos repos; ESLint 9 flat config.

**Pendiente**
- F1: crear la VM (el loop de Terraform sigue reintentando por capacidad en AD-1).
- F2: scrape de prueba desde el VPS → decisión 2a/2b.
- F4: backups nightly, UptimeRobot, registros A en Cloudflare + certbot + bloque 443 en nginx.
- F5: corte de ngrok/local y verificación final.
- *(Solo 2b)* `scripts/scrape.ts` con `createApplicationContext` + LaunchAgent de macOS.

## 7. Límites gratuitos Oracle (cuidado)

4 OCPU ARM + 24 GB RAM totales, ~200 GB disco, 10 TB salida. La shape A1 a veces sale
**"sin capacidad"**; la región Santiago tiene un solo AD, así que la única palanca es
reintentar (Terraform `retry.sh`) o bajar el tamaño pedido (p. ej. 1 OCPU / 6 GB).

## 8. Roadmap de implementación

1. **F0** Verificar disponibilidad e inscribir `eduscout.cl` (nic.cl). ✅
2. **F1** Cuenta Oracle → VM ARM Santiago (Terraform + retry) → Docker + Compose →
   migraciones + seed. *(en curso)*
3. **F2** Scrape de prueba desde el VPS (12 fuentes) → **decisión 2a/2b**.
4. **F3** CI/CD: Dockerfiles, workflows push → GHCR, timer systemd, migrations en entrypoint. ✅
5. **F4** Backups nightly + monitor UptimeRobot + TLS/DNS apuntando (certbot).
6. **F5** Corte: apagar ngrok/local, verificación final (buscador, conteos, Swagger).

## 9. Riesgos y mitigaciones

- **Punto único de falla** (1 VM) → backups + monitor + doc de recuperación.
- **IP de datacenter bloqueada** → la Fase 2 decide; fallback Mac (2b).
- **La Mac apagada** → solo aplica en 2b; mitigado con 2 corridas al día.

## 10. Decisiones pendientes

- Túnel fallback 2b: Tailscale (preferido) o SSH.
- Destino de backups (F4): volumen de la VM vs OCI Object Storage.
- A registros de Cloudflare (A `eduscout.cl` + `www`) cuando exista la IP del VPS.