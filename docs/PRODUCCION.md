# Producción — EduScout

> Decisiones de arquitectura y despliegue en producción.
> Actualizado: 2026-09-12.

## 1. Objetivo

Pasar la app a producción con **costo $0**, dominio propio en `.cl`, deploy automatizado y scraping confiable, sin depender de la Mac del desarrollador.

## 2. Decisiones clave

| Tema | Decisión |
|---|---|
| Hosting | **Oracle Cloud Always Free**, 2× `VM.Standard.E2.1.Micro` (AMD gratis) en split |
| Región | **Santiago, Chile** (`sa-santiago-1`, un solo AD) |
| VMs | `eduscout-db` = solo PostgreSQL; `eduscout-app` = backend + frontend + nginx |
| VM | **Provisionadas con Terraform** (`deploy/terraform/`) + loop de reintentos por "out of host capacity" |
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

- Provisionamiento de las VMs: `deploy/terraform/` (2 instancias sobre la VCN/subred públicas
  existentes de OCI; `retry.sh` reintenta `terraform apply` cada 15 min hasta conseguir capacidad).
- Shell de cada VPS: **Docker + Compose**, copiar `deploy/`, crear `deploy/.env` según la VM
  (`eduscout-db`: solo `DATABASE_*`; `eduscout-app`: completo), montar el timer systemd correspondiente
  (`eduscout-deploy.timer` en app / `eduscout-deploy-db.timer` en db) y levantar el stack
  (`deploy/docker-compose.app.yml` / `deploy/docker-compose.db.yml`).
- El puerto **5432 no se expone al mundo**: la Security List solo permite ingress desde `10.0.0.0/16`
  (intra-VCN) y el iptables interno de la VM db lo restringe al mismo CIDR. Solo 80/443 y 22 (SSH) públicos.

## 4. Scraping (decisión crítica)

- La IP del VPS de Santiago es geográficamente chilena → resuelve bloqueos por país. ✅
- **Riesgo verificado (F2, 2026-09-16)**: con la IP del datacenter (AS31898 Oracle) el scrape
  pasó **12/12 fuentes, 0 errores** (191 ofertas activas). No hubo bloqueo por Cloudflare/WAF ni geoIP.
- **Decisión (fase 2)**: **2a** — cron nativo en Oracle (`SCRAPING_CRON_ENABLED=true`, 06:00
  America/Santiago); la Mac queda fuera de operación.

## 5. Deploy automatizado (CI/CD)

- **Workflows por repo** (`eduscout-back`, `eduscout-front`), ambos en `push a main`.
- Build multi-stage (amd64 + arm64) → imagen → `ghcr.io/<org>/<repo>:<git-sha>` y `:latest`.
- La imagen backend trae `scripts/` (necesario para el `db:seed` interno) y arranca con
  `bun run db:migrate` antes de `bun dist/src/main.js`.
- **VPS**: `docker compose pull && up -d` vía **timer systemd** (cada ~5 min).
  - Se elige timer systemd sobre Watchtower para no montar `docker.sock` dentro de un contenedor.
  - Antes del pull, `deploy.sh` sincroniza `/opt/eduscout` con `origin/main` (`git fetch` +
    `reset --hard`): los dos VMs son checkouts del repo público desde 29/10/2026, así que
    `nginx.conf`, los compose y los scripts llegan solos. `.env`, `.backup-gpg-passphrase` y
    `terraform.tfstate` son no versionados y no se tocan.
  - Después del `up -d`, `deploy.sh` compara el `nginx.conf` del repo con el que ve el
    contenedor y recarga nginx. Si difieren, primero **recrea** el contenedor: el archivo se
    monta uno a uno, y como git reemplaza el inode al actualizarlo, el contenedor seguiría
    leyendo el viejo (un `reload` no lo arregla). Si la config es inválida, nginx mantiene la
    anterior y el service queda en `failed` (visible en `journalctl -u eduscout-deploy`).
  - Los secrets se siguen escribiendo a mano en cada VM (`.env`), nunca por git.
