########################################################
##  Developed By  :   Pradeepta Kumar Sahu
##  Project       :   Nasuni Azure Cognitive Search Integration
##  Organization  :   Nasuni Labs   
#########################################################

variable "acs_resource_group" {
  description = "Resouce group name for Azure Cognitive Search"
  type        = string
  default     = ""
}

variable "azure_location" {
  description = "Region for Azure Cognitive Search"
  type        = string
  default     = ""
}

variable "acs_key_vault" {
  description = "Azure Key Vault name for Azure Cognitive Search"
  type        = string
  default     = ""
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