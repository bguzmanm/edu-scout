resource "oci_core_instance" "eduscout" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = local.compartment_id
  display_name        = var.instance_display_name
  shape               = var.shape

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = local.ubuntu_image_id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    assign_public_ip = "true"
    display_name     = "eduscout-vnic"
    subnet_id        = local.subnet.id
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
  }
}