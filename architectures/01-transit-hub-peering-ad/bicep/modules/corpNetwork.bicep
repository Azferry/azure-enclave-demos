// Generic "corporate" VNet that lives OUTSIDE the enclave boundary.
// It hosts the Active Directory VM and is peered to the community transit hub.

@description('Azure region.')
param location string

@description('Name of the corporate VNet.')
param vnetName string

@description('Address space of the corporate VNet. Must not overlap the community address space.')
param addressPrefix string

@description('Subnet that hosts the Active Directory / identity VM.')
param identitySubnetPrefix string

@description('AzureBastionSubnet prefix (/26 or larger).')
param bastionSubnetPrefix string

@description('Community address space(s). Traffic from enclaves arrives from these ranges via the transit hub.')
param communityAddressSpaces array

param tags object = {}

var adTcpPorts = [
  '53'
  '88'
  '135'
  '139'
  '389'
  '445'
  '464'
  '636'
  '3268-3269'
  '9389'
  '49152-65535'
]
var adUdpPorts = [
  '53'
  '88'
  '123'
  '137-138'
  '389'
  '464'
]

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${vnetName}-identity'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Enclave-AD-TCP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefixes: communityAddressSpaces
          sourcePortRange: '*'
          destinationAddressPrefix: identitySubnetPrefix
          destinationPortRanges: adTcpPorts
          description: 'AD DS / DNS / Kerberos / LDAP / SMB / RPC from enclave workloads (via transit hub).'
        }
      }
      {
        name: 'Allow-Enclave-AD-UDP'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Udp'
          sourceAddressPrefixes: communityAddressSpaces
          sourcePortRange: '*'
          destinationAddressPrefix: identitySubnetPrefix
          destinationPortRanges: adUdpPorts
          description: 'AD DS / DNS / Kerberos / NTP / NetBIOS from enclave workloads (via transit hub).'
        }
      }
      {
        name: 'Allow-Enclave-RDP'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefixes: communityAddressSpaces
          sourcePortRange: '*'
          destinationAddressPrefix: identitySubnetPrefix
          destinationPortRange: '3389'
          description: 'RDP from enclave workloads (demo only).'
        }
      }
      {
        name: 'Allow-Enclave-ICMP'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Icmp'
          sourceAddressPrefixes: communityAddressSpaces
          sourcePortRange: '*'
          destinationAddressPrefix: identitySubnetPrefix
          destinationPortRange: '*'
          description: 'Ping from enclave workloads (demo only).'
        }
      }
      {
        name: 'Allow-Bastion-RDP'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: identitySubnetPrefix
          destinationPortRanges: [
            '3389'
            '22'
          ]
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-identity'
        properties: {
          addressPrefix: identitySubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output identitySubnetId string = vnet.properties.subnets[0].id
output bastionSubnetId string = vnet.properties.subnets[1].id
