data "azurerm_client_config" "current" {}

data "azurerm_app_configuration" "appconf" {
  name                = var.acs_admin_app_config_name
  resource_group_name = var.acs_resource_group
}

########### START ::: Provision NAC_Discovery Function  #################
resource "random_id" "nac_unique_stack_id" {
  byte_length = 4
}

data "archive_file" "test" {
  type        = "zip"
  source_dir  = "./ACSFunction"
  output_path = var.output_path
}

resource "azurerm_resource_group" "resource_group" {
  ### Purpose: Function APP - NAC_Discovery function - Storage Accont for Function 
  name     = var.acs_resource_group
  location = var.azure_location
}

###### Storage Account for: Azure function NAC_Discovery in ACS Resource Group ###############
resource "azurerm_storage_account" "storage_account" {
  name                     = "nasunist${random_id.nac_unique_stack_id.hex}"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  # allow_blob_public_access = true
}

###### App Insight for: Azure function NAC_Discovery in ACS Resource Group ###############
resource "azurerm_application_insights" "app_insights" {
  name                = "nasuni-app-insights-${random_id.nac_unique_stack_id.hex}"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  application_type    = "web"
}

###### App Service Plan for: Azure function NAC_Discovery in ACS Resource Group ###############
resource "azurerm_app_service_plan" "app_service_plan" {
  name                = "nasuni-app-service-plan-${random_id.nac_unique_stack_id.hex}"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  kind                = "FunctionApp"
  reserved            = true # This has to be set to true for Linux. Not related to the Premium Plan
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

###### Function App for: Azure function NAC_Discovery in ACS Resource Group ###############
resource "azurerm_function_app" "function_app" {
  name                = "nasuni-function-app-${random_id.nac_unique_stack_id.hex}"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  app_service_plan_id = azurerm_app_service_plan.app_service_plan.id
  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE"       = "1",
    "FUNCTIONS_WORKER_RUNTIME"       = "python",
    "AzureWebJobsDisableHomepage"    = "false",
    "https_only"                     = "true",
    "APPINSIGHTS_INSTRUMENTATIONKEY" = "${azurerm_application_insights.app_insights.instrumentation_key}"
  }
  identity {
    type = "SystemAssigned"
  }
  os_type = "linux"
  site_config {
    linux_fx_version          = "Python|3.9"
    use_32_bit_worker_process = false
    cors {
      allowed_origins = ["*"]
    }
  }
  storage_account_name       = azurerm_storage_account.storage_account.name
  storage_account_access_key = azurerm_storage_account.storage_account.primary_access_key
  version                    = "~3"
  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_app_service_plan.app_service_plan
  ]
}

###### Locals: used for publishing NAC_Discovery Function ###############
locals {
  publish_code_command = "az functionapp deployment source config-zip -g ${azurerm_resource_group.resource_group.name} -n ${azurerm_function_app.function_app.name} --src ${var.output_path}"
}

###### Publish : NAC_Discovery Function ###############
resource "null_resource" "function_app_publish" {
  provisioner "local-exec" {
    command = local.publish_code_command
  }
  depends_on = [azurerm_function_app.function_app, local.publish_code_command]
  triggers = {
    input_json           = filemd5(var.output_path)
    publish_code_command = local.publish_code_command
  }
}
########### END ::: Provision NAC_Discovery Function  #################

########### START : Provision NAC ###########################

resource "null_resource" "provision_nac" {
  provisioner "local-exec" {
    command = "sh nac-auth.sh"
  }
}

########### END : Provision NAC ###########################

########### START : Create and Update Key-Vault index-endpoint ###########################

# resource "azurerm_app_configuration_key" "datasource_connection_string" {
#   configuration_store_id = data.azurerm_app_configuration.appconf.id
#   key                    = "datasource-connection-string"
#   label                  = "datasource-connection-string"
#   value                  = var.datasource_connection_string
# }

resource "azurerm_app_configuration_key" "index-endpoint" {
  configuration_store_id = data.azurerm_app_configuration.appconf.id
  key         = "index-endpoint"
  label       = "index-endpoint"
  value        = "https://${azurerm_function_app.function_app.default_hostname}/api/IndexFunction"
}

resource "azurerm_app_configuration_key" "web-access-appliance-address" {
  configuration_store_id = data.azurerm_app_configuration.appconf.id
  key         = "web-access-appliance-address"
  label       = "web-access-appliance-address"
  value       = var.web_access_appliance_address
}

resource "azurerm_app_configuration_key" "nmc-volume-name" {
  configuration_store_id = data.azurerm_app_configuration.appconf.id
  key         = "nmc-volume-name"
  label         = "nmc-volume-name"
  value        = var.nmc_volume_name
}

resource "azurerm_app_configuration_key" "unifs-toc-handle" {
  configuration_store_id = data.azurerm_app_configuration.appconf.id
  key         = "unifs-toc-handle"
  label       = "unifs-toc-handle"
  value       = var.unifs_toc_handle
}
########### END : Create and Update Key-Vault index-endpoint ###########################

###### Setting Environment Variables for Azure Indexing Function ###############
resource "null_resource" "set_key_vault_env_var" {
  provisioner "local-exec" {
    command = "az functionapp config appsettings set --name ${azurerm_function_app.function_app.name} --resource-group ${azurerm_resource_group.resource_group.name} --settings ACS_ADMIN_APP_CONFIG_CONNECTION_STRING=${data.azurerm_app_configuration.appconf.primary_write_key[0].connection_string}"
  }
}
###### END ::: Setting Environment Variables for Azure Indexing Function ###############

output "FunctionAppSearchURL" {
  value = "https://${azurerm_function_app.function_app.default_hostname}/api/IndexFunction"
}
