// =============================================================================
//  Azure Virtual Enclaves demo: the ONE parameter file to edit.
//
//  Every stage's .bicepparam file (stage1-foundation.bicepparam, ...) extends
//  this file, so a value set here flows to every stage that declares it.
//  Deploy-AVEDemo.ps1 also reads this file (prefix, location, address spaces,
//  DC IP) for its own checks, resource naming and teardown.
//
//  Secrets and per-run values are never stored here; they come from
//  environment variables. Deploy-AVEDemo.ps1 supplies them automatically.
//  Set them yourself only when deploying a stage manually with az / Az.
// =============================================================================
using none

// ---------------------------------------------------------------- general ---
// Lowercase letters/digits, 2-8 chars. Drives every resource and RG name.
param prefix = 'ave'
param location = 'westus2'
param tags = {
  demo: 'azure-virtual-enclaves'
  audience: 'demo'
}

// --------------------------------------------- community (stage 1) ---
// Enclaves are carved out of this range. Must NOT overlap the corporate VNet.
param communityAddressSpaces = [
  '10.0.0.0/16'
]
param firewallSku = 'Standard'

// ------------------ corporate network outside the enclave (stage 1) ---
var corpIdentitySubnet = '10.100.1.0/24'
var dcIp = '10.100.1.4'

param corpVnetAddressPrefix = '10.100.0.0/16'
param corpIdentitySubnetPrefix = corpIdentitySubnet
param corpBastionSubnetPrefix = '10.100.254.0/26'
param dcPrivateIp = dcIp
param bastionSku = 'Basic' // Basic | Standard

// ------------------------------------- transit hub endpoint (stage 2) ---
// What enclaves may reach in the corporate network (AD ports + RDP/ICMP).
param corpDestination = corpIdentitySubnet

// ------------------------------------------------- enclave (stage 3) ---
param enclaveNetworkSize = 'small'
param enclaveCustomCidr = '' // e.g. '10.0.8.0/24'; empty = auto-allocate
param enclaveBastionEnabled = true

// --------------------------------------------- VMs (stages 1 and 4) ---
param vmSize = 'Standard_D2s_v3'
param adminUsername = 'aveadmin'

// Flip to true AFTER the DC has been promoted to AD DS, then re-run stage 4:
// the enclave VM's NIC will use the domain controller as its DNS server.
var useDcForEnclaveDns = false
param vmDnsServers = useDcForEnclaveDns ? [dcIp] : []

// Enclave guardrail knobs (see README "Cost and known caveats").
param encryptionAtHost = false
param keyVaultPublicNetworkAccess = 'Enabled' // Enabled | Disabled

// ---------------------------------- validation (Deploy-AVEDemo.ps1 only) ---
// AD domain for the stage 5 DNS SRV checks. Empty = port/ICMP checks only.
// No template declares this, so the stage files simply ignore it.
param adDomainName = ''

// ------------------------------- runtime values (environment variables) ---
param adminPassword = readEnvironmentVariable('AVE_ADMIN_PASSWORD', '')
param adminPrincipalId = readEnvironmentVariable('AVE_ADMIN_PRINCIPAL_ID', '')
param adminPrincipalType = readEnvironmentVariable('AVE_ADMIN_PRINCIPAL_TYPE', 'User')
param keyVaultCreateMode = readEnvironmentVariable('AVE_KV_CREATE_MODE', 'default')
