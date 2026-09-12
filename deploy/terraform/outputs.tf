output "instance_public_ip" {
  value = oci_core_instance.eduscout.public_ip
}

output "instance_ocpu_memory" {
  value = "${oci_core_instance.eduscout.shape_config[0].ocpus} OCPU / ${oci_core_instance.eduscout.shape_config[0].memory_in_gbs} GB"
}