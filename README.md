# EduScout

Agregador de ofertas de trabajo académico para educación superior en Chile.

EduScout recopila, organiza y presenta ofertas de trabajo docente desde múltiples universidades e instituciones del país, todo en una sola plataforma.

## Stack

| Capa | Tecnología |
|------|-----------|
| **Backend** | NestJS 11, Drizzle ORM, PostgreSQL 17 |
| **Frontend** | Next.js 16, React 19, Tailwind CSS v4 |
| **Scraping** | Axios, Cheerio, Playwright |
| **Runtime** | Bun |
| **Infra** | Docker (PostgreSQL) |

## Estructura del repositorio

```
edu-scout/
├── eduscout-back/    → API y scraping (NestJS)
├── eduscout-front/   → Aplicación web (Next.js)
├── AGENTS.md
└── README.md
```

Cada módulo es un [git submodule](https://git-scm.com/book/es/v2/Herramientas-de-Git-Subm%C3%B3dulos) con su propio repositorio.

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
bun run db:seed            # Sembrar 8 fuentes iniciales
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
| Universidad Nacional Andrés Bello | Nuxt data parsing | [unab.trabajando.cl](https://unab.trabajando.cl) |
| Inacap | Nuxt data parsing | [inacap.trabajando.cl](https://inacap.trabajando.cl) |
| Duoc UC | Nuxt data parsing | [duoc.trabajando.cl](https://duoc.trabajando.cl) |
| IP Santo Tomás | WordPress (HTML) | [ipsantotomas.cl](https://www.ipsantotomas.cl/trabaja-con-nosotros/academicos/) |
| IP Chile | Playwright (SPA) | [laborum.cl](https://www.laborum.cl) |

El scraping se ejecuta automáticamente todos los días a las **6:00 AM**. También se puede ejecutar manualmente:

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
