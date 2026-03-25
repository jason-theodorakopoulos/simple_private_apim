// ============================================================================
// Module: Update APIM publicNetworkAccess
// Re-deploys the APIM service to set publicNetworkAccess after the private
// endpoint has been created. Azure does not allow disabling public access
// during the initial service creation.
// ============================================================================

@description('Name of the existing API Management service instance.')
param apimName string

@description('Location must match the existing APIM instance.')
param location string

@description('Publisher email address for the APIM instance.')
param publisherEmail string

@description('Publisher organization name for the APIM instance.')
param publisherName string

@description('SKU capacity (scale units) for the APIM StandardV2 instance.')
@minValue(1)
param skuCapacity int

@description('Whether to disable public network access to the APIM gateway.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string

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
