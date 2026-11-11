// STAGE 4 - Workload VM (workload resource group, created by the enclave RP)
//   * CMK dependencies (identity, Key Vault, key, Disk Encryption Set)
//   * Windows Server VM on the enclave subnet

import { names } from 'modules/naming.bicep'

param location string = resourceGroup().location

@minLength(2)
@maxLength(8)
param prefix string = 'ave'

@description('Resource ID of the enclave subnet. Empty = read it from the stage 3 enclave.')
param enclaveSubnetId string = ''

@description('Optional DNS servers for the enclave VM NIC (e.g. the DC IP after AD is promoted).')
param vmDnsServers array = []

param vmSize string = 'Standard_D2s_v5'
param adminUsername string

@secure()
param adminPassword string = ''

@description('Deploy the enclave VM. Set to false to skip VM deployment (CMK dependencies are still created).')
param deployEnclaveVm bool = true

param encryptionAtHost bool = false

@allowed([
  'Enabled'
  'Disabled'
])
param keyVaultPublicNetworkAccess string = 'Enabled'

@allowed([
  'default'
  'recover'
])
param keyVaultCreateMode string = 'default'

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
var keyVaultName = take('kv-${prefix}-${n.regionCode}-${uniqueString(resourceGroup().id)}', 24)

resource enclave 'Microsoft.Mission/virtualEnclaves@2026-04-01' existing = {
  name: n.enclave
  scope: resourceGroup(n.enclaveRg)
}

var subnetId = empty(enclaveSubnetId)
  ? enclave.properties.enclaveVirtualNetwork.subnetConfigurations[0].subnetResourceId!
  : enclaveSubnetId

module cmk 'modules/cmkDependencies.bicep' = {
  name: 'cmk-dependencies'
  params: {
    location: location
    keyVaultName: keyVaultName
    identityName: n.identity
    diskEncryptionSetName: n.diskEncryptionSet
    adminPrincipalId: adminPrincipalId
    adminPrincipalType: adminPrincipalType
    publicNetworkAccess: keyVaultPublicNetworkAccess
    keyVaultCreateMode: keyVaultCreateMode
    tags: tags
  }
}

module vm 'modules/enclaveVm.bicep' = if (deployEnclaveVm) {
  name: 'enclave-vm'
  params: {
    location: location
    vmName: n.enclaveVm
    computerName: n.enclaveComputer
    subnetId: subnetId
    diskEncryptionSetId: cmk.outputs.diskEncryptionSetId
    dnsServers: vmDnsServers
    encryptionAtHost: encryptionAtHost
    vmSize: vmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    tags: tags
  }
}

output enclaveVmName string = deployEnclaveVm ? vm!.outputs.vmName : ''
output enclaveVmPrivateIp string = deployEnclaveVm ? vm!.outputs.privateIp : ''
output keyVaultName string = keyVaultName
output diskEncryptionSetId string = cmk.outputs.diskEncryptionSetId
