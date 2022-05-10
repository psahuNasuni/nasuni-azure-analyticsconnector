########################################################
##  Developed By  :   Pradeepta Kumar Sahu
##  Project       :   Nasuni Azure Cognitive Search Integration
##  Organization  :   Nasuni Labs   
#########################################################

variable "acs_resource_group" {
  description = "Resouce group name for Azure Cognitive Search"
  type        = string
}

variable "azure_location" {
  description = "Region for Azure Cognitive Search"
  type        = string
}

variable "acs_key_vault" {
  description = "Azure Key Vault name for Azure Cognitive Search"
  type        = string
  default     = "nasuniacssecretstore"
}

variable "output_path" {
  type        = string
  description = "function_path of file where zip file is stored"
  default     = "./ACSFunction.zip"
}
