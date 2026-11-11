#Requires -Version 7.0
<#
.SYNOPSIS
    Deploys (or tears down) the Azure Virtual Enclaves demo:
    community -> enclave -> workload VM, plus a transit hub peered to a
    "corporate" VNet that hosts a Windows Server VM to be promoted to AD DS.

.DESCRIPTION
    All demo settings live in Bicep parameter files:

      bicep\demo.bicepparam              <- the one file you edit
      bicep\stage<N>-*.bicepparam        <- one per stage, 'extends' demo.bicepparam

    The script compiles each stage's .bicepparam with the Bicep CLI and deploys
    the matching template. It only adds the run-time values that do not belong
    in a file: the VM admin password, the principal that gets enclave access,
    the Key Vault create mode and the enclave subnet ID.

    Stage 1  Foundation    : resource groups, corp VNet + Bastion + DC VM, community
    Stage 2  Connectivity  : transit hub (VNet peering) + community endpoint for AD
    Stage 3  Enclave       : enclave, workload, enclave connection
    Stage 4  Workload VM   : CMK dependencies + Windows VM in the enclave
    Stage 5  Validation    : run Test-AdConnectivity.ps1 inside the enclave VM

    Each stage derives the IDs it needs from the shared naming convention, so a
    run can be resumed at any stage with -StartAtStage.

.PARAMETER AdminPassword
    Local admin password for both VMs. Falls back to $env:AVE_ADMIN_PASSWORD,
    then prompts.

.PARAMETER DomainName
    AD domain for the stage 5 DNS checks. Overrides adDomainName in demo.bicepparam.

.EXAMPLE
    .\Deploy-AVEDemo.ps1 -SubscriptionId <guid>

.EXAMPLE
    .\Deploy-AVEDemo.ps1 -SubscriptionId <guid> -StartAtStage 3

.EXAMPLE
    .\Deploy-AVEDemo.ps1 -SubscriptionId <guid> -StartAtStage 5 -DomainName corp.contoso.local

.EXAMPLE
    .\Deploy-AVEDemo.ps1 -SubscriptionId <guid> -Teardown
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId,

    [securestring]$AdminPassword,

    [string]$DomainName,

    [ValidateRange(1, 5)]
    [int]$StartAtStage = 1,

    [ValidateRange(1, 5)]
    [int]$StopAfterStage = 5,

    [Parameter(HelpMessage = 'Object ID to grant Contributor in the community/enclave/workload. Defaults to the signed-in principal.')]
    [string]$AdminPrincipalId,

    [switch]$SkipRoleAssignments,

    [Parameter(HelpMessage = 'Skip deploying the DC VM (stage 1) and the enclave VM (stage 4), and skip stage 5 validation.')]
    [switch]$SkipVmDeployment,

    [switch]$Teardown,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MissionApiVersion = '2026-04-01'
$BicepRoot = Join-Path $PSScriptRoot 'bicep'
$SettingsFile = Join-Path $BicepRoot 'demo.bicepparam'
$TestScript = Join-Path $PSScriptRoot 'scripts\Test-AdConnectivity.ps1'

$StageFiles = @{
    1 = 'stage1-foundation'
    2 = 'stage2-connectivity'
    3 = 'stage3-enclave'
    4 = 'stage4-workload-vm'
}

# Region short codes. Keep in sync with regionMap() in bicep\modules\naming.bicep.
# Unknown regions fall back to the full region name.
$RegionCodes = @{
    eastus = 'eus'; eastus2 = 'eus2'; westus = 'wus'; westus2 = 'wus2'; westus3 = 'wus3'
    centralus = 'cus'; northcentralus = 'ncus'; southcentralus = 'scus'; westcentralus = 'wcus'
    usgovvirginia = 'ugv'; usgovarizona = 'uga'; usgovtexas = 'ugt'
    canadacentral = 'cac'; canadaeast = 'cae'
    northeurope = 'neu'; westeurope = 'weu'; uksouth = 'uks'; ukwest = 'ukw'
    francecentral = 'frc'; germanywestcentral = 'gwc'; swedencentral = 'sdc'
    switzerlandnorth = 'szn'; norwayeast = 'noe'
    southeastasia = 'sea'; eastasia = 'ea'; japaneast = 'jpe'; koreacentral = 'krc'
    australiaeast = 'aue'; centralindia = 'inc'
    brazilsouth = 'brs'; southafricanorth = 'san'; uaenorth = 'uan'
}

