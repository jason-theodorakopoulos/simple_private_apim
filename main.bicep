// ============================================================================
// Azure API Management - Private AI Gateway Accelerator
// Deploys APIM (StandardV2 or Developer tier) with private connectivity via
// a private endpoint in an existing VNet. APIM is integrated into a dedicated
// subnet ('apim-subnet') for outbound VNet connectivity to backend services
// such as Azure AI Foundry LLMs. Creates a DNS Zone Group that references an
// existing private DNS zone (which may reside in another subscription /
// resource group) so that the private endpoint A record is registered
// automatically.
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

@description('SKU tier for the API Management instance.')
@allowed([
  'StandardV2'
  'Developer'
])
param skuName string = 'StandardV2'

@description('SKU capacity (scale units) for the APIM instance. Developer tier only supports a capacity of 1.')
@minValue(1)
param skuCapacity int = 1

@description('Name of the existing Virtual Network.')
param vnetName string

@description('Resource group name of the existing Virtual Network. Defaults to the current resource group.')
param vnetResourceGroupName string = resourceGroup().name

@description('Name of the existing subnet for private endpoints.')
param peSubnetName string = 'pe-subnet'

@description('Name of the existing subnet for APIM VNet integration (outbound connectivity to backends such as Azure AI Foundry).')
param apimSubnetName string = 'apim-subnet'

@description('VNet integration mode for APIM. External: gateway is internet-facing but connected to VNet for outbound. Internal: gateway is only accessible within the VNet.')
@allowed([
  'External'
  'Internal'
])
param virtualNetworkType string = 'External'

@description('Whether to disable public network access to the APIM gateway. Set to Enabled if you need hybrid access.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('Subscription ID where the existing private DNS zone resides. Defaults to the current subscription.')
param privateDnsZoneSubscriptionId string = subscription().subscriptionId

@description('Resource group name where the existing private DNS zone resides. Defaults to the current resource group.')
param privateDnsZoneResourceGroupName string = resourceGroup().name

@description('Name of the existing private DNS zone for APIM (e.g. privatelink.azure-api.net).')
param privateDnsZoneName string = 'privatelink.azure-api.net'

// ============================================================================
// Variables
// ============================================================================

var privateEndpointName = '${apimName}-pe'
var privateLinkServiceConnectionName = '${apimName}-plsc'

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

// Reference the existing APIM integration subnet
resource existingApimSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: apimSubnetName
  parent: existingVnet
}

// Reference the existing private DNS zone (may be in a different subscription and resource group)
resource existingPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDnsZoneName
  scope: resourceGroup(privateDnsZoneSubscriptionId, privateDnsZoneResourceGroupName)
}

// ============================================================================
// API Management Service
// ============================================================================

// Azure does not allow publicNetworkAccess = 'Disabled' during initial service
// creation. The service is always created with public access enabled; it is
// disabled in a follow-up module deployment after the private endpoint exists.
resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicNetworkAccess: 'Enabled'
    virtualNetworkType: virtualNetworkType
    virtualNetworkConfiguration: {
      subnetResourceId: existingApimSubnet.id
    }
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
// Private DNS Zone Group
// ============================================================================

// Creates a DNS Zone Group on the private endpoint so that the A record for
// the APIM gateway is automatically registered in the existing private DNS
// zone. The DNS zone may live in a different subscription and resource group
// (common in CAF hub-spoke topologies).
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  name: 'default'
  parent: apimPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azure-api-net'
        properties: {
          privateDnsZoneId: existingPrivateDnsZone.id
        }
      }
    ]
  }
}

// ============================================================================
// Disable Public Network Access (post-creation)
// ============================================================================

// Azure requires APIM to be created with public access enabled. This module
// updates the service to disable public access once the private endpoint is
// in place. The module is skipped when publicNetworkAccess is 'Enabled'.
module disablePublicAccess 'modules/apim-public-network-access.bicep' = if (publicNetworkAccess == 'Disabled') {
  name: 'disable-public-network-access'
  params: {
    apimName: apimName
    location: location
    publisherEmail: publisherEmail
    publisherName: publisherName
    skuName: skuName
    skuCapacity: skuCapacity
    publicNetworkAccess: 'Disabled'
    virtualNetworkType: virtualNetworkType
    apimSubnetId: existingApimSubnet.id
  }
  dependsOn: [
    apimPrivateEndpoint
  ]
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
