# EduScout

Agregador de ofertas académicas de educación superior en Chile.

EduScout recopila, organiza y presenta ofertas de trabajo académico (cargos docentes y
concursos académicos) desde universidades e instituciones del país, todo en una sola
plataforma con buscador filtrable.

## Stack

| Capa | Tecnología |
|------|-----------|
| **Backend** | NestJS 11, Drizzle ORM, PostgreSQL 17 |
| **Frontend** | Next.js 16, React 19, Tailwind CSS v4 |
| **Scraping** | Axios, Cheerio, Playwright |
| **Runtime** | Bun |
| **Infra** | Docker Compose en un VPS Oracle Cloud (provisionado con Terraform) |

## Estructura del repositorio

```
edu-scout/
├── eduscout-back/    → API y scraping (NestJS)
├── eduscout-front/   → Aplicación web (Next.js)
├── deploy/           → Infraestructura de producción (compose, nginx, terraform, timers)
├── docs/             → Decisiones de producción y guía de Oracle Cloud
├── AGENTS.md
└── README.md
```

Cada módulo es un [git submodule](https://git-scm.com/book/es/v2/Herramientas-de-Git-Subm%C3%B3dulos) con su propio repositorio y pipeline.

## Setup rápido

```bash
# 1. Clonar con submodules
git clone --recurse-submodules https://github.com/bguzmanm/edu-scout.git
cd edu-scout

# 2. Backend
cd eduscout-back
bun install
cp .env.example .env
bun run docker:up          # PostgreSQL 17
bun run db:generate        # Generar migraciones
bun run db:migrate         # Aplicar migraciones
bun run db:seed            # Sembrar 12 fuentes iniciales
bun run start:dev          # → http://localhost:3001

# 3. Frontend (otra terminal)
cd ../eduscout-front
bun install
bun run dev                # → http://localhost:3000
```

## Puertos

| Servicio | Puerto |
|----------|--------|
| Frontend (Next.js) | `:3000` |
| Backend (NestJS) | `:3001` |
| PostgreSQL | `:5432` |

## Fuentes de datos

EduScout scraping automáticamente las siguientes instituciones:

| Institución | Tipo de scraper | Sitio web |
|-------------|----------------|-----------|
| Pontificia Universidad Católica de Chile | WordPress (HTML) | [cargosacademicos.uc.cl](https://cargosacademicos.uc.cl) |
| Universidad de Chile | API REST | [concurso-academico.uchile.cl](https://concurso-academico.uchile.cl) |
| Universidad Adolfo Ibañez | HTML parsing | [uai.cl](https://www.uai.cl/ingenieria-y-ciencias/academicos/concursos-academicos) |
| Universidad Nacional Andrés Bello | trabajando.cl | [unab.trabajando.cl](https://unab.trabajando.cl) |
| Inacap | trabajando.cl | [inacap.trabajando.cl](https://inacap.trabajando.cl) |
| Duoc UC | trabajando.cl | [duoc.trabajando.cl](https://duoc.trabajando.cl) |
| IP Santo Tomás | HTML/WordPress | [ipsantotomas.cl](https://www.ipsantotomas.cl/trabaja-con-nosotros/academicos/) |
| IP Chile | Playwright (SPA) | [laborum.cl](https://www.laborum.cl) |
| Instituto Profesional Iplacex | API REST | [convocatoriasdocentes.iplacex.cl](https://convocatoriasdocentes.iplacex.cl/) |
| Universidad de Concepción | trabajando.cl | [udec.trabajando.cl](https://udec.trabajando.cl/trabajo-empleo/) |
| U. Técnica Federico Santa María | HTML | [vra.usm.cl](https://vra.usm.cl/ofertas-laborales/) |
| Universidad de Valparaíso | HTML | [cyl.uv.cl](https://cyl.uv.cl/cargos) |

El scraping se ejecuta automáticamente por cron según `SCRAPING_CRON_ENABLED` (en producción
desactivado hasta validar el scraping desde el VPS). También se puede ejecutar manualmente:

```bash
# Todas las fuentes activas
curl -X POST http://localhost:3001/api/scraping/run

# Una fuente específica
curl -X POST http://localhost:3001/api/scraping/run?source=uchile
```

## API

Swagger disponible en `http://localhost:3001/api` cuando el backend está corriendo.

**Endpoints principales:**

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/jobs` | Buscar ofertas (paginado, con filtros) |
| `GET` | `/api/jobs/:id` | Detalle de una oferta |
| `GET` | `/api/jobs/stats` | Estadísticas globales |
| `GET` | `/api/sources` | Listar fuentes |
| `POST` | `/api/scraping/run` | Ejecutar scraping manual |

## Licencia

UNLICENSED — Proyecto privado.