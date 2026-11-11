// STAGE 3 - Enclave (enclave resource group)
//   * Virtual enclave inside the community
//   * Workload that links a (new, RP-created) resource group to the enclave
//   * Enclave connection to the community endpoint that fronts corporate AD

import { names } from 'modules/naming.bicep'

param location string = resourceGroup().location

@minLength(2)
@maxLength(8)
param prefix string = 'ave'

@description('Resource ID of the community. Empty = the stage 1 community.')
param communityId string = ''

@description('Resource ID of the community endpoint. Empty = the stage 2 endpoint.')
param communityEndpointId string = ''

param enclaveNetworkSize string = 'small'

@description('Optional explicit enclave CIDR inside the community range. Empty = auto-allocate.')
param enclaveCustomCidr string = ''

param enclaveBastionEnabled bool = true

@description('Source CIDR for the enclave connection. Empty = the enclave custom CIDR if set, otherwise the allocated enclave address space.')
param enclaveConnectionSourceCidr string = ''

param adminPrincipalId string = ''

@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param adminPrincipalType string = 'User'

param tags object = {
  demo: 'azure-virtual-enclaves'
  audience: 'demo'
}

var n = names(prefix, location)
var subId = subscription().subscriptionId
var resolvedCommunityId = empty(communityId)
  ? resourceId(subId, n.communityRg, 'Microsoft.Mission/communities', n.community)
  : communityId
var resolvedEndpointId = empty(communityEndpointId)
  ? resourceId(subId, n.communityRg, 'Microsoft.Mission/communities/communityEndpoints', n.community, n.communityEndpoint)
  : communityEndpointId

module enclave 'modules/enclave.bicep' = {
  name: 'enclave'
  params: {
    location: location
    enclaveName: n.enclave
    communityResourceId: resolvedCommunityId
    networkSize: enclaveNetworkSize
    customCidrRange: enclaveCustomCidr
    bastionEnabled: enclaveBastionEnabled
    adminPrincipalId: adminPrincipalId
    adminPrincipalType: adminPrincipalType
    tags: tags
  }
}

module workload 'modules/workload.bicep' = {
  name: 'workload'
  params: {
    location: location
    enclaveName: enclave.outputs.enclaveName
    workloadName: n.workload
    resourceGroupNames: [
      n.workloadRg
    ]
    tags: tags
  }
}

module connection 'modules/enclaveConnection.bicep' = {
  name: 'enclave-connection'
  params: {
    location: location
    connectionName: n.enclaveConnection
    communityResourceId: resolvedCommunityId
    enclaveResourceId: enclave.outputs.enclaveId
    communityEndpointId: resolvedEndpointId
    sourceCidr: !empty(enclaveConnectionSourceCidr)
      ? enclaveConnectionSourceCidr
      : (!empty(enclaveCustomCidr) ? enclaveCustomCidr : enclave.outputs.enclaveAddressSpace)
    tags: tags
  }
}

output enclaveId string = enclave.outputs.enclaveId
output enclaveName string = enclave.outputs.enclaveName
output enclaveSubnetId string = enclave.outputs.subnetResourceId
output enclaveAddressSpace string = enclave.outputs.enclaveAddressSpace
output enclaveManagedResourceGroup string = enclave.outputs.managedResourceGroupName
output workloadId string = workload.outputs.workloadId
output workloadResourceGroup string = n.workloadRg
output enclaveConnectionId string = connection.outputs.connectionId
