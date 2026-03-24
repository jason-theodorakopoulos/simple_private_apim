// ============================================================================
// Azure API Management - StandardV2 with Private Endpoint
// Deploys APIM StandardV2 with private connectivity via a private endpoint
// in an existing VNet. References existing private DNS zones in a separate
// subscription following the Cloud Adoption Framework (CAF) best practices.
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Location for all resources.')
@allowed([
  'australiaeast'
  'brazilsouth'
  'canadaeast'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'italynorth'
  'japaneast'
  'koreacentral'
  'norwayeast'
  'polandcentral'
  'southafricanorth'
  'southcentralus'
  'southindia'
  'spaincentral'
  'swedencentral'
  'switzerlandnorth'
  'uaenorth'
  'uksouth'
  'westeurope'
  'westus'
  'westus3'
])
param location string = 'eastus'

@description('Name for the API Management service instance. Must be globally unique.')
@minLength(1)
@maxLength(50)
param apimName string

@description('Publisher email address for the APIM instance.')
param publisherEmail string

@description('Publisher organization name for the APIM instance.')
param publisherName string

@description('SKU capacity (scale units) for the APIM StandardV2 instance.')
@minValue(1)
param skuCapacity int = 1

@description('Name of the existing Virtual Network.')
param vnetName string

@description('Resource group name of the existing Virtual Network. Defaults to the current resource group.')
param vnetResourceGroupName string = resourceGroup().name

@description('Name of the existing subnet for private endpoints.')
param peSubnetName string = 'pe-subnet'

@description('Subscription ID where existing private DNS zones are located (following CAF hub-spoke model). Defaults to the current subscription if not specified.')
param dnsZonesSubscriptionId string = subscription().subscriptionId

@description('Resource group name where existing private DNS zones are located.')
param dnsZonesResourceGroupName string

@description('Whether to disable public network access to the APIM gateway. Set to Enabled if you need hybrid access.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

// ============================================================================
// Variables
// ============================================================================

var privateDnsZoneName = 'privatelink.azure-api.net'
var privateEndpointName = '${apimName}-pe'
var privateLinkServiceConnectionName = '${apimName}-plsc'
var effectiveDnsSubscriptionId = dnsZonesSubscriptionId

// ============================================================================
// Existing Resources
// ============================================================================

// Reference the existing VNet (same subscription, potentially different resource group)
resource existingVnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroupName)
}

// Reference the existing PE subnet
resource existingPeSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: peSubnetName
  parent: existingVnet
}

// Reference the existing Private DNS Zone in the DNS subscription (CAF pattern)
resource existingPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDnsZoneName
  scope: resourceGroup(effectiveDnsSubscriptionId, dnsZonesResourceGroupName)
}

// ============================================================================
// API Management Service - StandardV2
// ============================================================================

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: {
    name: 'StandardV2'
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicNetworkAccess: publicNetworkAccess
  }
}

// ============================================================================
// Private Endpoint for APIM
// ============================================================================

resource apimPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: existingPeSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: privateLinkServiceConnectionName
        properties: {
          privateLinkServiceId: apimService.id
          groupIds: [
            'Gateway'
          ]
        }
      }
    ]
  }
}

// ============================================================================
// Private DNS Zone Group (links PE to existing DNS zone for automatic A record)
// ============================================================================

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  name: 'default'
  parent: apimPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(privateDnsZoneName, '.', '-')
        properties: {
          privateDnsZoneId: existingPrivateDnsZone.id
        }
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource ID of the APIM service.')
output apimServiceId string = apimService.id

@description('Name of the APIM service.')
output apimServiceName string = apimService.name

@description('Gateway URL of the APIM service.')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('Resource ID of the private endpoint.')
output privateEndpointId string = apimPrivateEndpoint.id

@description('Principal ID of the APIM system-assigned managed identity.')
output apimPrincipalId string = apimService.identity.principalId
