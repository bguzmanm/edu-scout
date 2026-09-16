# Plan de Trabajo — Hardening de Seguridad de EduScout

> Estado a 2026-09-16 (actualización noche). Propósito: **reporte final** de lo entregado
> y **punto de reanudación** para futuras sesiones (leer antes de tocar nada).
> Pasos `[x]` = verificados en vivo y commit/dispatch de hoy.

## Reglas del operador que SIEMPRE respetar (no negociables)

1. **No rotar secretos**: admin password, `ADMIN_PASSWORD`, `ADMIN_TOKEN_SECRET`,
   `CANDIDATE_TOKEN_SECRET`, Telegram → **mantienen sus valores actuales**. Nunca cambiarlos.
   El endurecimiento de hashing (scrypt) se hizo **sin tocar valores**, solo el algoritmo.
2. **Cero downtime / no romper prod**: toda acción en VM es `verificar → aplicar → comprobar`; si
   algo se rompe → rollback y reportar, no "arreglar a oscuras".
3. **Reversible e idempotente**: los scripts pueden correrse N veces con el mismo resultado.
4. **No exponer secretos**: rsync/scp SIEMPRE con `--exclude='.env' --exclude='*.gpg' --exclude='*.pem'`.
   Los `.env` se copian con `scp` dircto a `/tmp` + `sudo mv` (nunca rsync), o se escriben in-place.
5. **Pasos "destructivos" van gated**: requieren OK explícito del usuario (ej: backup cifrado de la VM db).

## Topología de producción

| VM | IP pública | Rol | Puertos expuestos |
|---|---|---|---|
| `eduscout-app` | `144.22.42.169` | nginx → frontend(3000) → backend(3001) + timer | 22, 80, 443 |
| `eduscout-db` | `161.153.203.115` | PostgreSQL 17 | 22; 5432 SOLO `10.0.0.0/16` (iptables) |

- nginx CSP/headers/limit_req → `deploy/nginx.conf` (montado ro y recargado en caliente).
- Backend/Frontend: imágenes en GHCR (`ghcr.io/bguzmanm/eduscout-{back,front}:latest`), publicadas
  por CI en cada merge a `main`; la VM app las baja con timer systemd cada 5 min
  (`deploy/edu-scout-*.timer` → `deploy/edu-scout-*.service`, `docker compose pull && up -d`).

## Estado de cada frente (verificado en vivo)

### 1. nginx (app VM) — ✅ APLICADO y verificado
- Crash-loop tras `cap_drop ALL` → corregido agregando caps mínimas
  (`CHOWN FOWNER SETGID SETUID NET_BIND_SERVICE`). `docker-compose.app.yml`.
- Headers activos y chequeados con curl real: HSTS, CSP, nosniff, X-Frame-Options, Referrer-Policy,
  Permissions-Policy, `server_tokens off`.