- **Migrations**: el entrypoint del contenedor backend ejecuta `db:migrate` (idempotente) antes de `start:prod`.
- **Rollback**: apuntar `.env` del VPS a un tag anterior → `docker compose up -d`.
- **GHCR público**: hecho manual en la UI de GitHub (los pasos con `GITHUB_TOKEN` no funcionan;
  se retiró del workflow). Pull anónimo requiere intercambiar bearer token (`/token?scope=repository:...:pull`).

## 6. Estado de implementación

**Hecho**
- Guard `SCRAPING_CRON_ENABLED` en `ScrapingScheduler` (ConfigService; default `true`).
- Dockerfiles multi-stage (`oven/bun` back, `oven/bun`→`node:22-alpine` front) con `output: standalone`.
- Workflows CI/CD por repo (push a main → GHCR amd64+arm64).
- `deploy/`: `docker-compose.app.yml` + `docker-compose.db.yml` (split app/db), `nginx.conf`
  (80/ACME), `scripts/deploy.sh` (`app|db`), `systemd/eduscout-deploy.{service,timer}` y
  `systemd/eduscout-deploy-db.{service,timer}`, `.env.example`.
- `deploy/terraform/`: 2× `VM.Standard.E2.1.Micro` + retry loop (`retry.sh`).
- `docs/ORACLE_GUIA.md`: guía de cuenta Oracle + VM.
- F0: `eduscout.cl` registrado en nic.cl y zona activa en Cloudflare (NS delegados).
- F1: 2× VM Micro (`eduscout-app` + `eduscout-db`) provisionadas, Docker + Compose
  en split, migraciones automáticas y seed de las 12 fuentes (endpoints `/`, `/api`, `/api/jobs` OK).
- F2: scrape de prueba desde el VPS — **12/12 fuentes OK, 0 errores** → decisión **2a**:
  cron nativo en Oracle activado (`SCRAPING_CRON_ENABLED=true`, 06:00 America/Santiago) con
  informe diario a Telegram (token + chat id en `.env`, bot `@eduScout_cl_bot` + comandos `/scrape`, `/status`, `/list`, `/stats`). La Mac queda fuera de operación.
- F4: registros A en Cloudflare (DNS only) → `eduscout-app`; TLS Let's Encrypt con certbot
  (https 200 + redirect 80→443 + renovación semanal `eduscout-certbot.timer`); backups nightly
  en `eduscout-db` (`eduscout-backup.timer`, 04:00, retención 7 días).
- Lint/typecheck: scripts `bun run typecheck` en ambos repos; ESLint 9 flat config.
- Medición de audiencia (ver §11): access log de nginx persistido en `deploy/logs/nginx/` +
  `deploy/scripts/log-report.sh` (goaccess en Docker); atribución de registros por canal
  (`candidates.acquisition_*`, migración `0018`) visible en el panel admin.

**Pendiente**
- F4: monitoreo UptimeRobot (faltan los checks). *— el usuario los creó en su cuenta.*
- *(Solo si 2b)* `scripts/scrape.ts` con `createApplicationContext` + LaunchAgent de macOS — ya no aplica (2a).

## 7. Límites gratuitos Oracle (cuidado)

4 OCPU ARM + 24 GB RAM totales, ~200 GB disco, 10 TB salida. La shape A1 a veces sale
**"sin capacidad"**; la región Santiago tiene un solo AD, así que la única palanca es
reintentar (Terraform `retry.sh`) o bajar el tamaño pedido (p. ej. 1 OCPU / 6 GB).

## 8. Roadmap de implementación

1. **F0** Verificar disponibilidad e inscribir `eduscout.cl` (nic.cl). ✅
2. **F1** Cuenta Oracle → 2× VM Micro Santiago (Terraform + retry) → Docker + Compose →
   migraciones + seed. ✅
3. **F2** Scrape de prueba desde el VPS (12 fuentes) → **decisión 2a**. ✅
4. **F3** CI/CD: Dockerfiles, workflows push → GHCR, timer systemd, migrations en entrypoint. ✅
5. **F4** Backups nightly ✅ + monitor UptimeRobot ✅ + TLS/DNS apuntando ✅.
6. **F5** Corte de ngrok/local ✅, IP pública reservada (`144.22.42.169`) ✅, verificación final ✅.

## 9. Riesgos y mitigaciones

