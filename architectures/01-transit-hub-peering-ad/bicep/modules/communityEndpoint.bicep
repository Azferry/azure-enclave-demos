// Community endpoint: publishes a destination that enclaves may connect to.
// A PrivateNetwork rule bound to the transit hub exposes the corporate VNet
// (Active Directory) to enclaves that create an enclave connection to it.

param location string
param communityName string
param endpointName string

@description('Resource ID of the transit hub that reaches the corporate network.')
param transitHubResourceId string

@description('Comma-separated CIDR(s)/IP(s) in the corporate network that enclaves may reach.')
param destination string

param tags object = {}

resource community 'Microsoft.Mission/communities@2026-04-01' existing = {
  name: communityName
}

resource endpoint 'Microsoft.Mission/communities/communityEndpoints@2026-04-01' = {
  parent: community
  name: endpointName
  location: location
  tags: tags
  properties: {
    updateMode: 'Automatic'
    ruleCollection: [
      {
        endpointRuleName: 'corp-ad-domain-services'
        destinationType: 'PrivateNetwork'
        destination: destination
        transitHubResourceId: transitHubResourceId
        // DNS, Kerberos, NTP, RPC, NetBIOS, LDAP(S), SMB, kpasswd, Global Catalog, AD Web Services, RPC dynamic range
        ports: '53,88,123,135,137-139,389,445,464,636,3268-3269,9389,49152-65535'
        protocols: [
          'TCP'
          'UDP'
        ]
      }
      {
        endpointRuleName: 'corp-rdp-icmp'
        destinationType: 'PrivateNetwork'
        destination: destination
        transitHubResourceId: transitHubResourceId
        ports: '3389'
        protocols: [
          'TCP'
          'ICMP'
        ]
      }
    ]
  }
}

output endpointId string = endpoint.id
output endpointName string = endpoint.name
