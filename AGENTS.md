# AGENTS.md

## Project

EduScout unifica ofertas de trabajo académico (cargos docentes y concursos académicos) de
instituciones de educación superior chilenas en un buscador filtrable. El backend scrapea las
páginas de las instituciones (axios/Cheerio vía adaptadores por fuente), consolida en
PostgreSQL y expone una API; el frontend (Next.js) es una SPA que consume esa API. El
despliegue de producción son 2 VMs `VM.Standard.E2.1.Micro` (Oracle Cloud Always Free)
con Docker Compose en topología split (`eduscout-db`: solo PostgreSQL;
`eduscout-app`: backend + frontend + nginx), dominio `eduscout.cl` vía Cloudflare (DNS only).

## Stack

- **Backend:** NestJS 11, PostgreSQL 17, Drizzle ORM, Bun
- **Frontend:** Next.js 16, React 19, Tailwind CSS v4, Bun
- **All UI text, seed data, and Swagger descriptions are in Spanish**

## Quick Reference

Todos los comandos se ejecutan en el directorio del submódulo correspondiente.

Backend (`eduscout-back/`):

- **Dev server**: `bun run start:dev` (requiere Postgres: `bun run docker:up`)
- **Build**: `bun run build`
- **Start prod**: `bun run start:prod`
- **Test**: `bun test`
- **Lint**: `bun run lint`
- **Typecheck**: `bun run typecheck`
- **Migraciones/seed**: `bun run db:migrate`, `bun run db:seed`

Frontend (`eduscout-front/`):

- **Dev server**: `bun run dev` (puerto 3000)
- **Build**: `bun run build`
- **Start prod**: `bun run start`
- **Lint**: `bun run lint`
- **Typecheck**: `bun run typecheck`

## Architecture

Monorepo raíz con submódulos git independientes (pipelines y repos propios):

- `eduscout-back/` — API NestJS: módulos `sources`, `jobs`, `scraping`, `database` (Drizzle + `postgres`).
- `eduscout-front/` — Next.js App Router (`src/app/...`), API consumida server-side.
- `deploy/` — infraestructura de producción: `docker-compose.app.yml` + `docker-compose.db.yml` (split), `nginx.conf` (80/443 →
  `frontend:3000`, `backend:3001`), `terraform/` (VM Oracle), scripts y timers systemd.
- Producción: nginx (Let's Encrypt) → frontend Next standalone → backend NestJS → PostgreSQL 17.
  PostgreSQL corre en la VM `eduscout-db` (solo `5432` alcanzable desde el CIDR de la VCN
  `10.0.0.0/16`); backend/frontend/nginx en `eduscout-app`. Solo 80/443 y 22 (SSH) expuestos.

## Conventions

- Todo texto visible (UI, seed, Swagger) está en español.
- Uso de Bun como gestor y runtime; ESLint 9 con config flat (`eslint.config.mjs`).
- La API del backend se sirve bajo el prefijo `/api/`.
- Los commits siguen Conventional Commits (feat/fix/chore/docs).

## Testing

- Backend: `bun test` (jest config en `package.json`, tests en `src/**/*.spec.ts`).
- Frontend: sin suites de tests.

## Gotchas

- **Migraciones custom (drizzle-kit)**: para migraciones de SOLO SQL (cambios de datos, no de
  schema) usar `bunx drizzle-kit generate --custom --name <slug>` y rellenar el `.sql`. OJO:
  drizzle-kit solo aplica entradas del journal con `when` mayor al último aplicado en la DB — si
  interpolas/cambias timestamps (`when`) de migraciones previas, actualízalos para mantener el orden.
- **Cron de scraping en prod**: `SCRAPING_CRON_ENABLED=true` en `deploy/.env` (F2 validado:
  12/12 fuentes OK desde el VPS, decisión 2a, corrida diaria 06:00 America/Santiago).
  La imagen se construye vía CI en cada push a `main`.
- **`NEXT_PUBLIC_API_URL`**: horneada en el build del Dockerfile (`http://backend:3001`, red interna).
- **Arranque prod backend**: `bun dist/src/main.js` (el bundle queda en `dist/src/`, no `dist/`).
- **GHCR**: los paquetes (`eduscout-back`, `eduscout-front`) son públicos; el pull anónimo requiere
  intercambiar un bearer token (`https://ghcr.io/token?scope=repository:...:pull`).
- **Oracle/Terraform**: shape A1 free = 4 OCPU/24 GB totales por tenant; regiones con un solo AD
  (Santiago) y "out of host capacity" común → reintentar (`deploy/terraform/retry.sh`, 15 min).
- **iptables de Ubuntu en Oracle**: las imágenes bloquean 80/443 por defecto aun con la security
  list abierta; requiere `iptables -I INPUT ... -j ACCEPT` + `netfilter-persistent save`.
- **Backups de DB cifrados (VM db)**: nightly 04:00 UTC vía `deploy/scripts/backup-db.sh` → GPG
  AES256. Passphrase en `/opt/eduscout/deploy/.backup-gpg-passphrase` (root 600); copia local
  gitignored en `deploy/.backup-gpg-passphrase`. Decifrar: `gpg --batch --decrypt --pinentry-mode
  loopback --passphrase-file <pass>` (ver `PLAN_TRABAJO.md`).
- **Residuo pre-split en app VM**: ~~todavía hay un `deploy-db-1` + timer `eduscout-deploy-db`
  corriendo en `eduscout-app`~~ → LIMPIADO 16/09 noche (timer/service disabled, contenedor
  removido; volumen `deploy_postgres_data` conservado, DB residual estaba vacía).
- **Bot de Telegram local vs prod**: `eduscout-back/.env` (dev) usa el MISMO `TELEGRAM_BOT_TOKEN`
  que prod → si corres `bun run start:dev` mientras el bot de prod hace polling, Telegram
  responde `409 Conflict` (doble `getUpdates`) cada ~60s. Correr solo una instancia a la vez o
  usar un token de prueba local.