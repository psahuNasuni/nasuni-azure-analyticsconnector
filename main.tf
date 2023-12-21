data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "resource_group" {
  ### Purpose: Function APP - NAC_Discovery function - Storage Accont for Function 
  name = var.service_name == "EXP" ? var.exp_resource_group : var.acs_resource_group
  # name = var.acs_resource_group
}

data "azurerm_app_configuration" "appconf" {
  count = var.service_name == "EXP" ? 0 : 1
  name                =  var.acs_admin_app_config_name
  resource_group_name = var.acs_resource_group 
}

########## START ::: Provision NAC_Discovery Function  #################

resource "random_id" "nac_unique_stack_id" {
  byte_length = 4
}

data "archive_file" "test" {
  type        = "zip"
  source_dir  = "./ACSFunction"
  output_path = var.output_path
}

data "azurerm_virtual_network" "VnetToBeUsed" {
  count               = var.use_private_acs == "Y" ? 1 : 0
  name                = var.user_vnet_name
  resource_group_name = var.networking_resource_group
}

data "azurerm_subnet" "azure_subnet_name" {
  count                = var.use_private_acs == "Y" ? 1 : 0
  name                 = var.user_subnet_name
  virtual_network_name = data.azurerm_virtual_network.VnetToBeUsed[0].name
  resource_group_name  = data.azurerm_virtual_network.VnetToBeUsed[0].resource_group_name
}

resource "azurerm_subnet" "discovery_outbound_subnet_name" {
  count                = var.use_private_acs == "Y" ? 1 : 0
  name                 = "outbound-vnetSubnet-${random_id.nac_unique_stack_id.hex}"
  virtual_network_name = data.azurerm_virtual_network.VnetToBeUsed[0].name
  resource_group_name  = data.azurerm_virtual_network.VnetToBeUsed[0].resource_group_name
  address_prefixes     = [var.discovery_outbound_subnet[0]]
  delegation {
    name = "serverFarms_delegation"

    service_delegation {
      name = "Microsoft.Web/serverFarms"
    }
  }
}

resource "azurerm_subnet" "nac_subnet_name" {
  count                = var.use_private_acs == "Y" ? length(var.nac_subnet) : 0
  name                 = "vnetSubnets-${count.index}"
  resource_group_name  = data.azurerm_virtual_network.VnetToBeUsed[0].resource_group_name
  virtual_network_name = data.azurerm_virtual_network.VnetToBeUsed[0].name
  address_prefixes     = [var.nac_subnet[count.index]]

  delegation {
    name = "serverFarms_delegation"

    service_delegation {
      name = "Microsoft.Web/serverFarms"
    }
  }

  depends_on = [
    azurerm_subnet.discovery_outbound_subnet_name
  ]
}

resource "null_resource" "update_subnet_name" {
  count = var.use_private_acs == "Y" ? length(var.nac_subnet) : 0
  provisioner "local-exec" {
    command = "echo \"vnetSubnetName-${count.index}: \"${azurerm_subnet.nac_subnet_name[count.index].name} >> config.dat"
  }
  depends_on = [
    azurerm_subnet.nac_subnet_name
  ]
  triggers = {
    input_json = var.nac_subnet[count.index]
  }
}

###### Storage Account for: Azure function NAC_Discovery in ACS Resource Group ###############

data "azurerm_private_dns_zone" "storage_account_dns_zone" {
  count               = var.use_private_acs == "Y" && var.service_name != "EXP" ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = data.azurerm_virtual_network.VnetToBeUsed[0].resource_group_name
}

resource "azurerm_storage_account" "storage_account" {
  name                     = "nasunist${random_id.nac_unique_stack_id.hex}"
  resource_group_name      = data.azurerm_resource_group.resource_group.name
  location                 = data.azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags

  depends_on = [
    null_resource.update_subnet_name,
    data.azurerm_private_dns_zone.storage_account_dns_zone
  ]
}

resource "null_resource" "disable_storage_public_access" {
  provisioner "local-exec" {
    command = var.use_private_acs == "Y" ? "az storage account update --allow-blob-public-access false --name ${azurerm_storage_account.storage_account.name} --resource-group ${azurerm_storage_account.storage_account.resource_group_name}" : "echo 'INFO ::: Destination Storage Account is Public...'"
  }
  depends_on = [azurerm_storage_account.storage_account]
}

resource "azurerm_private_endpoint" "storage_account_private_endpoint" {
  count               = var.use_private_acs == "Y" && var.service_name != "EXP" ? 1 : 0
  name                = "nasunist${random_id.nac_unique_stack_id.hex}_private_endpoint"
  location            = data.azurerm_virtual_network.VnetToBeUsed[0].location
  resource_group_name = data.azurerm_virtual_network.VnetToBeUsed[0].resource_group_name
  subnet_id           = data.azurerm_subnet.azure_subnet_name[0].id

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.storage_account_dns_zone[0].id]
  }

  private_service_connection {
    name                           = "nasunist${random_id.nac_unique_stack_id.hex}_connection"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.storage_account.id
    subresource_names              = ["blob"]
  }

  provisioner "local-exec" {
    command = "az resource wait --updated --ids ${self.subnet_id}"
  }

  depends_on = [
    data.azurerm_virtual_network.VnetToBeUsed,
    data.azurerm_subnet.azure_subnet_name,
    null_resource.disable_storage_public_access
  ]
}

