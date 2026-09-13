output "db_public_ip" {
  value = oci_core_instance.eduscout["db"].public_ip
}

output "app_public_ip" {
  value = oci_core_instance.eduscout["app"].public_ip
}