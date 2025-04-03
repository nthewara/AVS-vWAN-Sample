#test
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
    }
  }
}

variable "prefix" {
  type    = string
  default = "ntavsri"
}

variable "location" {
  type    = string
  default = "australiaeast"

}




variable "avserid" {
  type = string
}

variable "avserkey" {
  type = string
}

variable "vnetconfig" {
  type = object({
    vhub1ip  = string
    vhub2ip = string
    vhub3ip = string
    vnet1ip  = string
    vnet2ip  = string
    evnet1ip = string
    ivnet1ip = string
    vnet3ip  = string
    vnet4ip  = string
    vnet5ip  = string
  })
}


resource "random_string" "random" {
  length  = 4
  lower   = true
  special = false
  numeric  = false
  upper   = false
}


# Configure the Microsoft Azure Provider
provider "azurerm" {
  subscription_id = ""
  features {}
  use_oidc = true
}

# Create a resource group
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-${random_string.random.result}"
  location = var.location
}

resource "azurerm_virtual_wan" "vwan" {
  name                = "${var.prefix}-vwan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

#create vhub1
resource "azurerm_virtual_hub" "vhub1" {
  name                = "${var.prefix}-vhub1"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  virtual_wan_id      = azurerm_virtual_wan.vwan.id
  address_prefix      = "${var.vnetconfig.vhub1ip}.0/23"
}

resource "azurerm_firewall_policy_rule_collection_group" "fwpol-rulecol1" {
  name               = "fwpol-rulecol1"
  firewall_policy_id = azurerm_firewall_policy.fwpol-vwan1.id
  priority           = 500
  network_rule_collection {
    name     = "AllowAll"
    priority = 400
    action   = "Allow"
    rule {
      name                  = "network_rule_collection1_rule1"
      protocols             = ["Any"]
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["*"]
    }
  }
}

resource "azurerm_firewall" "fwvhub1" {
  name                = "${var.prefix}-fwvhub1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  firewall_policy_id = azurerm_firewall_policy.fwpol-vwan1.id
  sku_name = "AZFW_Hub"
  sku_tier = "Standard"
  virtual_hub {
     virtual_hub_id = azurerm_virtual_hub.vhub1.id
  }
}

resource "azurerm_firewall_policy" "fwpol-vwan1" {
  name                            = "${var.prefix}-fwpol-vwan1"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
}


resource "azurerm_express_route_gateway" "ergw1" {
  name                = "${var.prefix}-ergwvhub1"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  virtual_hub_id      = azurerm_virtual_hub.vhub1.id
  scale_units         = 1
}

resource "azurerm_virtual_hub_routing_intent" "fwvhub1ri" {
  name                = "${var.prefix}-fwvhub1ri"
  virtual_hub_id      = azurerm_virtual_hub.vhub1.id
  routing_policy {
   name = "InternetTrafficPolicy"
   destinations = ["Internet"]
   next_hop = azurerm_firewall.fwvhub1.id
  }  
}

resource "azurerm_log_analytics_workspace" "loga" {
  name                = "${var.prefix}-log-analytics-workspace"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_storage_account" "storageaccount" {
  name                     = "${var.prefix}stg771266998"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}


data "azurerm_monitor_diagnostic_categories" "fw" {
  resource_id = azurerm_firewall.fwvhub1.id
}

resource "azurerm_monitor_diagnostic_setting" "fw" {
  name                       = "diagnostic_setting"
  target_resource_id         = data.azurerm_monitor_diagnostic_categories.fw.resource_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.loga.id
  storage_account_id = azurerm_storage_account.storageaccount.id
  log_analytics_destination_type = "Dedicated"
  dynamic "metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.fw.metrics
    content {
      category = metric.value      
    }
  }

  dynamic "enabled_log" {
    for_each = data.azurerm_monitor_diagnostic_categories.fw.log_category_types
    content {
      category = enabled_log.value
    }
  }
}
resource "azurerm_express_route_connection" "erc-con1" {
  name                             = "${var.prefix}-erccon1"
  express_route_gateway_id         = azurerm_express_route_gateway.ergw1.id
  express_route_circuit_peering_id = "${var.avserid}/peerings/AzurePrivatePeering"
  authorization_key = var.avserkey
  enable_internet_security = true
}
