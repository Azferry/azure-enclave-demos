// Azure Bastion for console access to the corporate (non-enclave) VNet.

param location string
param bastionName string
param bastionSubnetId string

@allowed([
  'Basic'
  'Standard'
])
param sku string = 'Basic'

param tags object = {}

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-${bastionName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
}

output bastionId string = bastion.id
