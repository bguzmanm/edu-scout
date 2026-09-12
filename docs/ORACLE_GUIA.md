# Guía: cuenta Oracle Cloud (Always Free) y VM para EduScout

Guía paso a paso para crear la cuenta gratuita de Oracle Cloud, aprovisionar la VM
que alojará EduScout en producción y dejarla lista para el despliegue.

Fecha de validación: septiembre 2026, contra la documentación oficial de Oracle.

## 0. Qué vas a tener (gratis, para siempre)

Con la cuenta **Oracle Cloud Free Tier** consigues, sin costo:

- **Crédito de prueba de $300 USD por 30 días** (para probar servicios; nosotros no lo usaremos).
- Recursos **Siempre gratis** que no caducan:
  - Hasta **4 OCPU / 24 GB de RAM** en **Ampere A1 (ARM)** divididos en 1 a 4 instancias
    (equivalente a 3.000 horas OCPU y 18.000 GB-hora al mes).
  - **200 GB** de almacenamiento en bloque (SSD NVMe).
  - **10 TB** de transferencia saliente al mes.
  - 2 instancias AMD micro (`VM.Standard.E2.1.Micro`) por si ocupas una VM liviana de respaldo.

> ⚠️ **Regla de oro**: mantén las instancias Ampere A1 dentro de **4 OCPU / 24 GB totales**.
> Si la cuenta está en periodo de prueba de 30 días y creas recursos A1 que exceden ese límite,
> Oracle **detiene y elimina** esas instancias a los 30 días salvo que cambies a cuenta de pago.
> Con nuestra única VM de 4 OCPU / 24 GB estás dentro del límite y el recurso queda para siempre.

## 1. Requisitos previos

- Email personal.
- **Teléfono móvil** (verificación por SMS).
- **Tarjeta de crédito** O **débito que funcione como crédito** (Visa, Mastercard, Amex, Discover, sin PIN).
  **No sirven**: tarjetas de prepago, virtuales de un solo uso, ni débito con PIN.
- **Clave SSH** ya generada en tu Mac (paso 2 de la sección 4).

## 2. Crear la cuenta

URL de registro: **https://signup.cloud.oracle.com/** (también desde cloud.oracle.com → *Start for free*).

1. Ingresa **email y contraseña**.
   Oracle permite **una cuenta gratuita por persona** (no crees varias, suspenden el arrendamiento).
2. Verifica el email con el enlace que llega a tu correo (válido 30 minutos) y vuelve a la página
   para continuar.
3. Completa con **datos reales**: nombre, **país: Chile**, compañía (opcional), dirección, teléfono.
   Oracle verifica la identidad; datos inventados = cuenta rechazada.
4. **Región principal** (el paso más importante):
   - Elige **Chile Central (Santiago, `sa-santiago-1`)** para reducir latencia.
   - La región principal **no se puede cambiar después** y es donde viven los recursos Siempre gratis.
   - Si Santiago no aparece en la lista de tu país, elige una región adyacente o avísame;
     en algunos países la promoción gratuita requiere contactar a Oracle Sales.
5. **Método de verificación de pago** → *Tarjeta de crédito*:
   - Oracle hace una **retención temporal (~$1 USD)** que tu banco libera en 3–5 días.
   - **No hay cargos reales** mientras permanezcas en Free Tier.
   - Si tu débito es rechazada, necesitarás una de crédito.
6. Confirma y espera el aprovisionamiento. Oracle tarda de **minutos a unas horas**
   (si pasa más de ~1 día, algo falló: revisa email/buzón de spam o reintenta).

Cuando termine, te lleva a la **consola OCI** y recibes un email con el acceso.
Tu cuenta queda con: Free Tier + $300 de prueba por 30 días.

## 3. Primera comprobación

1. Entra a **https://cloud.oracle.com/** e inicia sesión en tu región (Santiago).
2. Arriba a la derecha, confirma que estás en **Chile Central (Santiago)**.
3. No crees nada costoso: "Upgrade to Pay As You Go" es opcional y lo dejamos para después
   (o nunca, si la VM siempre gratuíta alcanza).

## 4. Crear la VM (instancia Ampere A1)

### 4.1 Generar la clave SSH en tu Mac (una sola vez)

```bash
ssh-keygen -t ed25519 -C "eduscout-oracle" -f ~/.ssh/oracle_eduscout
cat ~/.ssh/oracle_eduscout.pub   # copia esta clave para pegarla en la consola
```

> Si pierdes la clave privada (o el passphrase), no podrás entrar nunca a la VM;
> guarda `~/.ssh/oracle_eduscout` a salvo.

### 4.2 Crear la instancia

En la consola OCI:

1. Menú hamburguesa ☰ → **Compute → Instances → Create instance**.
2. **Name**: `eduscout-prod`.
3. **Placement**: deja el *availability domain* por defecto (AD-1). Si después falla por capacidad,
   prueba con otro AD.
4. **Image**: **Canonical Ubuntu 24.04** (la LTS más reciente).
5. **Shape → Change shape** → sección **Ampere** → **`VM.Standard.A1.Flex`**:
   - **OCPUs = 4**, **memoria = 24 GB**.
   - Debe decir **Always Free eligible** al lado.
6. **Networking**: crea/usar la **VCN por defecto** con su subnet pública y marca
   **"Assign a public IPv4 address" = Sí**.
7. **Add SSH keys**: elige **Paste public keys** y pega la clave del paso 4.1.
8. **Boot volume**: deja el tamaño por defecto (o súbelo hasta ~100 GB si quieres espacio;
   recuerda que el total Siempre gratis es 200 GB).
