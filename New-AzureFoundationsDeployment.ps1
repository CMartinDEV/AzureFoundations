
<#PSScriptInfo

.VERSION 1.0.0

.GUID 0137466b-0678-4984-a24b-862f412813d3

.AUTHOR chrismartin

.COMPANYNAME

.COPYRIGHT

.TAGS

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES

.PRIVATEDATA

#>

#Requires -Module PSSubnetCarver
#Requires -Module Az.Accounts
#Requires -Module Az.Network
#Requires -Module Az.Subscription
#Requires -Module ImportExcel

<# 

.DESCRIPTION 
 Deploy the Azure foundations framework from the Azure foundations worksheet 

#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Path,

    [Parameter(Mandatory, Position = 1)]
    [Guid]$TenantId
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'Import-AzureFoundationFunctions.ps1' -Resolve)

$accountInfo = Get-AvailableBillingAccount -TenantId $TenantId -ErrorAction Stop

$deploymentInfo = Get-DeploymentInfo -Path $Path -ErrorAction Stop

$subscriptions = @{}

$deploymentInfo | ForEach-Object -Process {

    if ($_.Account -eq 'Managed') {
        $workload = 'Production'
    }
    else {
        $workload = 'Sandbox'
    }

    $sub = New-FoundationsSubscription -Name $_.SubscriptionName -BillingAccountId $accountInfo.BillingAccountId -EnrollmentAccountId $accountInfo.EnrollmentId -Workload $workload -ErrorAction Stop

    $subscriptions[$_.Name] = $sub
}

$deploymentInfo = $deploymentInfo | ForEach-Object -Process {

    $null = Select-AzSubscription -SubscriptionId $subscriptions[$_.SubscriptionName].Id -ErrorAction Stop

    $primaryRg = New-AzResourceGroup -Name $_.PrimaryResourceGroupName -Location $_.PrimaryRegion -ErrorAction Stop
    $secondaryRg = New-AzResourceGroup -Name $_.SecondaryResourceGroupName -Location $_.SecondaryRegion -ErrorAction Stop

    $primaryVnet = New-AzVirtualNetwork -ResourceGroupName $primaryRg.PrimaryResourceGroupName -Name $_.PrimaryVirtualNetwork.Name -AddressPrefix $_.PrimaryVirtualNetwork.AddressSpace -Subnet $_.PrimaryVirtualNetwork.Subnets -ErrorAction Stop
    $secondaryVnet = New-AzVirtualNetwork -ResourceGroupName $secondaryRg.SecondaryResourceGroupName -Name $_.SecondaryVirtualNetwork.Name -AddressPrefix $_.SecondaryVirtualNetwork.AddressSpace -Subnet $_.SecondaryVirtualNetwork.Subnets -ErrorAction Stop

    $_.PrimaryVirtualNetwork.Subnets | ForEach-Object -Process {
        $null = New-AzNetworkSecurityGroup -ResourceGroupName $primaryRg.PrimaryResourceGroupName -Name $_.NetworkSecurityGroup -ErrorAction Stop
    }

    $_.SecondaryVirtualNetwork.Subnets | ForEach-Object -Process {
        $null = New-AzNetworkSecurityGroup -ResourceGroupName $secondaryRg.SecondaryResourceGroupName -Name $_.NetworkSecurityGroup -ErrorAction Stop
    }

    [PSCustomObject]@{
        SubscriptionName = $_.SubscriptionName
        Deployment = $_
        PrimaryResourceGroup = $primaryRg
        SecondaryResourceGroup = $secondaryRg
        PrimaryVirtualNetwork = $primaryVnet
        SecondaryVirtualNetwork = $secondaryVnet
    }
}

#TODO: Create Peering