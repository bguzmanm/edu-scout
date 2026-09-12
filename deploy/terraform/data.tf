data "oci_identity_availability_domains" "ads" {
  compartment_id = local.compartment_id
}

data "oci_core_subnets" "existing" {
  compartment_id = local.compartment_id
  display_name   = var.subnet_display_name
}

data "oci_core_images" "ubuntu" {
  compartment_id   = local.compartment_id
  operating_system = "Canonical Ubuntu"
  sort_by          = "TIMECREATED"
  sort_order       = "DESC"
}

locals {
  compartment_id  = var.compartment_ocid != "" ? var.compartment_ocid : var.tenancy_ocid
  subnet          = data.oci_core_subnets.existing.subnets[0]
  ubuntu_images   = [for img in data.oci_core_images.ubuntu.images : img if length(regexall("^26\\.04", img.operating_system_version)) > 0]
  ubuntu_image_id = local.ubuntu_images[0].id
}