9. **Create** y espera a que la instancia pase a estado **Running** (1–3 min).
10. En los detalles de la instancia, **anota la IP pública**:
    ```
    ssh -i ~/.ssh/oracle_eduscout ubuntu@<IP_PUBLICA>
    ```

> **Error "Out of host capacity"**: es común con A1 en regiones concurridas.
> Solución: reintenta en horario de baja demanda, prueba otro *availability domain*,
> o espera unos días (Oracle repone capacidad). **No** caigas en la tentación de la
> AMD Micro (1 GB) para producción: Postgres + Nest + Next no caben.

### 4.2.b (Alternativa) Crear la instancia con Terraform

Para automatizar la creación y los reintentos por "Out of host capacity" (con `deploy/terraform/retry.sh`
que vuelve a intentar `terraform apply` cada 15 min):
- Antes de usarlo, genera una **API key** en OCI: tu perfil → API Keys → Add API Key → descarga el PEM
  y anota tenancy/user OCID y fingerprint.
- Copia `terraform.tfvars.example` a `terraform.tfvars` y completa los valores.
- Ejecuta `terraform init && terraform plan` (revisa el plan) y luego `./retry.sh`.

### 4.3 (Opcional, recomendado) IP pública reservada

La IP que asigna Oracle a la instancia es **efímera**: cambia si *detienes* la VM.
Para que los registros DNS no cambien jamás:

- Menú ☰ → **Networking → IP management → Reserved public IPs → Reserve a public IP**.
- Luego edita la instancia → **Attach** esa IP reservada.

Es gratuito en Free Tier mientras esté en uso.

## 5. Abrir puertos (Security List)

Oracle bloquea el tráfico entrante por defecto. Para nginx y SSH:

1. Menú ☰ → **Networking → Virtual cloud networks** → tu VCN.
2. → **Security Lists** → **Default Security List** → **Add Ingress Rules**.
3. Agrega (protocolo TCP), una por una:
   | Source | Puerto destino | Para |
   |---|---|---|
   | `0.0.0.0/0` | **80** | HTTP (nginx / certbot) |
   | `0.0.0.0/0` | **443** | HTTPS |
   | Tu IP de casa `/32` | **22** | SSH (o por Tailscale) |
   - **NUNCA** abras el **5432** (Postgres): la app no lo necesita expuesto al mundo.

## 6. Firewall interno de la instancia (¡no te lo saltes!)

Las imágenes **Ubuntu de Oracle traen un firewall interno (iptables)** que descarta casi todo
el tráfico entrante, aun con la Security List bien abierta. Si te conectas por SSH pero el
puerto 80 "no responde", es esto.

Conéctate a la VM y revisa:

```bash
sudo iptables -L INPUT -n --line-numbers
```

Si ves una regla que **RECHAZA/DROP** el resto del tráfico (muy probable), añade las reglas
**ACCEPT por encima de la línea de rechazo** a peso y luego persístelas:

```bash
sudo iptables -I INPUT 6 -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

> Ajusta el **6** al número de línea real de tu tabla (debe quedar ANTES de la regla de drop).
> Verifica después con `sudo iptables -L INPUT -n --line-numbers`.

## 7. Resumen / checklist al terminar

- [ ] Cuenta creada con región **Santiago**.
- [ ] VM **`eduscout-prod`** en estado **Running** con 4 OCPU / 24 GB A1 + Ubuntu 24.04.
- [ ] **IP pública** anotada (idealmente IP reservada).
- [ ] SSH funciona desde tu Mac: `ssh -i ~/.ssh/oracle_eduscout ubuntu@<IP>`.
- [ ] Security List con **80, 443 y 22** abiertos (sin 5432).
- [ ] iptables interno acepta 80/443 (sección 6).

Cuando la VM esté corriendo, pásame la **IP pública** y con eso continúo yo:
registros A en Cloudflare (`eduscout.cl` y `www`, modo DNS only), deploy del stack
(Postgres + backend + frontend + nginx), seed de las 12 fuentes, TLS con Let's Encrypt,
backups y prueba de scrape (fases B.2 a F5 de `docs/PRODUCCION.md`).

## 8. Solución de problemas frecuentes

| Problema | Qué hacer |
|---|---|
| Cuenta sin confirmar tras ~1 día | Revisa spam; reintenta el registro; contacta Oracle Sales por el chat de la consola. |
| "Out of host capacity" al crear A1 | Cambiar de AD, reintentar en horas de baja demanda o esperar días. |
| Tarjeta rechazada | Usa tarjeta **de crédito a tu nombre**; lee bien el país/CPF de la dirección. |
| SSH no conecta | Verifica en la instancia que tu IP es la correcta y que pegaste la clave correcta; revisa la Security List (22). |
| Puerto 80/443 no responde con SSH OK | Aplica la sección 6 (iptables de la imagen Ubuntu). |
| Oracle "detuvo" la VM a los 30 días | Creaste A1 por encima de 4 OCPU/24 GB en total; borra el exceso o cambia a Pay As You Go. |

## Notas legales / de uso

- Una cuenta gratuita por persona; no crees varias (Oracle cancela el arrendamiento).
- Usa datos reales y legítimos; Oracle verifica identidad.
- Cuentas inactivas 30+ días pueden considerarse abandonadas y suspendidas.
- La lista de regiones de Free Tier puede variar en el formulario de alta; si Santiago no aparece,
  escribe a Oracle Sales.