###### App Insight for: Azure function NAC_Discovery in ACS Resource Group ###############

resource "azurerm_application_insights" "app_insights" {
  name                = "nasuni-app-insights-${random_id.nac_unique_stack_id.hex}"
  resource_group_name = data.azurerm_resource_group.resource_group.name
  location            = data.azurerm_resource_group.resource_group.location
  application_type    = "web"
  tags                = var.tags
}

###### App Service Plan for: Azure function NAC_Discovery in ACS Resource Group ###############

resource "azurerm_service_plan" "app_service_plan" {
  count = var.service_name == "EXP" ? 0 : 1
  name                = "nasuni-app-discovery-service-plan-${random_id.nac_unique_stack_id.hex}"
  resource_group_name = data.azurerm_resource_group.resource_group.name
  location            = data.azurerm_resource_group.resource_group.location
  os_type             = "Linux"
  sku_name            = "EP1"
  tags                = var.tags
}

###### Function App for: Azure function NAC_Discovery in ACS Resource Group ###############

data "azurerm_private_dns_zone" "discovery_function_app_dns_zone" {
  count               = var.use_private_acs == "Y" && var.service_name != "EXP" ? 1 : 0
  name                = "privatelink.azurewebsites.net"
  resource_group_name = data.azurerm_virtual_network.VnetToBeUsed[0].resource_group_name
}

resource "azurerm_linux_function_app" "discovery_function_app_private" {
  count               = var.use_private_acs == "Y" && var.service_name != "EXP" ? 1 : 0
  name                = "nasuni-function-app-${random_id.nac_unique_stack_id.hex}"
  resource_group_name = data.azurerm_resource_group.resource_group.name
  location            = data.azurerm_resource_group.resource_group.location
  service_plan_id     = azurerm_service_plan.app_service_plan[0].id
  tags                = var.tags
  app_settings = {
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true",
    "FUNCTIONS_WORKER_RUNTIME"       = "python",
    "AzureWebJobsDisableHomepage"    = "false"
  }
  identity {
    type = "SystemAssigned"
  }
  site_config {
    use_32_bit_worker        = false
    application_insights_key = azurerm_application_insights.app_insights.instrumentation_key
    cors {
      allowed_origins = ["*"]
    }
    application_stack {
      python_version = "3.9"
    }
    ip_restriction {
      action                    = "Allow"
      name                      = "https"
      priority                  = "310"
      virtual_network_subnet_id = data.azurerm_subnet.azure_subnet_name[0].id
    }
    scm_ip_restriction {
      action                    = "Allow"
      name                      = "https"
      priority                  = "310"
      virtual_network_subnet_id = data.azurerm_subnet.azure_subnet_name[0].id
    }
  }
  https_only                  = "true"
  storage_account_name        = azurerm_storage_account.storage_account.name
  storage_account_access_key  = azurerm_storage_account.storage_account.primary_access_key
  functions_extension_version = "~4"
  depends_on = [
    azurerm_private_endpoint.storage_account_private_endpoint,
    azurerm_service_plan.app_service_plan,
    azurerm_application_insights.app_insights,
    data.azurerm_private_dns_zone.discovery_function_app_dns_zone
  ]
}
resource "azurerm_linux_function_app" "discovery_function_app_public" {
  count               = var.use_private_acs == "Y" && var.service_name != "EXP" ? 0 : 1
  name                = "nasuni-function-app-${random_id.nac_unique_stack_id.hex}"
  resource_group_name = data.azurerm_resource_group.resource_group.name
  location            = data.azurerm_resource_group.resource_group.location
  service_plan_id     = var.service_name == "EXP" ? "" : azurerm_service_plan.app_service_plan[0].id
  tags                = var.tags
  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE"    = "1"
    "FUNCTIONS_WORKER_RUNTIME"    = "python",
    "AzureWebJobsDisableHomepage" = "false"
  }
  identity {
    type = "SystemAssigned"
  }
  site_config {
    use_32_bit_worker        = false
    application_insights_key = azurerm_application_insights.app_insights.instrumentation_key
    cors {
      allowed_origins = ["*"]
    }
    application_stack {
      python_version = "3.9"
    }
  }
  https_only                  = "true"
  storage_account_name        = azurerm_storage_account.storage_account.name
  storage_account_access_key  = azurerm_storage_account.storage_account.primary_access_key
  functions_extension_version = "~4"
  depends_on = [
    azurerm_private_endpoint.storage_account_private_endpoint,
    azurerm_service_plan.app_service_plan,
    azurerm_application_insights.app_insights,
    data.azurerm_private_dns_zone.discovery_function_app_dns_zone
  ]
}

