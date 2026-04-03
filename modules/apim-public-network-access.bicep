// ============================================================================
// Module: Update APIM publicNetworkAccess
// Re-deploys (PUT) the APIM service to set publicNetworkAccess after the
// private endpoint has been created. Azure does not allow disabling public
// access during the initial service creation.
//
// NOTE: ARM/Bicep only supports PUT (full resource deployment), not PATCH.
// All required properties — including VNet configuration — are passed
// through from the parent template to ensure an idempotent update.
// If APIM properties are modified outside of this template between
// deployments, those changes may be overwritten.
//
// Developer SKU uses classic VNet injection and requires a public IP for
// stv2 platform management. The publicIpAddressId parameter is only
// supplied when deploying the Developer tier.
// ============================================================================

@description('Name of the existing API Management service instance.')
param apimName string

@description('Location must match the existing APIM instance.')
param location string

@description('Publisher email address for the APIM instance.')
param publisherEmail string

@description('Publisher organization name for the APIM instance.')
param publisherName string

@description('SKU tier for the API Management instance.')
param skuName string

@description('SKU capacity (scale units) for the APIM instance.')
@minValue(1)
param skuCapacity int

@description('Whether to disable public network access to the APIM gateway.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string

@description('Resource ID of the APIM VNet integration subnet.')
param apimSubnetId string

@description('Resource ID of the public IP address for Developer SKU VNet injection. Leave empty for StandardV2.')
param publicIpAddressId string = ''

@description('VNet type: External for StandardV2, Internal for Developer.')
@allowed([
  'External'
  'Internal'
])
param virtualNetworkType string = 'External'

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
    publicNetworkAccess: publicNetworkAccess
    publicIpAddressId: !empty(publicIpAddressId) ? publicIpAddressId : null
    virtualNetworkType: virtualNetworkType
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
  }
}
