resource "oci_core_instance" "eduscout" {
  for_each            = { db = var.instance_db_display_name, app = var.instance_app_display_name }
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = local.compartment_id
  display_name        = each.value
  shape               = var.shape

  source_details {
    source_type             = "image"
    source_id               = local.ubuntu_image_id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    assign_public_ip = "true"
    display_name     = "eduscout-${each.key}-vnic"
    subnet_id        = local.subnet.id
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
  }
}