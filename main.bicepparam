// ============================================================================
// Parameter file for Azure API Management - Private Endpoint Accelerator
// Update the values below to match your environment before deploying.
// ============================================================================

using './main.bicep'

param location = 'eastus'

param skuName = 'StandardV2'

param apimName = 'apim-myorg-001'

param publisherEmail = 'admin@contoso.com'

param publisherName = 'Contoso'

param skuCapacity = 1

param vnetName = 'vnet-hub-001'

param vnetResourceGroupName = 'rg-networking'

param peSubnetName = 'snet-privateendpoints'

param publicNetworkAccess = 'Disabled'

param privateDnsZoneSubscriptionId = '<connectivity-subscription-id>'

param privateDnsZoneResourceGroupName = 'rg-connectivity-dns'

param privateDnsZoneName = 'privatelink.azure-api.net'