- Throttle nginx: `limit_req` 5r/min login, 10r/min register → **verificado** (login#5/#6 → 503).
- CSP `img-src 'self' data: https:` → **logos externos cargan** (fix del 16/09, no romper branding).
  Config local = config desplegada (`diff` vacío); fix incluido en commit de hoy.

### 2. Backend (PR #2 merged) — imagen endurecida EN CI (success), lista para auto-pull
- scrypt para passwords (reemplaza HMAC-SHA256 legacy), reusa `hashPassword`/`verifyPassword`.
- Split `verifyAdminToken` / `verifyCandidateToken` (sin key-confusion entre roles).
- Guards por rol + `@Throttle` (5/min login, 10/min register).
- 409 genérico en registro (anti-enumeración), `trust proxy`, Swagger solo dev, CSP/logger hardening.
- El timer (5 min) la levanta sola: NO hay que forzar nada.
- ✅ Verificado en vivo (noche 16/09): login admin → `200` (scrypt, mismas credenciales),
  throttle aplicativo directo → `429` en request #6, nginx `503` en paralelo.

### 3. Frontend (PR #3 merged)
- `next@16.2.5`, `poweredByHeader:false`, fix XSS JSON-LD, CSP, headers. CI en curso/distribuyendo.
- ✅ Verificado en vivo (noche 16/09): imagen `ghcr.io/bguzmanm/eduscout-front:latest`
  (creada 18:02) desplegada; CSP con `img-src https:` confirmado con curl real.

### 4. VM db — ✅ HARDENING COMPLETO (aplicado y verificado)
- iptables: `5432` restringido a `10.0.0.0/16` con reglas **explícitas** ACCEPT (internal) + DROP
  (resto), persistidas vía `netfilter-persistent` (`/etc/iptables/rules.v4`). Aplicado con
  `harden-db-iptables.sh` (idempotente). App VM confirmó conexión `10.0.0.45:5432` OK.
- Backup **cifrado GPG (AES256)** desplegado: `backup-db.sh` del repo reemplazó la versión
  plana; passphrase en `/opt/eduscout/deploy/.backup-gpg-passphrase` (root 600; copia local
  gitignored en `deploy/.backup-gpg-passphrase`). Backup ejecutado + **descifrado de
  verificación OK** (gpg → gunzip -t). El timer nightly 04:00 ya usa la versión cifrada.

## Pendientes / próximos pasos

- [x] **VM db (gated):** `harden-db-iptables.sh` + backup cifrado GPG + probar descifrado de verificación.
- [x] Tras CI backend: **verificar en vivo throttle aplicativo (429)** y login admin OK
      (la credencial admin funcionará igual: el algoritmo cambió, el valor no).
- [x] Commitear el fix pendiente de `deploy/nginx.conf` (img-src https:).
- [ ] (Opcional, decisión de usuario) ISR o `no-store` en el fetch de `src/lib/api.ts` p/ datos públicos.
      → HECHO ítem 16/09 noche: ISR `revalidate: 3600` en los 4 GET públicos (`perf(frontend): ...` en main).
- [ ] (Opcional, decisión de usuario) Borrar los backups legacy **en claro** de
      hoy (16/09) en `/opt/eduscout/backups` (`..._0248.sql.gz`, `..._0400.sql.gz`); el retention
      nuevo solo barre `*.sql.gz.gpg`.
      → HECHO 16/09 noche: borrados (queda solo `eduscout_... .sql.gz.gpg`).
- [ ] (Opcional, higiene) La VM app aún corre un `deploy-db-1` + timer `eduscout-deploy-db`
      sobrantes de la topología pre-split (el backend usa la VM db; inactivos pero duplican
      5432 en la app VM). Deshabilitar timer y detener contenedor si no se usa.
      → HECHO 16/09 noche: timer/servicio `systemctl disable --now` + `compose down`
      (volumen `deploy_postgres_data` conservado; la DB residual estaba vacía).
- [x] (Resuelto) Log backend: `TelegramBotService: Error en polling ... 409`. Causa raíz:
      `eduscout-back/.env` (dev local) comparte el MISMO `TELEGRAM_BOT_TOKEN` que prod →
      doble `getUpdates` → conflicto Telegram. Cero 409 en ~2 min continuos tras cerrar la
      instancia dev. No es bug del infra.

## Comandos rápidos de verificación (post-cambio)

```bash
# headers + throttle en vivo (desde la VM app)
curl -sk -D- -o /dev/null https://127.0.0.1/ -H "Host: eduscout.cl" | grep -i "strict-transport\|content-security"
for i in $(seq 1 6); do curl -sk -o /dev/null -w "%{http_code}\n" -X POST https://127.0.0.1/api/auth/login -H "Host: eduscout.cl" -H "content-type: application/json" -d '{"username":"admin","password":"xxxx"}'; done
# estado contenedores
docker compose -f /opt/eduscout/deploy/docker-compose.app.yml ps
```

## Cómo reanudar una sesión (checklist de entrada)

1. Leer este archivo + `AGENTS.md`.
2. `git -C /Volumes/BGSSD/code/edu-scout status` (repo raíz con submódulos eduscout-back/front).
3. SSH sin passwords a ambas VMs; host key ya readmitida.
4. NO tocar `.env` de ninguna VM sin mtime-verificar primero y pedir OK.
5. Arrancar por lo `[ ]` (pendientes) de arriba.
