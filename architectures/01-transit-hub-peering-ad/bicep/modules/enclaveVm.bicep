// Windows Server VM deployed into the enclave workload. Its NIC is placed on
// the enclave-managed subnet, it has no public IP, and its OS disk is
// encrypted with a customer-managed key to satisfy enclave guardrails.

param location string
param vmName string

@maxLength(15)
param computerName string

@description('Resource ID of the enclave subnet (output of the enclave).')
param subnetId string

@description('Disk Encryption Set used for CMK encryption of the OS disk.')
param diskEncryptionSetId string

@description('Optional DNS servers for the NIC (for example the AD DC IP once promoted). Empty = inherit from VNet.')
param dnsServers array = []

@description('Enable encryption at host (requires the Microsoft.Compute/EncryptionAtHost feature on the subscription).')
param encryptionAtHost bool = false

param vmSize string = 'Standard_D2s_v5'
param adminUsername string

@secure()
param adminPassword string

param tags object = {}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${vmName}'
  location: location
  tags: tags
  properties: {
    dnsSettings: {
      dnsServers: dnsServers
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      encryptionAtHost: encryptionAtHost
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${vmName}'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
          diskEncryptionSet: {
            id: diskEncryptionSetId
          }
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

output vmId string = vm.id
output vmName string = vm.name
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
