// ============================================================================
// Parameter file for Azure API Management - Private AI Gateway Accelerator
// Update the values below to match your environment before deploying.
//
// SKU notes:
//   StandardV2 — VNet integration (outbound), PE (inbound).
//                Subnet delegated to Microsoft.Web/serverFarms.
//   Developer  — Classic VNet injection (full placement in subnet).
//                Subnet delegated to Microsoft.ApiManagement/service.
//                Capacity is always 1. Public IP created automatically.
// ============================================================================

using './main.bicep'

param location = 'eastus'

// Change to 'Developer' for dev/test with classic VNet injection.
param skuName = 'Developer'

param apimName = 'apim-myorg-001'

param publisherEmail = 'admin@contoso.com'

param publisherName = 'Contoso'

param skuCapacity = 1

param vnetName = 'vnet-hub-001'

param vnetResourceGroupName = 'apimrg'

param peSubnetName = 'snet-privateendpoints'

// For StandardV2: subnet delegated to Microsoft.Web/serverFarms
// For Developer:  NO delegation (stv2 VMSS conflicts with delegations)
param apimSubnetName = 'apim-subnet'

param publicNetworkAccess = 'Disabled'

param privateDnsZoneResourceGroupName = 'apimrg'

param privateDnsZoneName = 'privatelink.azure-api.net'
