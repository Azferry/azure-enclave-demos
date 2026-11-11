// STAGE 2 - Connectivity (community resource group)
//   * Transit hub: peers the community hub to the corporate VNet
//   * Community endpoint: publishes the AD domain controller as a destination
//     enclaves can opt in to (AD ports + RDP/ICMP through the community firewall)

import { names } from 'modules/naming.bicep'

param location string = resourceGroup().location

@minLength(2)
@maxLength(8)
param prefix string = 'ave'

@description('Resource ID of the VNet to peer with. Empty = the stage 1 corporate VNet.')
param corpVnetId string = ''

@description('Destination(s) in the corporate network that enclaves may reach, e.g. the DC IP or identity subnet.')
param corpDestination string = '10.100.1.0/24'

param tags object = {
  demo: 'azure-virtual-enclaves'
  audience: 'demo'
}

var n = names(prefix, location)
var remoteVnetId = empty(corpVnetId)
  ? resourceId(subscription().subscriptionId, n.corpRg, 'Microsoft.Network/virtualNetworks', n.corpVnet)
  : corpVnetId

// This may time out due to the creation of the transit hub and its peering with the remote VNet. Rerunning or hardcoding the community endpoint will allow the deployment proceed 
module transitHub 'modules/transitHub.bicep' = {
  name: 'transit-hub'
  params: {
    location: location
    communityName: n.community
    transitHubName: n.transitHub
    remoteVirtualNetworkId: remoteVnetId
    tags: tags
  }
}

module endpoint 'modules/communityEndpoint.bicep' = {
  name: 'community-endpoint'
  params: {
    location: location
    communityName: n.community
    endpointName: n.communityEndpoint
    transitHubResourceId: transitHub.outputs.transitHubId
    // transitHubResourceId: '<transitHubResourceId>'
    destination: corpDestination
    tags: tags
  }
}

output transitHubId string = transitHub.outputs.transitHubId
// output transitHubId string = '<transitHubResourceId>'
output transitHubName string = transitHub.outputs.transitHubName
output communityEndpointId string = endpoint.outputs.endpointId
