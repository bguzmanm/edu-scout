data "oci_identity_availability_domains" "ads" {
  compartment_id = local.compartment_id
}

data "oci_core_vcns" "existing" {
  compartment_id = local.compartment_id
  display_name   = var.vcn_display_name
}

data "oci_core_subnets" "existing" {
  compartment_id = local.compartment_id
  vcn_id         = data.oci_core_vcns.existing.virtual_networks[0].id
}

data "oci_core_images" "ubuntu" {
  compartment_id   = local.compartment_id
  operating_system = "Canonical Ubuntu"
  shape            = var.shape
  sort_by          = "TIMECREATED"
  sort_order       = "DESC"
}

locals {
  compartment_id  = var.compartment_ocid != "" ? var.compartment_ocid : var.tenancy_ocid
  subnets         = data.oci_core_subnets.existing.subnets
  subnet          = length([for s in local.subnets : s if s.display_name == var.subnet_display_name]) > 0 ? [for s in local.subnets : s if s.display_name == var.subnet_display_name][0] : [for s in local.subnets : s if s.prohibit_public_ip_on_vnic == false][0]
  ubuntu_images   = [for img in data.oci_core_images.ubuntu.images : img if length(regexall("^26\\.04", img.operating_system_version)) > 0]
  ubuntu_image_id = local.ubuntu_images[0].id
}