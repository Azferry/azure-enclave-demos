// Azure Enclave community: the top-level governance + networking boundary
// (Virtual WAN, Azure Firewall, policy, approvals) shared by all enclaves.

param location string

@description('Community name. Must start with a letter and contain only letters, numbers and hyphens.')
param communityName string

@description('Address space(s) from which enclave networks are allocated.')
param addressSpaces array

@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param firewallSku string = 'Standard'

@description('Optional custom DNS servers for the community (for example the AD DC IP after promotion). Leave empty for Azure DNS.')
param dnsServers array = []

@description('Object ID of the deploying principal. Empty = no explicit role assignment.')
param adminPrincipalId string = ''

@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param adminPrincipalType string = 'User'

param tags object = {}

var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// Hands-off demo: no approval workflow anywhere.
var notRequired = {
  approvalPolicy: 'NotRequired'
}

var baseProperties = {
  addressSpaces: addressSpaces
  firewallSku: firewallSku
  approvalSettings: {
    communityEndpointUpdate: notRequired
    enclaveEndpointUpdate: notRequired
    enclaveCreation: notRequired
    connectionCreation: notRequired
    connectionUpdate: notRequired
    communityMaintenanceMode: notRequired
    enclaveMaintenanceMode: notRequired
  }
}

var dnsProperties = empty(dnsServers) ? {} : { dnsServers: dnsServers }

var roleProperties = empty(adminPrincipalId)
  ? {}
  : {
      communityRoleAssignments: [
        {
          roleDefinitionId: contributorRoleId
          principals: [
            {
              id: adminPrincipalId
              type: adminPrincipalType
            }
          ]
        }
      ]
    }

resource community 'Microsoft.Mission/communities@2026-04-01' = {
  name: communityName
  location: location
  tags: tags
  properties: union(baseProperties, dnsProperties, roleProperties)
}

output communityId string = community.id
output communityName string = community.name
