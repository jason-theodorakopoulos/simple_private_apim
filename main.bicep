// ============================================================================
// Azure API Management - Private AI Gateway Accelerator
// Deploys APIM as an AI gateway for Azure AI Foundry LLMs.
// Supports both StandardV2 and Developer SKUs with conditional networking.
//
// === StandardV2 Networking (VNet integration) ===
//   - Outbound:  VNet integration via a dedicated subnet delegated to
//                Microsoft.Web/serverFarms. APIM reaches private backends
//                (e.g. Azure AI Foundry endpoints) through the VNet.
//   - Inbound:   Private endpoint (Gateway sub-resource) so clients connect
//                over Private Link. Public access is disabled post-creation.
//   - Subnet:    Delegated to Microsoft.Web/serverFarms
//                NSG: outbound 443 to Storage + AzureKeyVault
//                /27 minimum, /24 recommended. Dedicated.
//   - Public IP: Not required.
//
// === Developer Networking (classic VNet injection — Internal mode) ===
//   - Full VNet injection: APIM is deployed inside the subnet with
//     Internal mode — gateway only accessible within the VNet.
//   - Outbound:  Traffic to backends flows through the VNet natively.
//   - Inbound:   Gateway accessible only within the VNet (private VIP).
//                Cross-VNet access via VNet peering.
//                PE is NOT supported with VNet-injected services.
//   - Subnet:    NO delegation (stv2 uses VMSS which conflicts with delegations)
//                NSG: inbound 3443 (ApiManagement tag), 443, 80;
//                     outbound 443 to Storage, SQL, AzureKeyVault, AzureAD.
//                /27 minimum, /29 usable. Dedicated.
//   - Public IP: Required (Standard SKU, Static, IPv4) for stv2 platform
//                management plane. Created automatically by this template.
//
// Prerequisites for the PE subnet ('pe-subnet') — StandardV2 only:
//   1. privateEndpointNetworkPolicies = Disabled
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

@description('Location for all resources. StandardV2 and Developer tiers have different region availability — see Azure docs for the latest supported regions.')
param location string = 'eastus'

@description('Name for the API Management service instance. Must be globally unique.')
@minLength(1)
@maxLength(50)
param apimName string

@description('Publisher email address for the APIM instance.')
param publisherEmail string

@description('Publisher organization name for the APIM instance.')
param publisherName string

@description('SKU tier for the API Management instance. StandardV2 uses VNet integration; Developer uses classic VNet injection.')
@allowed([
  'StandardV2'
  'Developer'
])
param skuName string = 'StandardV2'

@description('SKU capacity (scale units). Developer tier is limited to 1.')
@minValue(1)
param skuCapacity int = 1

@description('Name of the existing Virtual Network.')
param vnetName string

@description('Resource group name of the existing Virtual Network. Defaults to the current resource group.')
param vnetResourceGroupName string = resourceGroup().name

@description('Name of the existing subnet for private endpoints.')
param peSubnetName string = 'pe-subnet'

@description('Name of the existing subnet for APIM networking. For StandardV2: delegated to Microsoft.Web/serverFarms. For Developer: NO delegation (stv2 VMSS conflicts with delegations).')
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

// --- Azure AI Foundry parameters ---

@description('Name for the Azure AI Foundry account (CognitiveServices/accounts, kind: AIServices). Must be globally unique — also used as the custom subdomain.')
@minLength(2)
@maxLength(64)
param aiFoundryName string

@description('Name for the Azure AI Foundry project (child of the Foundry account).')
param aiProjectName string = '${aiFoundryName}-proj'

@description('Subscription ID where the existing Foundry private DNS zone resides. Defaults to the current subscription.')
param foundryPrivateDnsZoneSubscriptionId string = subscription().subscriptionId

@description('Resource group name where the existing Foundry private DNS zone resides. Defaults to the current resource group.')
param foundryPrivateDnsZoneResourceGroupName string = resourceGroup().name

@description('Name of the existing private DNS zone for Cognitive Services (e.g. privatelink.cognitiveservices.azure.com).')
param foundryPrivateDnsZoneName string = 'privatelink.cognitiveservices.azure.com'

// ============================================================================
// Variables
// ============================================================================

var privateEndpointName = '${apimName}-pe'
var privateLinkServiceConnectionName = '${apimName}-plsc'
var publicIpName = '${apimName}-pip'
var isDeveloper = skuName == 'Developer'
// Developer tier is hard-limited to capacity 1
var effectiveCapacity = isDeveloper ? 1 : skuCapacity

// --- Azure AI Foundry variables ---
var foundryPrivateEndpointName = '${aiFoundryName}-pe'
var foundryPrivateLinkServiceConnectionName = '${aiFoundryName}-plsc'
// Cognitive Services OpenAI User — lets APIM call the Foundry inference endpoint
var cognitiveServicesOpenAIUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

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

// Reference the existing Foundry private DNS zone (may be in a different subscription and resource group)
resource existingFoundryPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: foundryPrivateDnsZoneName
  scope: resourceGroup(foundryPrivateDnsZoneSubscriptionId, foundryPrivateDnsZoneResourceGroupName)
}

