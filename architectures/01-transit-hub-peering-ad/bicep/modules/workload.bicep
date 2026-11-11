// Workload: links one or more resource groups to the enclave so everything
// deployed into them inherits the enclave's policy and network boundary.
// Azure Enclave creates resource groups that don't exist yet; existing ones must be empty.

param location string
param enclaveName string
param workloadName string

@description('Names of the resource groups (same subscription) to link to this workload.')
param resourceGroupNames array

param tags object = {}

resource enclave 'Microsoft.Mission/virtualEnclaves@2026-04-01' existing = {
  name: enclaveName
}

resource workload 'Microsoft.Mission/virtualEnclaves/workloads@2026-04-01' = {
  parent: enclave
  name: workloadName
  location: location
  tags: tags
  properties: {
    resourceGroupCollection: [for rg in resourceGroupNames: subscriptionResourceId('Microsoft.Resources/resourceGroups', rg)]
  }
}

output workloadId string = workload.id
output workloadName string = workload.name
