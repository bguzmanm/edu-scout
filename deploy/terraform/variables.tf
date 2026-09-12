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

variable "instance_display_name" {
  type    = string
  default = "eduscout-prod"
}

variable "shape" {
  type    = string
  default = "VM.Standard.A1.Flex"
}

variable "ocpus" {
  type    = number
  default = 2
}

variable "memory_in_gbs" {
  type    = number
  default = 12
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