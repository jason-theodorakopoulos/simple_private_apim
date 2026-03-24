# Azure API Management – StandardV2 with Private Endpoint

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjason-theodorakopoulos%2Fsimple_private_apim%2Fmain%2Fazuredeploy.json)

This accelerator deploys an **Azure API Management (APIM) StandardV2** instance with **private connectivity** via a private endpoint in an existing virtual network. It follows the **Cloud Adoption Framework (CAF)** pattern where private DNS zones reside in a centralised connectivity subscription.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  APIM Subscription                                          │
│                                                             │
│  ┌───────────────────┐    ┌──────────────────────────────┐  │
│  │  API Management   │◄───│  Private Endpoint            │  │
│  │  (StandardV2)     │    │  (in existing PE subnet)     │  │
│  │  publicAccess:Off │    └──────────┬───────────────────┘  │
│  └───────────────────┘               │                      │
│                             ┌────────┴────────┐             │
│                             │  Existing VNet  │             │
│                             │  & PE Subnet    │             │
│                             └─────────────────┘             │
└─────────────────────────────────────────────────────────────┘
                                       │
                              DNS Zone Group
                                       │
┌─────────────────────────────────────────────────────────────┐
│  DNS Zones Subscription (CAF Connectivity)                  │
│                                                             │
│  ┌─────────────────────────────────────────┐                │
│  │  privatelink.azure-api.net (existing)   │                │
│  └─────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

| Prerequisite | Details |
|---|---|
| **Virtual Network** | An existing VNet with a subnet designated for private endpoints. |
| **Private DNS Zone** | `privatelink.azure-api.net` must already exist in the DNS zones subscription. |
| **VNet ↔ DNS Link** | The VNet (or its DNS resolver) must be linked to the private DNS zone so that clients can resolve the APIM private endpoint address. |
| **Permissions** | Contributor on the APIM resource group; Reader on the VNet resource group; Private DNS Zone Contributor on the DNS zones resource group. |

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `location` | No | `eastus` | Azure region (restricted to regions that support StandardV2). |
| `apimName` | **Yes** | — | Globally unique name for the APIM instance. |
| `publisherEmail` | **Yes** | — | Publisher email address shown in the developer portal. |
| `publisherName` | **Yes** | — | Publisher organisation name. |
| `skuCapacity` | No | `1` | Number of StandardV2 scale units. |
| `vnetName` | **Yes** | — | Name of the existing VNet. |
| `vnetResourceGroupName` | No | current RG | Resource group that contains the VNet. |
| `peSubnetName` | No | `pe-subnet` | Subnet name for the private endpoint. |
| `dnsZonesSubscriptionId` | No | current subscription | Subscription ID where `privatelink.azure-api.net` lives. |
| `dnsZonesResourceGroupName` | **Yes** | — | Resource group that contains the private DNS zone. |
| `publicNetworkAccess` | No | `Disabled` | Set to `Enabled` for hybrid (public + private) access. |

## Deploy

### Option 1 – Azure Portal (Deploy to Azure button)

Click the button at the top of this page, fill in the parameters and deploy.

### Option 2 – Azure CLI

```bash
az deployment group create \
  --resource-group <resource-group> \
  --template-file main.bicep \
  --parameters main.bicepparam
```

> **Tip:** Edit `main.bicepparam` with your actual values before running the command.

### Option 3 – Azure PowerShell

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName <resource-group> `
  -TemplateFile main.bicep `
  -TemplateParameterFile main.bicepparam
```

## Outputs

| Output | Description |
|---|---|
| `apimServiceId` | Resource ID of the APIM service. |
| `apimServiceName` | Name of the APIM service. |
| `apimGatewayUrl` | Gateway URL (e.g. `https://<name>.azure-api.net`). |
| `privateEndpointId` | Resource ID of the private endpoint. |
| `apimPrincipalId` | Object ID of the APIM system-assigned managed identity. |

## Files

| File | Purpose |
|---|---|
| `main.bicep` | Bicep template (source of truth). |
| `main.bicepparam` | Bicep native parameter file – edit with your values. |
| `azuredeploy.json` | Compiled ARM template used by the *Deploy to Azure* button. |
