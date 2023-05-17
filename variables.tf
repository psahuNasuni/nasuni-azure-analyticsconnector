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

variable "output_path" {
  type        = string
  description = "function_path of file where zip file is stored"
  default     = "./ACSFunction.zip"
}

variable "networking_resource_group" {
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

variable "discovery_outbound_subnet" {
  description = "Available subnet name in Virtual Network"
  type        = list(string)
}

variable "nac_subnet" {
  description = "Subnet range from Virtual Network for NAC Deployment"
  type        = list(string)
}

variable "datasource_connection_string" {
  description = "Destination Storage Account Connection Stringe"
  type        = string
  default     = ""
}

variable "destination_container_name" {
  description = "Destination Storage Account Container Name"
  type        = string
  default     = ""
}