- **Punto único de falla** (2 VMs Micro) → backups (✅ en db) + monitor UptimeRobot (⏳) + doc de recuperación.
- **IP de datacenter bloqueada** → verificado en F2: **no bloquea** (2a). Fallback Mac (2b) descartado.
- **La Mac apagada** → no aplica (2a: scraping solo en Oracle).

## 10. Decisiones pendientes

- **F5**: eliminar los registros `*.vercel.app`/ngrok locales cuando se corten. *— el usuario confirmó que ya no están en uso.*
- **IP reservada**: lista (`144.22.42.169`, reservada en OCI; sobrevive paradas de la VM). ⚠️ actualizala si se recrea la VM.

## 11. Medición de audiencia

No hay analítica de terceros (ni GA, ni Plausible). La medición es propia y en dos capas:

**a) Tráfico (logs de nginx).** El `server` 443 escribe `access_log /var/log/eduscout/access.log`
en formato `COMBINED`, persistido en `deploy/logs/nginx/` por el bind mount del compose. El
contenedor corre con `TZ=America/Santiago`, así que las horas del log son locales.

```bash
cd /opt/eduscout/deploy
./scripts/log-report.sh            # dashboard goaccess en la terminal
./scripts/log-report.sh --html     # reporte HTML en logs/reportes/
./scripts/log-report.sh --rotate   # archiva access.log y hace nginx -s reopen
```

goaccess corre en un contenedor efímero (`allinurl/goaccess`), sin instalar nada en la VM. Usa
`--ignore-crawlers`, que excluye el tráfico de Googlebot y compañía: las visitas del reporte son
personas, no indexación. `deploy/logs/nginx` debe ser `root:<tu usuario>` con `chmod 775`: nginx
corre como root pero con `cap_drop: ALL` (sin `CAP_DAC_OVERRIDE`), así que solo escribe en un
directorio cuyo dueño sea root, y el grupo con escritura permite rotar sin `sudo`. `deploy.sh`
deja esos permisos en cada corrida; `logs/reportes` queda para el dueño del repo.

**Verlo desde el navegador (incluido el celular).** `https://eduscout.cl/reportes/` sirve el
`ultimo.html` con Basic Auth; nginx lo monta desde `logs/reportes` (ro). Como muchos clientes
(navegadores embebidos de WhatsApp/Instagram, el panel de OpenCode) no saben mostrar el diálogo
de Basic Auth, existe una segunda entrada con token en la ruta:
`https://eduscout.cl/r/<token>/` (la misma vista, sin diálogo). Para esa ruta el token **es** la
credencial y `access_log` está apagado ahí para que no quede escrito en el propio reporte; si se
filtra, se cambia el `location` en `nginx.conf` y se despliega. El timer
`eduscout-log-report.timer` regenera el reporte a diario a las 07:30 de Chile y rota el log el
día 1 de cada mes. Credenciales en `deploy/logs/.htpasswd` (no versionado, `644` porque el worker
de nginx corre como uid 101). Para cambiarlas, en la VM:

```bash
docker run --rm httpd:alpine htpasswd -nbB eduscout 'nueva-clave' \
  > /opt/eduscout/deploy/logs/.htpasswd
sudo /opt/eduscout/deploy/scripts/deploy.sh app   # recrea nginx con el archivo nuevo
```

Si `.htpasswd` no existe, Docker lo crearía como **directorio** y nginx no arrancaría; por eso
`deploy.sh` lo genera (contraseña aleatoria, se imprime una sola vez en el journal) antes del
`up -d`. El timer se instala una vez por VM:

```bash
sudo install -m 644 /opt/eduscout/deploy/systemd/eduscout-log-report.* /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now eduscout-log-report.timer
```

**b) Conversión (base de datos).** `candidates.acquisition_source/medium/campaign/referrer`
guarda el canal capturado en el navegador al momento del registro (`utm_*` o dominio de
referencia, con ventana de 30 días y último toque con UTM). Se ve en el panel admin, pestaña
**Postulantes → Registros por canal**. Los registros anteriores al 28/10/2026 aparecen como
`sin dato`.

Lo que los logs no pueden decir (y Search Console sí): qué consultas traen visitas, en qué
posición y con qué CTR. Verificar `eduscout.cl` en Google Search Console es el siguiente paso
manual, y no requiere cambios de código.
