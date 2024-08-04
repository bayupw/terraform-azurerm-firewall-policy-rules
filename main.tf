# Create 
module "hub" {
  source  = "bayupw/hub-vnet-azurefirewall/azurerm"
  version = "0.0.1"

  location           = "Australia East"
  rg_name            = "rg-bayu-hub-ae"
  vnet_name          = "bayu-hub-vnet-ae"
  vnet_address_space = ["10.100.0.0/23"]
  subnets = {
    AzureFirewallSubnet = {
      address_prefixes = ["10.100.0.0/26"]
    }
  }

  firewall_name        = "fw-hub-ae"
  firewall_sku_name    = "AZFW_VNet"
  firewall_sku_tier    = "Premium"
  firewall_dns_proxy   = true
  firewall_policy_name = "policy-azfw-ae"
}

# Load YAML inputs
locals {
  application_rules     = yamldecode(file("./yaml-input/application-rules-default.yaml"))
  network_rules_default = yamldecode(file("./yaml-input/network-rules-default.yaml"))
}

# Application Rules
resource "azurerm_firewall_policy_rule_collection_group" "application_rules" {
  name               = local.application_rules.name
  priority           = local.application_rules.priority
  firewall_policy_id = module.hub.azurerm_firewall_policy.id

  dynamic "application_rule_collection" {
    for_each = [local.application_rules.application_rule_collection]
    content {
      name     = application_rule_collection.value.name
      action   = application_rule_collection.value.action
      priority = application_rule_collection.value.priority

      dynamic "rule" {
        for_each = application_rule_collection.value.rules
        content {
          name        = rule.value.name
          description = rule.value.description

          dynamic "protocols" {
            for_each = rule.value.protocols
            content {
              type = protocols.value.type
              port = protocols.value.port
            }
          }

          source_addresses  = rule.value.source_addresses
          terminate_tls     = rule.value.terminate_tls
          destination_fqdns = rule.value.destination_fqdns
        }
      }
    }
  }
}

# Default Network Rules
resource "azurerm_firewall_policy_rule_collection_group" "network_rules_default" {
  name               = local.network_rules_default.name
  priority           = local.network_rules_default.priority
  firewall_policy_id = module.hub.azurerm_firewall_policy.id

  dynamic "network_rule_collection" {
    for_each = [local.network_rules_default.network_rule_collection]
    content {
      name     = network_rule_collection.value.name
      action   = network_rule_collection.value.action
      priority = network_rule_collection.value.priority

      # IP based rules
      dynamic "rule" {
        for_each = network_rule_collection.value.ip_rules
        content {
          name                  = rule.value.name
          source_addresses      = rule.value.source_addresses
          protocols             = rule.value.protocols
          destination_ports     = rule.value.destination_ports
          destination_addresses = rule.value.destination_addresses
        }
      }

      # FQDN rules requires DNS Proxy to be enabled in Azure Firewall
      dynamic "rule" {
        for_each = network_rule_collection.value.fqdn_rules
        content {
          name              = rule.value.name
          source_addresses  = rule.value.source_addresses
          protocols         = rule.value.protocols
          destination_ports = rule.value.destination_ports
          destination_fqdns = rule.value.destination_fqdns
        }
      }
    }
  }
}