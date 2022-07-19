data "azurerm_client_config" "current" {}

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

resource "random_id" "nac_unique_stack_id" {
  byte_length = 6
}

resource "azurerm_resource_group" "resource_group" {
  name     = var.acs_resource_group
  location = var.azure_location
}

###### Integration of azure function with cognitive search ###############

resource "azurerm_storage_account" "storage_account" {
  name                     = "nasunist${random_id.nac_unique_stack_id.hex}"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  # allow_blob_public_access = true
}

resource "azurerm_application_insights" "app_insights" {
  name                = "nasuni-app-insights-${random_id.nac_unique_stack_id.hex}"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  application_type    = "web"
}


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

locals {
  publish_code_command = "az functionapp deployment source config-zip -g ${azurerm_resource_group.resource_group.name} -n ${azurerm_function_app.function_app.name} --src ${var.output_path}"
}

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

data "azurerm_key_vault" "acs_key_vault" {
  name                = var.acs_key_vault
  resource_group_name = var.acs_resource_group
}

resource "azurerm_key_vault_access_policy" "func_vault_id_mngmt" {
  key_vault_id = data.azurerm_key_vault.acs_key_vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_function_app.function_app.identity.0.principal_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore"
  ]

  depends_on = [data.azurerm_key_vault.acs_key_vault]
}


resource "azurerm_key_vault_secret" "search-endpoint" {
  name         = "search-endpoint-test"
  value        = "https://${azurerm_function_app.function_app.default_hostname}/api/IndexFunction"
  key_vault_id = data.azurerm_key_vault.acs_key_vault.id
}

resource "azurerm_key_vault_secret" "web-access-appliance-address" {
  name         = "web-access-appliance-address"
  value        = var.web_access_appliance_address
  key_vault_id = data.azurerm_key_vault.acs_key_vault.id
}

resource "azurerm_key_vault_secret" "nmc-volume-name" {
  name         = "nmc-volume-name"
  value        = var.nmc_volume_name
  key_vault_id = data.azurerm_key_vault.acs_key_vault.id
}

resource "azurerm_key_vault_secret" "unifs-toc-handle" {
  name         = "unifs-toc-handle"
  value        = var.unifs_toc_handle
  key_vault_id = data.azurerm_key_vault.acs_key_vault.id
}

# resource "null_resource" "execute_function" {
#   provisioner "local-exec" {
#     command = "curl https://${azurerm_function_app.function_app.default_hostname}/api/IndexFunction"
#   }

#   depends_on = [
#     null_resource.function_app_publish,
#     null_resource.set_key_vault_env_var,
#     azurerm_key_vault_access_policy.func_vault_id_mngmt,
#     azurerm_key_vault_secret.search-endpoint,
#     azurerm_key_vault_secret.web-access-appliance-address,
#     azurerm_key_vault_secret.nmc-volume-name,
#     azurerm_key_vault_secret.unifs-toc-handle
#   ]
# }

resource "null_resource" "set_key_vault_env_var" {
  provisioner "local-exec" {
    command = "az functionapp config appsettings set --name ${azurerm_function_app.function_app.name} --resource-group ${azurerm_resource_group.resource_group.name} --settings AZURE_KEY_VAULT=${data.azurerm_key_vault.acs_key_vault.name}"
  }
}

output "FunctionAppSearchURL" {
  value = "https://${azurerm_function_app.function_app.default_hostname}/api/IndexFunction"
}
