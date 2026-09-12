# AGENTS.md

## Project

EduScout unifica ofertas académicas de posgrado (magíster) de universidades chilenas en un
buscador filtrable. El backend scrapea las páginas de las instituciones (Playwright/Cheerio
vía adaptadores por fuente), consolida en PostgreSQL y expone una API; el frontend (Next.js)
es una SPA que consume esa API. El despliegue de producción es un único VPS (Oracle Cloud
Always Free) con Docker Compose, dominio `eduscout.cl` vía Cloudflare (DNS only).

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

- `eduscout-back/` — API NestJS: módulos `sources`, `offers`, `scraping`, `health` (Drizzle + `postgres`).
- `eduscout-front/` — Next.js App Router (`src/app/...`), API consumida server-side.
- `deploy/` — infraestructura de producción: `docker-compose.prod.yml`, `nginx.conf` (80/443 →
  `frontend:3000`, `backend:3001`), `terraform/` (VM Oracle), scripts y timers systemd.
- Producción: nginx (Let's Encrypt) → frontend Next standalone → backend NestJS → PostgreSQL 17,
  todo dentro de una red interna de Docker; solo 80/443 y 22 (SSH) expuestos.

## Conventions

- Todo texto visible (UI, seed, Swagger) está en español.
- Uso de Bun como gestor y runtime; ESLint 9 con config flat (`eslint.config.mjs`).
- La API del backend se sirve bajo el prefijo `/api/`.
- Los commits siguen Conventional Commits (feat/fix/chore/docs).

## Testing

- Backend: `bun test` (jest config en `package.json`, tests en `src/**/*.spec.ts`).
- Frontend: sin suites de tests.

## Gotchas

- **Cron de scraping off en prod**: `SCRAPING_CRON_ENABLED=false` en `deploy/.env` hasta validar
  el scraping desde el VPS (fase 2a); la imagen se construye vía CI en cada push a `main`.
- **`NEXT_PUBLIC_API_URL`**: horneada en el build del Dockerfile (`http://backend:3001`, red interna).
- **Arranque prod backend**: `bun dist/src/main.js` (el bundle queda en `dist/src/`, no `dist/`).
- **GHCR**: los paquetes (`eduscout-back`, `eduscout-front`) son públicos; el pull anónimo requiere
  intercambiar un bearer token (`https://ghcr.io/token?scope=repository:...:pull`).
- **Oracle/Terraform**: shape A1 free = 4 OCPU/24 GB totales por tenant; regiones con un solo AD
  (Santiago) y "out of host capacity" común → reintentar (`deploy/terraform/retry.sh`, 15 min).
- **iptables de Ubuntu en Oracle**: las imágenes bloquean 80/443 por defecto aun con la security
  list abierta; requiere `iptables -I INPUT ... -j ACCEPT` + `netfilter-persistent save`.