# ---- Email Delivery (OCI) ----
# Provisiona el relay SMTP de OCI y las credenciales para el backend
# (recuperación de contraseña de postulantes vía nodemailer).
#
# Flujo tras aplicar:
#   1) Crear en Cloudflare los registros DNS del DKIM (ver output
#      email_dkim_*) y el SPF (v=spf1 include:rp.oracleemaildelivery.com ~all).
#   2) Esperar a que el DKIM quede en estado ACTIVE (minutos a ~1 día).
#   3) Llenar SMTP_HOST/SMTP_USER/SMTP_PASS en deploy/.env con los outputs
#      email_smtp_*, y SMTP_FROM con email_sender_address.

data "oci_email_configuration" "config" {
  # Requiere el OCID root (tenancy), no un sub-compartment.
  compartment_id = var.tenancy_ocid
}

locals {
  smtp_user_ocid = var.smtp_user_ocid != "" ? var.smtp_user_ocid : var.user_ocid
}

resource "oci_email_email_domain" "eduscout" {
  compartment_id = local.compartment_id
  name           = var.email_domain_name
}

resource "oci_email_dkim" "eduscout" {
  # Si el dominio aún no está ACTIVE, re-aplicar el plan cuando lo esté.
  email_domain_id = oci_email_email_domain.eduscout.id
  name            = "eduscout-dkim"
}

resource "oci_email_sender" "eduscout" {
  compartment_id = local.compartment_id
  email_address  = var.email_sender_address
}

resource "oci_identity_smtp_credential" "eduscout" {
  description = "EduScout Email Delivery (nodemailer)"
  user_id     = local.smtp_user_ocid
}

output "email_dkim_cname_name" {
  description = "CNAME name a crear en Cloudflare para DKIM"
  value       = oci_email_dkim.eduscout.dns_subdomain_name
}

output "email_dkim_cname_value" {
  description = "CNAME value a crear en Cloudflare para DKIM"
  value       = oci_email_dkim.eduscout.cname_record_value
}

output "email_sender_address" {
  description = "Approved sender (From) a usar en SMTP_FROM"
  value       = oci_email_sender.eduscout.email_address
}

output "email_smtp_host" {
  description = "SMTP_HOST para deploy/.env (puerto 587, STARTTLS)"
  value       = data.oci_email_configuration.config.smtp_submit_endpoint
}

output "email_smtp_username" {
  description = "SMTP_USER para deploy/.env"
  value       = oci_identity_smtp_credential.eduscout.username
}

output "email_smtp_password" {
  description = "SMTP_PASS para deploy/.env (queda en el state como sensitive)"
  sensitive   = true
  value       = oci_identity_smtp_credential.eduscout.password
}