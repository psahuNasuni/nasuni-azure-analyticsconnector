########################################################
##  Developed By  :   Pradeepta Kumar Sahu
##  Project       :   Nasuni Azure Cognitive Search Integration
##  Organization  :   Nasuni Labs   
#########################################################

variable "acs_resource_group" {
  description = "Resouce group name for Azure Cognitive Search"
  type        = string
  default     = "nasuni-labs-acs-rg"
}

variable "azure_location" {
  description = "Region for Azure Cognitive Search"
  type        = string
  default     = ""
}

variable "acs_admin_app_config_name" {
  description = "Azure acs_admin_app_config_name"
  type        = string
  default     = "nasuni-labs-acs-admin"
}

variable "web_access_appliance_address" {
  description = "Azure Web access appliance address"
  type        = string
  default     = ""
}

variable "nmc_volume_name" {
  description = "NMC Volume Name"
  type        = string
  default     = ""
}

variable "unifs_toc_handle" {
  description = "NMC Unifs TOC Handle"
  type        = string
  default     = ""
}

variable "output_path" {
  type        = string
  description = "function_path of file where zip file is stored"
  default     = "./ACSFunction.zip"
}

variable "user_resource_group_name" {
  description = "Resouce group name for Azure Function"
  type        = string
  default     = ""
}

variable "user_vnet_name" {
  description = "Virtual Network Name for Azure Function"
  type        = string
  default     = ""
}

variable "user_subnet_name" {
  description = "Available subnet name in Virtual Network"
  type        = string
  default     = ""
}

variable "use_private_acs" {
  description = "Use Private ACS"
  type        = string
  default     = "N"
}

variable "user_outbound_subnet_name" {
  description = "Available subnet name in Virtual Network"
  type        = string
  default     = ""
}