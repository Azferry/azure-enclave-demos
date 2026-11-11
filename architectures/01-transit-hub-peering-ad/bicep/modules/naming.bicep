// Single naming convention shared by every stage so names line up across
// separate deployments.

// Region short codes. Keep in sync with $RegionCodes in Deploy-AVEDemo.ps1 and
// Deploy-AVEDemo.AzCli.ps1. Unknown regions fall back to the full region name.
func regionMap() object => {
  eastus: 'eus'
  eastus2: 'eus2'
  westus: 'wus'
  westus2: 'wus2'
  westus3: 'wus3'
  centralus: 'cus'
  northcentralus: 'ncus'
  southcentralus: 'scus'
  westcentralus: 'wcus'
  usgovvirginia: 'ugv'
  usgovarizona: 'uga'
  usgovtexas: 'ugt'
  canadacentral: 'cac'
  canadaeast: 'cae'
  northeurope: 'neu'
  westeurope: 'weu'
  uksouth: 'uks'
  ukwest: 'ukw'
  francecentral: 'frc'
  germanywestcentral: 'gwc'
  swedencentral: 'sdc'
  switzerlandnorth: 'szn'
  norwayeast: 'noe'
  southeastasia: 'sea'
  eastasia: 'ea'
  japaneast: 'jpe'
  koreacentral: 'krc'
  australiaeast: 'aue'
  centralindia: 'inc'
  brazilsouth: 'brs'
  southafricanorth: 'san'
  uaenorth: 'uan'
}

@export()
func regionCode(location string) string => regionMap()[?toLower(location)] ?? toLower(location)

@export()
func names(prefix string, location string) object => {
  regionCode: regionCode(location)
  communityRg: 'rg-${prefix}-${regionCode(location)}-community'
  enclaveRg: 'rg-${prefix}-${regionCode(location)}-enclave'
  workloadRg: 'rg-${prefix}-${regionCode(location)}-workload'
  corpRg: 'rg-${prefix}-${regionCode(location)}-corp'
  community: '${prefix}-${regionCode(location)}-community'
  transitHub: '${prefix}-${regionCode(location)}-th-corp'
  communityEndpoint: '${prefix}-${regionCode(location)}-ce-corp-ad'
  enclave: '${prefix}-${regionCode(location)}-enclave'
  workload: '${prefix}-${regionCode(location)}-workload'
  enclaveConnection: '${prefix}-${regionCode(location)}-ec-corp-ad'
  corpVnet: 'vnet-${prefix}-${regionCode(location)}-corp'
  corpBastion: 'bas-${prefix}-${regionCode(location)}-corp'
  dcVm: 'vm-${prefix}-${regionCode(location)}-dc01'
  dcComputer: 'DC01'
  enclaveVm: 'vm-${prefix}-${regionCode(location)}-enc01'
  enclaveComputer: 'ENCVM01'
  identity: 'id-${prefix}-${regionCode(location)}-cmk'
  diskEncryptionSet: 'des-${prefix}-${regionCode(location)}-cmk'
}
