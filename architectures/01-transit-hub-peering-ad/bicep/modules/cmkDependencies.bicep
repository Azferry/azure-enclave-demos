// Customer-managed key (CMK) dependencies required by enclave guardrails for
// VM disks: user-assigned identity, Key Vault + key, and a Disk Encryption Set.

param location string

@maxLength(24)
param keyVaultName string

param identityName string
param keyName string = 'cmk-disk-encryption'
param diskEncryptionSetName string

@description('Object ID of the deploying principal (granted Key Vault Administrator for demo inspection). Empty = skip.')
param adminPrincipalId string = ''

@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param adminPrincipalType string = 'User'

@description('Key Vault public network access. The firewall denies all traffic except trusted Azure services either way.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Use "recover" when a soft-deleted vault with the same name exists (purge protection keeps it for 7+ days after teardown).')
@allowed([
  'default'
  'recover'
])
param keyVaultCreateMode string = 'default'

param tags object = {}

var kvCryptoServiceEncryptionUserRoleId = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'
var kvAdministratorRoleId = '00482a5a-887f-4fb3-b363-3b7fe8e74483'

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    createMode: keyVaultCreateMode
    sku: {
      family: 'A'
      name: 'premium'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource key 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: keyName
  properties: {
    kty: 'RSA-HSM'
    keySize: 3072
    keyOps: [
      'wrapKey'
      'unwrapKey'
    ]
  }
}

resource uamiCryptoRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, uami.id, kvCryptoServiceEncryptionUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvCryptoServiceEncryptionUserRoleId)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource adminKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(adminPrincipalId)) {
  name: guid(keyVault.id, adminPrincipalId, kvAdministratorRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvAdministratorRoleId)
    principalId: adminPrincipalId
    principalType: adminPrincipalType
  }
}

resource des 'Microsoft.Compute/diskEncryptionSets@2024-03-02' = {
  name: diskEncryptionSetName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    encryptionType: 'EncryptionAtRestWithCustomerKey'
    rotationToLatestKeyVersionEnabled: true
    activeKey: {
      keyUrl: key.properties.keyUriWithVersion
      sourceVault: {
        id: keyVault.id
      }
    }
  }
  dependsOn: [
    uamiCryptoRole
  ]
}

output diskEncryptionSetId string = des.id
output keyVaultId string = keyVault.id
output identityId string = uami.id