resource "azurerm_private_endpoint" "discovery_function_app_private_endpoint" {
  count               = var.use_private_acs == "Y" && var.service_name != "EXP" ? 1 : 0
  name                = "nasuni-function-app-${random_id.nac_unique_stack_id.hex}_private_endpoint"
  location            = data.azurerm_virtual_network.VnetToBeUsed[0].location
  resource_group_name = data.azurerm_virtual_network.VnetToBeUsed[0].resource_group_name
  subnet_id           = data.azurerm_subnet.azure_subnet_name[0].id
  tags                = var.tags

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.discovery_function_app_dns_zone[0].id]
  }

  private_service_connection {
    name                           = "nasuni-function-app-${random_id.nac_unique_stack_id.hex}_connection"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_linux_function_app.discovery_function_app_private[0].id
    subresource_names              = ["sites"]
  }

  provisioner "local-exec" {
    command = "az resource wait --updated --ids ${self.subnet_id}"
  }

  depends_on = [
    azurerm_linux_function_app.discovery_function_app_private
  ]
}

resource "azurerm_app_service_virtual_network_swift_connection" "outbound_vnet_integration" {
  count          = var.use_private_acs == "Y" && var.service_name != "EXP" ? 1 : 0
  app_service_id = azurerm_linux_function_app.discovery_function_app_private[0].id
  subnet_id      = azurerm_subnet.discovery_outbound_subnet_name[0].id
  

  depends_on = [
    azurerm_subnet.discovery_outbound_subnet_name,
    azurerm_private_endpoint.discovery_function_app_private_endpoint
  ]
}

##### Locals: used for publishing NAC_Discovery Function ###############

locals {
  publish_code_command = "${var.service_name == "EXP" ? "" : ( var.use_private_acs == "Y" ? "az functionapp deployment source config-zip -g ${data.azurerm_resource_group.resource_group.name} -n ${azurerm_linux_function_app.discovery_function_app_private[0].name} --build-remote true --src ${var.output_path}" : "az functionapp deployment source config-zip -g ${data.azurerm_resource_group.resource_group.name} -n ${azurerm_linux_function_app.discovery_function_app_public[0].name} --build-remote true --src ${var.output_path}" )}"  
}


###### Publish : NAC_Discovery Function ###############
resource "null_resource" "function_app_publish" {
  count = var.service_name == "EXP" ? 0 : 1
  provisioner "local-exec" {
    command = var.use_private_acs == "Y" ? "sleep 15" : "echo 'INFO ::: Function app publish'"
  }
  provisioner "local-exec" {
    command = local.publish_code_command
  }
  depends_on = [
    azurerm_app_service_virtual_network_swift_connection.outbound_vnet_integration,
    local.publish_code_command
  ]
  triggers = {
    input_json           = filemd5(var.output_path)
    publish_code_command = local.publish_code_command
  }
}

########## END ::: Provision NAC_Discovery Function  ##########

########## START : Set Environmental Variable to NAC Discovery Function ##########

resource "null_resource" "set_env_variable" {
  count = var.service_name == "EXP" ? 0 : 1
  provisioner "local-exec" {
    command = var.use_private_acs == "Y" ? "az functionapp config appsettings set --name ${azurerm_linux_function_app.discovery_function_app_private[0].name} --resource-group ${data.azurerm_resource_group.resource_group.name} --settings AZURE_APP_CONFIG=\"${data.azurerm_app_configuration.appconf[0].primary_write_key[0].connection_string}\"" : "az functionapp config appsettings set --name ${azurerm_linux_function_app.discovery_function_app_public[0].name} --resource-group ${data.azurerm_resource_group.resource_group.name} --settings AZURE_APP_CONFIG=\"${data.azurerm_app_configuration.appconf[0].primary_write_key[0].connection_string}\""
  }
  depends_on = [
    null_resource.function_app_publish
  ]
}

########## END : Set Environmental Variable to NAC Discovery Function ##########

########## START : Provision NAC ###########################

resource "null_resource" "dos2unix" {
  provisioner "local-exec" {
    command     = "dos2unix ./nac-auth.sh"
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [
    data.azurerm_app_configuration.appconf,
    null_resource.set_env_variable
  ]
}

resource "null_resource" "provision_nac" {
  provisioner "local-exec" {
    command     = var.use_private_acs == "Y" ? "./nac-auth.sh ${azurerm_linux_function_app.discovery_function_app_private[0].default_hostname} ${var.acs_nmc_volume_name} ${var.nac_resource_group_name}" : "./nac-auth.sh ${azurerm_linux_function_app.discovery_function_app_public[0].default_hostname} ${var.acs_nmc_volume_name} ${var.nac_resource_group_name} ${var.service_name}"
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [
    null_resource.dos2unix,
    null_resource.function_app_publish
  ]
}

########### END : Provision NAC ###########################

output "FunctionAppSearchURL" {
  value = var.use_private_acs == "Y" && var.service_name != "EXP" ? "https://${azurerm_linux_function_app.discovery_function_app_private[0].default_hostname}/api/IndexFunction" : "https://${azurerm_linux_function_app.discovery_function_app_public[0].default_hostname}/api/IndexFunction"
}