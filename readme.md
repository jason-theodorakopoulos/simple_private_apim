# Azure API Management – StandardV2 with Private Endpoint

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjason-theodorakopoulos%2Fsimple_private_apim%2Fmain%2Fazuredeploy.json)

This accelerator deploys an **Azure API Management (APIM) StandardV2** instance with **private connectivity** via a private endpoint in an existing virtual network.

> **DNS assumption:** The private DNS zone `privatelink.azure-api.net` and its DNS Zone Group (which auto-creates the A record for the private endpoint) are assumed to **already exist** and be managed externally — for example by Azure Policy or a centralised connectivity team following the **Cloud Adoption Framework (CAF)** hub-spoke model.

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

  DNS Zone Group & privatelink.azure-api.net assumed to exist
  (managed externally, e.g. Azure Policy / CAF connectivity hub)
```

## Prerequisites

| Prerequisite | Details |
|---|---|
| **Virtual Network** | An existing VNet with a subnet designated for private endpoints. |
| **Private DNS Zone** | `privatelink.azure-api.net` must already exist with a DNS Zone Group configured (e.g. via Azure Policy) so that A records are auto-created for private endpoints. |
| **VNet ↔ DNS Link** | The VNet (or its DNS resolver) must be linked to the private DNS zone so that clients can resolve the APIM private endpoint address. |
| **Permissions** | Contributor on the APIM resource group; Reader on the VNet resource group. |

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
| `publicNetworkAccess` | No | `Disabled` | Set to `Enabled` for hybrid (public + private) access. |

## Deployment behaviour – `publicNetworkAccess`

Azure does not allow `publicNetworkAccess` to be set to `Disabled` during the initial creation of an API Management service. To work around this, the template uses a **two-phase** approach:

1. **Phase 1** – The APIM service is created with `publicNetworkAccess: Enabled` and the private endpoint is provisioned.
2. **Phase 2** – A follow-up nested deployment updates the APIM service to set `publicNetworkAccess: Disabled` (when the parameter is set to `Disabled`, which is the default).

This is fully automated within a single `az deployment group create` invocation — no manual steps are required.

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
| `modules/apim-public-network-access.bicep` | Helper module that updates `publicNetworkAccess` after PE creation. |
| `azuredeploy.json` | Compiled ARM template used by the *Deploy to Azure* button. |
