// Virtual enclave: an isolated, policy-governed network + resource boundary
// carved out of the community address space.

param location string
param enclaveName string

@description('Resource ID of the parent community.')
param communityResourceId string

@description('Enclave network size (small | medium | large) used when customCidrRange is empty.')
param networkSize string = 'small'

@description('Optional explicit CIDR for the enclave (must be inside the community address space). Empty = auto-allocate.')
param customCidrRange string = ''

param subnetName string = 'snet-workload'

@minValue(24)
@maxValue(29)
param subnetPrefixSize int = 26

param bastionEnabled bool = true

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

var notRequired = {
  approvalPolicy: 'NotRequired'
}

var adminRoleAssignments = empty(adminPrincipalId)
  ? []
  : [
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

var vnetBase = {
  networkSize: networkSize
  allowSubnetCommunication: true
  subnetConfigurations: [
    {
      subnetName: subnetName
      networkPrefixSize: subnetPrefixSize
    }
  ]
}

resource enclave 'Microsoft.Mission/virtualEnclaves@2026-04-01' = {
  name: enclaveName
  location: location
  tags: tags
  properties: {
    communityResourceId: communityResourceId
    enclaveVirtualNetwork: union(vnetBase, empty(customCidrRange) ? {} : { customCidrRange: customCidrRange })
    bastionEnabled: bastionEnabled
    approvalSettings: {
      enclaveEndpointUpdate: notRequired
      connectionCreation: notRequired
      connectionUpdate: notRequired
      enclaveMaintenanceMode: notRequired
    }
    enclaveRoleAssignments: adminRoleAssignments
    workloadRoleAssignments: adminRoleAssignments
  }
}

output enclaveId string = enclave.id
output enclaveName string = enclave.name
output subnetResourceId string = enclave.properties.enclaveVirtualNetwork.subnetConfigurations[0].?subnetResourceId ?? ''
output subnetAddressPrefix string = enclave.properties.enclaveVirtualNetwork.subnetConfigurations[0].?addressPrefix ?? ''
output enclaveAddressSpace string = enclave.properties.?enclaveAddressSpaces.?enclaveAddressSpace ?? ''
output managedResourceGroupName string = enclave.properties.?managedResourceGroupName ?? ''
