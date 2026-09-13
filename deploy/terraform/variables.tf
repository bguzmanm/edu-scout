variable "region" {
  type    = string
  default = "sa-santiago-1"
}

variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  type = string
}

variable "fingerprint" {
  type = string
}

variable "private_key_path" {
  type    = string
  default = "~/.oci/oci_api_key.pem"
}

variable "compartment_ocid" {
  type    = string
  default = ""
}

variable "instance_db_display_name" {
  type    = string
  default = "eduscout-db"
}

variable "instance_app_display_name" {
  type    = string
  default = "eduscout-app"
}

variable "shape" {
  type    = string
  default = "VM.Standard.E2.1.Micro"
}

variable "boot_volume_size_in_gbs" {
  type    = number
  default = 50
}

variable "vcn_display_name" {
  type    = string
  default = "vcn_eduscout"
}

variable "subnet_display_name" {
  type    = string
  default = "subnet-eduscout"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/oracle_eduscout.pub"
}