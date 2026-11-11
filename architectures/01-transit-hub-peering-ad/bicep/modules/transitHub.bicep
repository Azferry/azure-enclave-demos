// Transit hub: a vHub in the community Virtual WAN that connects the
// community to a network OUTSIDE the enclave boundary. Here: VNet peering
// to the generic corporate VNet that hosts Active Directory.

param location string
param communityName string
param transitHubName string

@description('Resource ID of the remote (corporate) VNet to peer with.')
param remoteVirtualNetworkId string

@description('Desired transit hub state. Community owners can create the hub directly in the Approved state.')
@allowed([
  'Approved'
  'PendingApproval'
])
param state string = 'Approved'

param tags object = {}

resource community 'Microsoft.Mission/communities@2026-04-01' existing = {
  name: communityName
}

resource transitHub 'Microsoft.Mission/communities/transitHubs@2026-04-01' = {
  parent: community
  name: transitHubName
  location: location
  tags: tags
  properties: {
    state: state
    securityProvider: 'AzureFirewall'
    transitOption: {
      type: 'Peering'
      params: {
        remoteVirtualNetworkId: remoteVirtualNetworkId
      }
    }
  }
}

output transitHubId string = transitHub.id
output transitHubName string = transitHub.name