// ============================================================================
// Public IP Address (Developer tier only)
// ============================================================================

// Developer SKU with classic VNet injection (stv2) requires a public IP for
// the management plane. StandardV2 does not need one.
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = if (isDeveloper) {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: apimName
    }
  }
}

// ============================================================================
// API Management Service
// ============================================================================

// StandardV2: VNet integration (outbound only) — gateway on public infra,
//             outbound traffic to backends flows through the integrated subnet.
//             Uses External mode + PE for private inbound access.
// Developer:  Classic VNet injection — APIM fully placed in the subnet.
//             Uses Internal mode — gateway accessible only within VNet.
//             PE is NOT supported with VNet-injected services.
//
// publicNetworkAccess starts as 'Enabled' because Azure does not allow
// disabling it during initial creation — it is toggled off in a follow-up
// module deployment after the private endpoint exists (StandardV2 only).

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: {
    name: skuName
    capacity: effectiveCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicNetworkAccess: 'Enabled'
    publicIpAddressId: isDeveloper ? publicIp.id : null
    virtualNetworkType: isDeveloper ? 'Internal' : 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: existingApimSubnet.id
    }
  }
}

// ============================================================================
// Private Endpoint for APIM (StandardV2 only)
// ============================================================================

// Developer tier uses Internal VNet injection — PE is NOT supported.
// StandardV2 uses PE for private inbound access to the gateway.
resource apimPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = if (!isDeveloper) {
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
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = if (!isDeveloper) {
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
// Azure AI Foundry — Account + Project (project-based model, NOT hub-based)
// ============================================================================

// The new Foundry model uses CognitiveServices/accounts (kind: AIServices) with
// allowProjectManagement: true.  Projects are child resources of the account.
// This is NOT the classic hub-based model (MachineLearningServices/workspaces).

resource aiFoundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: aiFoundryName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  properties: {
    allowProjectManagement: true
    customSubDomainName: aiFoundryName
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: false
  }
}

resource aiFoundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  name: aiProjectName
  parent: aiFoundryAccount
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// ============================================================================
// Private Endpoint for Foundry
// ============================================================================

// Always created regardless of APIM SKU. Unlike APIM (which has VNet injection
// in Developer mode), Foundry is a PaaS service without VNet injection — it
// always needs a PE for private connectivity.
resource foundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: foundryPrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: existingPeSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: foundryPrivateLinkServiceConnectionName
        properties: {
          privateLinkServiceId: aiFoundryAccount.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

// ============================================================================
// Foundry Private DNS Zone Group
// ============================================================================

resource foundryDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  name: 'default'
  parent: foundryPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-cognitiveservices-azure-com'
        properties: {
          privateDnsZoneId: existingFoundryPrivateDnsZone.id
        }
      }
    ]
  }
}

// ============================================================================
// RBAC — APIM Managed Identity → Cognitive Services OpenAI User on Foundry
// ============================================================================

// Grants the APIM system-assigned managed identity permission to call the
// Foundry inference endpoint (chat completions, embeddings, etc.).
resource apimFoundryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryAccount.id, apimService.id, cognitiveServicesOpenAIUserRoleId)
  scope: aiFoundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRoleId)
    principalId: apimService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Disable Public Network Access (post-creation)
// ============================================================================

// Azure requires APIM to be created with public access enabled. This module
// updates the service to disable public access after provisioning.
// Only applies to StandardV2 — Developer cannot disable publicNetworkAccess
// because it requires at least one PE, and PEs are not supported with VNet
// injection. Developer Internal mode already makes the gateway VNet-only.
module disablePublicAccess 'modules/apim-public-network-access.bicep' = if (publicNetworkAccess == 'Disabled' && !isDeveloper) {
  name: 'disable-public-network-access'
  params: {
    apimName: apimName
    location: location
    publisherEmail: publisherEmail
    publisherName: publisherName
    skuName: skuName
    skuCapacity: effectiveCapacity
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

@description('Resource ID of the private endpoint (empty for Developer tier).')
output privateEndpointId string = isDeveloper ? '' : apimPrivateEndpoint.id

@description('Principal ID of the APIM system-assigned managed identity.')
output apimPrincipalId string = apimService.identity.principalId

// --- Azure AI Foundry outputs ---

@description('Resource ID of the Azure AI Foundry account.')
output aiFoundryAccountId string = aiFoundryAccount.id

@description('Name of the Azure AI Foundry account.')
output aiFoundryAccountName string = aiFoundryAccount.name

@description('Endpoint URL of the Azure AI Foundry account.')
output aiFoundryEndpoint string = aiFoundryAccount.properties.endpoint

@description('Name of the Azure AI Foundry project.')
output aiProjectName string = aiFoundryProject.name

@description('Resource ID of the Azure AI Foundry project.')
output aiProjectId string = aiFoundryProject.id

@description('Resource ID of the Foundry private endpoint.')
output foundryPrivateEndpointId string = foundryPrivateEndpoint.id