#region Helpers ---------------------------------------------------------------

function Write-Banner([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
}

function Write-Info([string]$Text) { Write-Host "  - $Text" -ForegroundColor Gray }
function Write-Ok([string]$Text) { Write-Host "  + $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "  ! $Text" -ForegroundColor Yellow }

function ConvertTo-PlainText([securestring]$Secure) {
    [System.Net.NetworkCredential]::new('', $Secure).Password
}

function Get-CidrRange([string]$Cidr) {
    $ip, $bits = $Cidr.Split('/')
    if (-not $bits) { $bits = 32 }
    $bytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
    [array]::Reverse($bytes)
    $start = [uint64][BitConverter]::ToUInt32($bytes, 0)
    $size = [uint64][math]::Pow(2, 32 - [int]$bits)
    $start = $start - ($start % $size)
    [pscustomobject]@{ Start = $start; End = $start + $size - 1 }
}

function Test-CidrOverlap([string]$A, [string]$B) {
    $ra = Get-CidrRange $A
    $rb = Get-CidrRange $B
    ($ra.Start -le $rb.End) -and ($rb.Start -le $ra.End)
}

function Read-BicepParamFile([string]$Path) {
    # Compiles a .bicepparam file and returns its values as a hashtable.
    if (-not (Test-Path $Path)) { throw "Parameter file not found: $Path" }
    $ErrorActionPreference = 'Continue'
    $output = & bicep build-params $Path --stdout 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    if ($exitCode -ne 0) {
        throw "bicep build-params failed for '$Path':`n$(($stderr + $stdout) -join "`n")"
    }
    $stderr | ForEach-Object { Write-Warn "bicep: $_" }

    $compiled = ($stdout -join "`n") | ConvertFrom-Json
    $parameters = ($compiled.parametersJson | ConvertFrom-Json -AsHashtable).parameters
    $values = [ordered]@{}
    foreach ($key in $parameters.Keys) { $values[$key] = $parameters[$key].value }
    $values
}

function Get-Setting([string]$Name) {
    if (-not $Settings.Contains($Name)) { throw "'$Name' is missing from $SettingsFile." }
    $Settings[$Name]
}

function Get-MissionResource([string]$ResourceId) {
    try { Get-AzResource -ResourceId $ResourceId -ApiVersion $MissionApiVersion -ExpandProperties -ErrorAction Stop }
    catch { $null }
}

function Get-PropertyValue($Object, [string[]]$Path) {
    $current = $Object
    foreach ($segment in $Path) {
        if ($null -eq $current) { return $null }
        $prop = $current.PSObject.Properties[$segment]
        if (-not $prop) { return $null }
        $current = $prop.Value
    }
    $current
}

function Show-DeploymentFailure([string]$Name, [string]$ResourceGroupName) {
    try {
        $ops = if ($ResourceGroupName) {
            Get-AzResourceGroupDeploymentOperation -DeploymentName $Name -ResourceGroupName $ResourceGroupName
        }
        else {
            Get-AzDeploymentOperation -DeploymentName $Name
        }
        $ops | Where-Object ProvisioningState -eq 'Failed' | ForEach-Object {
            Write-Warn ("{0}: {1}" -f (($_.TargetResource -split '/')[-1]), $_.StatusMessage)
        }
    }
    catch { }
}

function Invoke-StageDeployment {
    param(
        [Parameter(Mandatory)][int]$Stage,
        [string]$ResourceGroupName,
        [hashtable]$Overrides = @{}
    )

    $name = $DeploymentNames[$Stage]
    $templateFile = Join-Path $BicepRoot "$($StageFiles[$Stage]).bicep"
    $paramFile = Join-Path $BicepRoot "$($StageFiles[$Stage]).bicepparam"

    Write-Info "Parameters: $(Split-Path $paramFile -Leaf) (extends demo.bicepparam)"
    $parameters = Read-BicepParamFile $paramFile
    foreach ($key in $Overrides.Keys) { $parameters[$key] = $Overrides[$key] }

    $common = @{
        Name                    = $name
        TemplateFile            = $templateFile
        TemplateParameterObject = [hashtable]$parameters
        AsJob                   = $true
    }

    Write-Info "Deployment '$name' started $(Get-Date -Format 'HH:mm:ss')"
    $job = if ($ResourceGroupName) {
        New-AzResourceGroupDeployment @common -ResourceGroupName $ResourceGroupName -Mode Incremental
    }
    else {
        New-AzSubscriptionDeployment @common -Location $Location
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $lastStatus = ''
    while ($job.State -in 'NotStarted', 'Running') {
        Start-Sleep -Seconds 30
        try {
            $ops = if ($ResourceGroupName) {
                Get-AzResourceGroupDeploymentOperation -DeploymentName $name -ResourceGroupName $ResourceGroupName -ErrorAction Stop
            }
            else {
                Get-AzDeploymentOperation -DeploymentName $name -ErrorAction Stop
            }
            $status = ($ops | Where-Object TargetResource | ForEach-Object {
                    '{0}={1}' -f (($_.TargetResource -split '/')[-1]), $_.ProvisioningState
                }) -join ', '
        }
        catch { $status = 'validating...' }

        if ($status -ne $lastStatus -or ($timer.Elapsed.TotalSeconds % 300) -lt 30) {
            Write-Host ("    [{0:hh\:mm\:ss}] {1}" -f $timer.Elapsed, $status) -ForegroundColor DarkGray
            $lastStatus = $status
        }
    }

    try {
        $result = Receive-Job -Job $job -Wait -AutoRemoveJob -ErrorAction Stop | Select-Object -Last 1
    }
    catch {
        Show-DeploymentFailure -Name $name -ResourceGroupName $ResourceGroupName
        throw "Stage $Stage deployment '$name' failed: $($_.Exception.Message)"
    }

    if (-not $result -or $result.ProvisioningState -ne 'Succeeded') {
        Show-DeploymentFailure -Name $name -ResourceGroupName $ResourceGroupName
        throw "Stage $Stage deployment '$name' finished with state '$($result.ProvisioningState)'."
    }

    Write-Ok ("Stage {0} succeeded in {1:hh\:mm\:ss}" -f $Stage, $timer.Elapsed)
    $result
}

function Get-DeploymentOutput($Deployment, [string]$Key) {
    if (-not $Deployment.Outputs -or -not $Deployment.Outputs.ContainsKey($Key)) {
        throw "Deployment '$($Deployment.DeploymentName)' has no output '$Key'."
    }
    $Deployment.Outputs[$Key].Value
}

function Assert-StageSucceeded([int]$Stage) {
    $name = $DeploymentNames[$Stage]
    $rg = $StageResourceGroups[$Stage]
    try {
        $dep = if ($rg) {
            Get-AzResourceGroupDeployment -ResourceGroupName $rg -Name $name -ErrorAction Stop
        }
        else {
            Get-AzSubscriptionDeployment -Name $name -ErrorAction Stop
        }
    }
    catch {
        throw "Cannot resume: stage $Stage deployment '$name' was not found. Re-run with -StartAtStage $Stage or lower."
    }
    if ($dep.ProvisioningState -ne 'Succeeded') {
        throw "Cannot resume: stage $Stage deployment '$name' is '$($dep.ProvisioningState)'. Re-run with -StartAtStage $Stage."
    }
    Write-Ok "Stage $Stage already deployed ($name)"
}

function Wait-ForCondition {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [Parameter(Mandatory)][string]$Description,
        [int]$TimeoutMinutes = 30,
        [int]$IntervalSeconds = 30
    )
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        $value = & $Condition
        if ($value) { return $value }
        Write-Host "    waiting for $Description ..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $IntervalSeconds
    }
    throw "Timed out after $TimeoutMinutes minutes waiting for $Description."
}

function Get-AdminPassword {
    if (-not $script:AdminPassword -and $env:AVE_ADMIN_PASSWORD) {
        $script:AdminPassword = ConvertTo-SecureString $env:AVE_ADMIN_PASSWORD -AsPlainText -Force
    }
    if (-not $script:AdminPassword) {
        $script:AdminPassword = Read-Host -AsSecureString -Prompt "Local admin password for the demo VMs (user '$AdminUsername')"
    }
    $plain = ConvertTo-PlainText $script:AdminPassword
    if ($plain.Length -lt 12) { throw 'Admin password must be at least 12 characters and meet Azure VM complexity rules.' }
    $plain
}

#endregion

#region Settings + pre-flight ---------------------------------------------------

function Initialize-Settings {
    Write-Banner 'Reading parameters'

    if (-not (Get-Command bicep -ErrorAction SilentlyContinue)) {
        throw 'Bicep CLI not found on PATH. Install it: winget install -e --id Microsoft.Bicep'
    }
    Write-Ok "Bicep CLI: $((& bicep --version) -join ' ')"

    $script:Settings = Read-BicepParamFile $SettingsFile
    $script:Prefix = Get-Setting 'prefix'
    if ($Prefix -notmatch '^[a-z][a-z0-9]{1,7}$') {
        throw "prefix '$Prefix' in demo.bicepparam must be 2-8 lowercase letters/digits, starting with a letter."
    }
    $script:Location = Get-Setting 'location'
    $script:AdminUsername = Get-Setting 'adminUsername'
    $script:DcPrivateIp = Get-Setting 'dcPrivateIp'
    $script:CorpDestination = Get-Setting 'corpDestination'
    if (-not $DomainName -and $Settings.Contains('adDomainName')) { $script:DomainName = $Settings['adDomainName'] }
    Write-Ok "Settings: $(Resolve-Path $SettingsFile -Relative) -> prefix '$Prefix', location '$Location'"

    $locKey = $Location.ToLowerInvariant()
    $script:RegionCode = if ($RegionCodes.ContainsKey($locKey)) { $RegionCodes[$locKey] } else { $locKey }
    $pr = "$Prefix-$RegionCode"
    Write-Info "Region code: '$RegionCode' (names look like rg-$pr-community)"

    $script:Names = @{
        CommunityRg       = "rg-$pr-community"
        EnclaveRg         = "rg-$pr-enclave"
        WorkloadRg        = "rg-$pr-workload"
        CorpRg            = "rg-$pr-corp"
        Community         = "$pr-community"
        TransitHub        = "$pr-th-corp"
        CommunityEndpoint = "$pr-ce-corp-ad"
        Enclave           = "$pr-enclave"
        Workload          = "$pr-workload"
        EnclaveConnection = "$pr-ec-corp-ad"
        CorpVnet          = "vnet-$pr-corp"
        DcVm              = "vm-$pr-dc01"
        EnclaveVm         = "vm-$pr-enc01"
        CorpBastion       = "bas-$pr-corp"
    }

    $script:DeploymentNames = @{}
    foreach ($stage in $StageFiles.Keys) { $script:DeploymentNames[$stage] = "$Prefix-$Location-$($StageFiles[$stage])" }
    $script:StageResourceGroups = @{ 1 = $null; 2 = $Names.CommunityRg; 3 = $Names.EnclaveRg; 4 = $Names.WorkloadRg }

    if ($Teardown) { return }

    $corpPrefix = Get-Setting 'corpVnetAddressPrefix'
    foreach ($cidr in @(Get-Setting 'communityAddressSpaces')) {
        if (Test-CidrOverlap $cidr $corpPrefix) {
            throw "Community address space $cidr overlaps the corporate VNet $corpPrefix. Peered ranges must not overlap."
        }
    }
    if (-not (Test-CidrOverlap "$DcPrivateIp/32" (Get-Setting 'corpIdentitySubnetPrefix'))) {
        throw "dcPrivateIp $DcPrivateIp is not inside corpIdentitySubnetPrefix $(Get-Setting 'corpIdentitySubnetPrefix')."
    }
    Write-Ok 'Address spaces are consistent and do not overlap'
}

function Initialize-Environment {
    Write-Banner 'Pre-flight checks'

    $requiredModules = 'Az.Accounts', 'Az.Resources', 'Az.Compute', 'Az.KeyVault'
    $missing = $requiredModules | Where-Object { -not (Get-Module -ListAvailable -Name $_) }
    if ($missing) {
        throw ("Missing PowerShell modules: {0}. Install with:  Install-Module Az -Scope CurrentUser -Repository PSGallery" -f ($missing -join ', '))
    }
    Import-Module $requiredModules -ErrorAction Stop
    Write-Ok 'Az PowerShell modules present'

    $ctx = Get-AzContext
    if (-not $ctx) {
        $connect = @{}
        if ($SubscriptionId) { $connect.Subscription = $SubscriptionId }
        Connect-AzAccount @connect | Out-Null
        $ctx = Get-AzContext
    }
    if ($SubscriptionId -and $ctx.Subscription.Id -ne $SubscriptionId) {
        $ctx = Set-AzContext -Subscription $SubscriptionId
    }
    Write-Ok ("Subscription: {0} ({1})" -f $ctx.Subscription.Name, $ctx.Subscription.Id)
    Write-Ok ("Signed in as: {0} [{1}]" -f $ctx.Account.Id, $ctx.Account.Type)
    $script:SubscriptionId = $ctx.Subscription.Id

    if ($Teardown) { return }

    foreach ($ns in 'Microsoft.Mission', 'Microsoft.Network', 'Microsoft.Compute', 'Microsoft.KeyVault', 'Microsoft.ManagedIdentity') {
        $state = (Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction SilentlyContinue | Select-Object -First 1).RegistrationState
        if ($state -ne 'Registered') {
            Write-Info "Registering resource provider $ns ..."
            Register-AzResourceProvider -ProviderNamespace $ns | Out-Null
            Wait-ForCondition -Description "$ns registration" -TimeoutMinutes 15 -IntervalSeconds 20 -Condition {
                (Get-AzResourceProvider -ProviderNamespace $ns | Select-Object -First 1).RegistrationState -eq 'Registered'
            } | Out-Null
        }
    }
    Write-Ok 'Resource providers registered'

    $script:PrincipalId = ''
    $script:PrincipalType = 'User'
    if (-not $SkipRoleAssignments) {
        if ($AdminPrincipalId) {
            $script:PrincipalId = $AdminPrincipalId
        }
        else {
            try {
                if ($ctx.Account.Type -eq 'User') {
                    $script:PrincipalId = (Get-AzADUser -SignedIn -ErrorAction Stop).Id
                }
                else {
                    $script:PrincipalId = (Get-AzADServicePrincipal -ApplicationId $ctx.Account.Id -ErrorAction Stop).Id
                    $script:PrincipalType = 'ServicePrincipal'
                }
            }
            catch {
                Write-Warn "Could not resolve the signed-in principal's object ID ($($_.Exception.Message)). Skipping enclave role assignments."
            }
        }
        if ($script:PrincipalId) { Write-Ok "Enclave role assignments -> $($script:PrincipalType) $($script:PrincipalId)" }
    }
}

function Get-PrincipalOverrides {
    @{ adminPrincipalId = $script:PrincipalId; adminPrincipalType = $script:PrincipalType }
}

#endregion

#region Stages ------------------------------------------------------------------

function Invoke-Stage1 {
    Write-Banner 'Stage 1/5  Foundation: resource groups, corporate network + DC VM, community'
    Write-Info 'The community deploys Azure Firewall + a virtual hub: expect 30-60 minutes.'
    $overrides = Get-PrincipalOverrides
    if ($SkipVmDeployment) { Write-Warn 'Skipping DC VM deployment (-SkipVmDeployment).' }
    else { $overrides.adminPassword = Get-AdminPassword }
    $overrides.deployDcVm = -not $SkipVmDeployment
    Invoke-StageDeployment -Stage 1 -Overrides $overrides | Out-Null
}

function Invoke-Stage2 {
    Write-Banner 'Stage 2/5  Connectivity: transit hub (peering to corp VNet) + community endpoint'
    $dep = Invoke-StageDeployment -Stage 2 -ResourceGroupName $Names.CommunityRg

    $thId = Get-DeploymentOutput $dep 'transitHubId'
    $th = Get-MissionResource $thId
    $state = Get-PropertyValue $th 'Properties', 'state'
    Write-Info "Transit hub state: $state"
    if ($state -and $state -ne 'Approved') {
        Write-Info 'Approving transit hub ...'
        $resp = Invoke-AzRestMethod -Method PATCH -Path "$($thId)?api-version=$MissionApiVersion" -Payload '{"properties":{"state":"Approved"}}'
        if ($resp.StatusCode -ge 300) { Write-Warn "Transit hub approval returned HTTP $($resp.StatusCode): $($resp.Content)" }
        Wait-ForCondition -Description 'transit hub approval' -TimeoutMinutes 30 -Condition {
            $r = Get-MissionResource $thId
            (Get-PropertyValue $r 'Properties', 'state') -eq 'Approved' -and
            (Get-PropertyValue $r 'Properties', 'provisioningState') -eq 'Succeeded'
        } | Out-Null
    }
    Write-Ok 'Transit hub approved'
}

function Invoke-Stage3 {
    Write-Banner 'Stage 3/5  Enclave: enclave + workload + enclave connection'
    Write-Info 'Enclave provisioning typically takes 30-45 minutes.'
    $dep = Invoke-StageDeployment -Stage 3 -ResourceGroupName $Names.EnclaveRg -Overrides (Get-PrincipalOverrides)
    Write-Ok ("Enclave address space: {0}" -f (Get-DeploymentOutput $dep 'enclaveAddressSpace'))
}

function Resolve-EnclaveSubnetId {
    $enclaveId = "/subscriptions/$($script:SubscriptionId)/resourceGroups/$($Names.EnclaveRg)/providers/Microsoft.Mission/virtualEnclaves/$($Names.Enclave)"
    Wait-ForCondition -Description 'enclave subnet' -TimeoutMinutes 15 -Condition {
        $enclave = Get-MissionResource $enclaveId
        $subnets = Get-PropertyValue $enclave 'Properties', 'enclaveVirtualNetwork', 'subnetConfigurations'
        if ($subnets) { @($subnets)[0].subnetResourceId }
    }
}

function Invoke-Stage4 {
    Write-Banner 'Stage 4/5  Workload VM: CMK disk encryption + Windows VM inside the enclave'

    Wait-ForCondition -Description "workload resource group '$($Names.WorkloadRg)'" -TimeoutMinutes 30 -Condition {
        Get-AzResourceGroup -Name $Names.WorkloadRg -ErrorAction SilentlyContinue
    } | Out-Null
    Write-Ok "Workload resource group '$($Names.WorkloadRg)' exists"

    $overrides = Get-PrincipalOverrides
    if ($SkipVmDeployment) { Write-Warn 'Skipping enclave VM deployment (-SkipVmDeployment).' }
    else { $overrides.adminPassword = Get-AdminPassword }
    $overrides.deployEnclaveVm = -not $SkipVmDeployment
    $overrides.enclaveSubnetId = Resolve-EnclaveSubnetId
    $overrides.keyVaultCreateMode = 'default'

    # Purge protection keeps a deleted vault for 7 days; recover it instead of failing on name conflicts.
    $rgPattern = "/resourceGroups/$([regex]::Escape($Names.WorkloadRg))/providers/Microsoft.KeyVault/vaults/"
    $deleted = Get-AzKeyVault -InRemovedState -ErrorAction SilentlyContinue | Where-Object {
        $_.PSObject.Properties['ResourceId'] -and $_.ResourceId -match $rgPattern
    }
    if ($deleted) {
        Write-Warn "Found soft-deleted Key Vault '$(@($deleted)[0].VaultName)'; it will be recovered."
        $overrides.keyVaultCreateMode = 'recover'
    }

    $dep = Invoke-StageDeployment -Stage 4 -ResourceGroupName $Names.WorkloadRg -Overrides $overrides
    Write-Ok ("Enclave VM {0} -> {1}" -f (Get-DeploymentOutput $dep 'enclaveVmName'), (Get-DeploymentOutput $dep 'enclaveVmPrivateIp'))
}

function Invoke-Stage5 {
    if ($SkipVmDeployment) { Write-Warn 'Skipping stage 5 validation: no VMs were deployed (-SkipVmDeployment).'; return }
    Write-Banner "Stage 5/5  Validation: enclave VM -> DC ($DcPrivateIp) through the community firewall"
    $runParams = @{ DcIp = $DcPrivateIp }
    if ($DomainName) { $runParams.DomainName = $DomainName }
    try {
        $run = Invoke-AzVMRunCommand -ResourceGroupName $Names.WorkloadRg -VMName $Names.EnclaveVm `
            -CommandId 'RunPowerShellScript' -ScriptPath $TestScript -Parameter $runParams
        $run.Value | Where-Object { $_.Message } | ForEach-Object { Write-Host $_.Message }
    }
    catch {
        Write-Warn "Run command failed: $($_.Exception.Message)"
        Write-Warn 'Connect to the enclave VM with the enclave Bastion and run scripts\Test-AdConnectivity.ps1 manually.'
    }
}

#endregion

#region Teardown ----------------------------------------------------------------

function Invoke-Teardown {
    Write-Banner "Teardown: removing all '$Prefix' demo resources"
    if (-not $Force) {
        $answer = Read-Host "This deletes the community, enclave, workload and corp resource groups for prefix '$Prefix'. Type the prefix to confirm"
        if ($answer -ne $Prefix) { Write-Warn 'Teardown cancelled.'; return }
    }

    $sub = "/subscriptions/$($script:SubscriptionId)/resourceGroups"
    $mission = 'providers/Microsoft.Mission'
    $steps = @(
        @{ Kind = 'rg'; Name = $Names.WorkloadRg }
        @{ Kind = 'res'; Name = 'enclave connection'; Id = "$sub/$($Names.EnclaveRg)/$mission/enclaveConnections/$($Names.EnclaveConnection)" }
        @{ Kind = 'res'; Name = 'workload'; Id = "$sub/$($Names.EnclaveRg)/$mission/virtualEnclaves/$($Names.Enclave)/workloads/$($Names.Workload)" }
        @{ Kind = 'res'; Name = 'enclave'; Id = "$sub/$($Names.EnclaveRg)/$mission/virtualEnclaves/$($Names.Enclave)" }
        @{ Kind = 'res'; Name = 'community endpoint'; Id = "$sub/$($Names.CommunityRg)/$mission/communities/$($Names.Community)/communityEndpoints/$($Names.CommunityEndpoint)" }
        @{ Kind = 'res'; Name = 'transit hub'; Id = "$sub/$($Names.CommunityRg)/$mission/communities/$($Names.Community)/transitHubs/$($Names.TransitHub)" }
        @{ Kind = 'res'; Name = 'community'; Id = "$sub/$($Names.CommunityRg)/$mission/communities/$($Names.Community)" }
        @{ Kind = 'rg'; Name = $Names.EnclaveRg }
        @{ Kind = 'rg'; Name = $Names.CommunityRg }
        @{ Kind = 'rg'; Name = $Names.CorpRg }
    )

    foreach ($step in $steps) {
        try {
            if ($step.Kind -eq 'rg') {
                if (Get-AzResourceGroup -Name $step.Name -ErrorAction SilentlyContinue) {
                    Write-Info "Deleting resource group $($step.Name) ..."
                    Remove-AzResourceGroup -Name $step.Name -Force | Out-Null
                    Write-Ok "Deleted $($step.Name)"
                }
            }
            elseif (Get-MissionResource $step.Id) {
                Write-Info "Deleting $($step.Name) ..."
                Remove-AzResource -ResourceId $step.Id -ApiVersion $MissionApiVersion -Force | Out-Null
                Write-Ok "Deleted $($step.Name)"
            }
        }
        catch {
            Write-Warn "Could not delete $($step.Name): $($_.Exception.Message)"
        }
    }

    Write-Info 'The CMK Key Vault stays soft-deleted (purge protection) for 7 days; redeploying recovers it automatically.'
}

#endregion

#region Main --------------------------------------------------------------------

if ($StartAtStage -gt $StopAfterStage) { throw '-StartAtStage cannot be greater than -StopAfterStage.' }

Initialize-Settings
Initialize-Environment

if ($Teardown) {
    Invoke-Teardown
    return
}

$total = [System.Diagnostics.Stopwatch]::StartNew()

if ($StartAtStage -gt 1) { Assert-StageSucceeded ([math]::Min($StartAtStage - 1, 4)) }

if ($StartAtStage -le 1) { Invoke-Stage1 }
if ($StartAtStage -le 2 -and $StopAfterStage -ge 2) { Invoke-Stage2 }
if ($StartAtStage -le 3 -and $StopAfterStage -ge 3) { Invoke-Stage3 }
if ($StartAtStage -le 4 -and $StopAfterStage -ge 4) { Invoke-Stage4 }
if ($StopAfterStage -ge 5) { Invoke-Stage5 }

Write-Banner ("Done in {0:hh\:mm\:ss}" -f $total.Elapsed)
Write-Host @"

  Community        : $($Names.Community)  ($($Names.CommunityRg))
  Transit hub      : $($Names.TransitHub) -> peered to $($Names.CorpVnet)
  Community endpt  : $($Names.CommunityEndpoint)  (AD ports + RDP/ICMP to $CorpDestination)
  Enclave          : $($Names.Enclave)  ($($Names.EnclaveRg))
  Workload         : $($Names.Workload) -> $($Names.WorkloadRg)
  Enclave VM       : $($Names.EnclaveVm)
  Domain controller: $($Names.DcVm)  ($DcPrivateIp, $($Names.CorpRg), Bastion $($Names.CorpBastion))

  Next steps (see README.md):
    1. Bastion into $($Names.DcVm) and promote it to a domain controller.
    2. In bicep\demo.bicepparam set  useDcForEnclaveDns = true  and  adDomainName = '<your.domain>'
    3. Re-run with:  -StartAtStage 4      (points the enclave VM at AD DNS, then re-tests)
    4. Domain-join the enclave VM:  Add-Computer -DomainName <your.domain> -Restart

"@ -ForegroundColor Gray

#endregion
