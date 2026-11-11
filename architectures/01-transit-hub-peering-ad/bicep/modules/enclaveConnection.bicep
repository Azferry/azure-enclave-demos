// Enclave connection: opts an enclave in to a community endpoint. This is what
// programs the community firewall to allow enclave -> corporate AD traffic.

param location string
param connectionName string
param communityResourceId string

@description('Resource ID of the source enclave.')
param enclaveResourceId string

@description('Resource ID of the destination community endpoint.')
param communityEndpointId string

@description('Source CIDR inside the enclave that may use the endpoint (required by the API; e.g. the enclave address space).')
param sourceCidr string

param tags object = {}

resource connection 'Microsoft.Mission/enclaveConnections@2026-04-01' = {
  name: connectionName
  location: location
  tags: tags
  properties: {
    communityResourceId: communityResourceId
    sourceResourceId: enclaveResourceId
    destinationEndpointId: communityEndpointId
    sourceCidr: sourceCidr
  }
}

output connectionId string = connection.id
output connectionName string = connection.name
