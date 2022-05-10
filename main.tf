 resource "null_resource" "provision_nac" {
   provisioner "local-exec" {
      command = "sh prov-nac.sh"
   }  
 }


data "archive_file" "test" {
  type        = "zip"
  source_dir  = "./ACSFunction"
  output_path = var.output_path
}


resource "azurerm_resource_group" "resource_group" {
  name     = "${var.acs_resource_group}"
  location = "eastus"
}


###### Integration of azure function with cognitive search ###############

resource "azurerm_storage_account" "storage_account" {
  name                     = "nasuninacsta"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  # allow_blob_public_access = true
}

resource "azurerm_application_insights" "app_insights" {
  name                = "${var.acs_resource_group}app-insights"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  application_type    = "web"
}


resource "azurerm_app_service_plan" "app_service_plan" {
  name                = "${var.acs_resource_group}-app-service-plan"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  kind                = "FunctionApp"
  reserved            = true # This has to be set to true for Linux. Not related to the Premium Plan
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}


resource "azurerm_function_app" "function_app" {
  name                = "${var.acs_resource_group}-function-app"
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
  os_type = "linux"
  site_config {
    linux_fx_version          = "Python|3.9"
    use_32_bit_worker_process = false
  }
  storage_account_name       = azurerm_storage_account.storage_account.name
  storage_account_access_key = azurerm_storage_account.storage_account.primary_access_key
  version                    = "~3"
  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_app_service_plan.app_service_plan
  ]
}

locals {
    publish_code_command = "az functionapp deployment source config-zip -g ${azurerm_resource_group.resource_group.name} -n ${azurerm_function_app.function_app.name} --src ${var.output_path}"
}

resource "null_resource" "function_app_publish" {
  provisioner "local-exec" {
    command = local.publish_code_command
  }
  depends_on = [ azurerm_function_app.function_app, local.publish_code_command]
  triggers = {
    input_json = filemd5(var.output_path)
    publish_code_command = local.publish_code_command
  }
}

output "function_app_default_hostname" {
  value = azurerm_function_app.function_app.default_hostname
}

data "azurerm_key_vault" "acs_key_vault" {
  name                = var.acs_key_vault
  resource_group_name = var.acs_resource_group
}

resource "azurerm_key_vault_secret" "search-endpoint" {
  name         = "search-endpoint-test"
  value        = "https://${azurerm_function_app.function_app.default_hostname}/api/SearchFunction"
  key_vault_id = data.azurerm_key_vault.acs_key_vault.id
}

