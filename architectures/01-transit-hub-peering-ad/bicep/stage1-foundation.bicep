// STAGE 1 - Foundation (subscription scope)
//   * Resource groups for the community, the enclave and the "corporate" network
//   * Corporate VNet (outside the enclave) + Bastion + Windows Server VM that
//     will be promoted to an Active Directory domain controller by hand
//   * The Azure Virtual Enclaves community (firewall + hub for all enclaves)

targetScope = 'subscription'

import { names } from 'modules/naming.bicep'

param location string = 'eastus'

@minLength(2)
@maxLength(8)
param prefix string = 'ave'

@description('Address space(s) owned by the community. Enclaves are carved out of this range.')
param communityAddressSpaces array = [
  '10.0.0.0/16'
]

param corpVnetAddressPrefix string = '10.100.0.0/16'
param corpIdentitySubnetPrefix string = '10.100.1.0/24'
param corpBastionSubnetPrefix string = '10.100.254.0/26'

@description('Static private IP of the domain controller VM in the corporate VNet.')
param dcPrivateIp string = '10.100.1.4'

param firewallSku string = 'Standard'

@allowed([
  'Basic'
  'Standard'
])
param bastionSku string = 'Basic'

param vmSize string = 'Standard_D2s_v5'
param adminUsername string

@secure()
param adminPassword string = ''

@description('Deploy the domain controller VM. Set to false to skip VM deployment (e.g. no vCPU quota).')
param deployDcVm bool = true

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

resource communityRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: n.communityRg
  location: location
  tags: tags
}

resource enclaveRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: n.enclaveRg
  location: location
  tags: tags
}

resource corpRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: n.corpRg
  location: location
  tags: tags
}

module corpNetwork 'modules/corpNetwork.bicep' = {
  name: 'corp-network'
  scope: corpRg
  params: {
    location: location
    vnetName: n.corpVnet
    addressPrefix: corpVnetAddressPrefix
    identitySubnetPrefix: corpIdentitySubnetPrefix
    bastionSubnetPrefix: corpBastionSubnetPrefix
    communityAddressSpaces: communityAddressSpaces
    tags: tags
  }
}

module bastion 'modules/bastion.bicep' = {
  name: 'corp-bastion'
  scope: corpRg
  params: {
    location: location
    bastionName: n.corpBastion
    bastionSubnetId: corpNetwork.outputs.bastionSubnetId
    sku: bastionSku
    tags: tags
  }
}

module dcVm 'modules/adVm.bicep' = if (deployDcVm) {
  name: 'corp-dc-vm'
  scope: corpRg
  params: {
    location: location
    vmName: n.dcVm
    computerName: n.dcComputer
    subnetId: corpNetwork.outputs.identitySubnetId
    privateIpAddress: dcPrivateIp
    vmSize: vmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    tags: tags
  }
}

module community 'modules/community.bicep' = {
  name: 'community'
  scope: communityRg
  params: {
    location: location
    communityName: n.community
    addressSpaces: communityAddressSpaces
    firewallSku: firewallSku
    adminPrincipalId: adminPrincipalId
    adminPrincipalType: adminPrincipalType
    tags: tags
  }
}

output communityId string = community.outputs.communityId
output communityName string = community.outputs.communityName
output communityResourceGroup string = communityRg.name
output enclaveResourceGroup string = enclaveRg.name
output corpResourceGroup string = corpRg.name
output corpVnetId string = corpNetwork.outputs.vnetId
output dcVmName string = deployDcVm ? dcVm!.outputs.vmName : ''
output dcPrivateIp string = deployDcVm ? dcVm!.outputs.privateIp : dcPrivateIp
