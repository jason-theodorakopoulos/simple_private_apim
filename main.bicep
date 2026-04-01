// ============================================================================
// Azure API Management - Private AI Gateway Accelerator (StandardV2)
// Deploys APIM StandardV2 as an AI gateway for Azure AI Foundry LLMs.
//
// Networking model (StandardV2 "VNet integration", NOT classic VNet injection):
//   - Outbound:  VNet integration via a dedicated subnet delegated to
//                Microsoft.Web/serverFarms. This lets APIM reach private
//                backends (e.g. Azure AI Foundry endpoints) through the VNet.
//   - Inbound:   Private endpoint (Gateway sub-resource) so clients connect
//                over Private Link. Public access is disabled after the PE
//                is provisioned.
//
// Prerequisites for the APIM integration subnet ('apim-subnet'):
//   1. Delegated to Microsoft.Web/serverFarms
//   2. NSG attached with outbound rules for Storage (443) and
//      AzureKeyVault (443) at minimum
//   3. /27 minimum, /24 recommended
//   4. Dedicated – cannot be shared with other Azure resources
//
// Prerequisites for the PE subnet ('pe-subnet'):
//   1. privateEndpointNetworkPolicies = Disabled (or
//      NetworkSecurityGroupEnabled depending on policy)
//   2. No delegation required
//
// Creates a DNS Zone Group referencing an existing private DNS zone (which
// may reside in another subscription / resource group) so the private-
// endpoint A record is registered automatically.
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

@description('SKU tier for the API Management instance. StandardV2 supports VNet integration (outbound) and private endpoints (inbound).')
param skuName string = 'StandardV2'

@description('SKU capacity (scale units) for the APIM instance.')
@minValue(1)
param skuCapacity int = 1

@description('Name of the existing Virtual Network.')
param vnetName string

@description('Resource group name of the existing Virtual Network. Defaults to the current resource group.')
param vnetResourceGroupName string = resourceGroup().name

@description('Name of the existing subnet for private endpoints.')
param peSubnetName string = 'pe-subnet'

@description('Name of the existing subnet for APIM VNet integration (outbound connectivity to backends such as Azure AI Foundry). Must be delegated to Microsoft.Web/serverFarms.')
param apimSubnetName string = 'apim-subnet'

@description('Whether to disable public network access to the APIM gateway after the private endpoint is created.')
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
// API Management Service (StandardV2 with VNet integration)
// ============================================================================

// StandardV2 uses "VNet integration" (outbound only) — NOT classic VNet
// injection. The gateway remains publicly accessible; outbound traffic to
// backends flows through the integrated subnet.
// publicNetworkAccess starts as 'Enabled' because Azure does not allow
// disabling it during initial creation — it is toggled off in a follow-up
// module deployment after the private endpoint exists.
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
    virtualNetworkType: 'External'
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
