
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

$WorksheetsToIgnore = @('Cover','Tables','Template','README')

function Get-AvailableBillingAccount {
    [CmdletBinding()]
    Param(
        [Guid]$TenantId
    )

    $token = Get-AzAccessToken -ResourceUrl 'https://management.azure.com/' -TenantId $TenantId -ErrorAction Stop | Select-Object -ExpandProperty Token

    $accounts = Invoke-RestMethod -Method Get -Headers @{ Authorization = "bearer $token" } -Uri 'https://management.azure.com/providers/Microsoft.Billing/billingaccounts/?api-version=2020-05-01'

    $accounts.value | ForEach-Object -Process { 

        $billingAccountId = $_.name

        $_.enrollmentAccounts | ForEach-Object -Process {

            [PSCustomObject]@{
                BillingAccountId = $billingAccountId
                EnrollmentId     = $_.Name
            }

        }
     }
}

function New-FoundationsSubscription {
    [CmdletBinding()]
    Param(
        $Name,
        $BillingAccountId,
        $EnrollmentAccountId,
        $Workload
    )

    $scope = "/providers/Microsoft.Billing/BillingAccounts/$($BillingAccountId)/enrollmentAccounts/$($EnrollmentAccountId)"

    $alias = $Name.Replace(" ","")

    $sub = New-AzSubscriptionAlias -AliasName $alias -SubscriptionName $Name -BillingScope $scope -Workload $Workload -ErrorAction Stop

    [PSCustomObject]@{
        Name = $Name
        Id   = $sub.properties.subscriptionId
    }
}

function Get-DeploymentInfo {
    [CmdletBinding()]
    Param(
        $Path
    )

    Get-ExcelFileSummary -Path $Path -ErrorAction Stop | Select-Object -ExpandProperty WorksheetName | Where-Object -FilterScript { $_ -notin $WorksheetsToIgnore } | ForEach-Object -Process {

        Format-FoundationsDeploymentWorksheet -Worksheet (Import-Excel -Path $Path -WorksheetName $_ -NoHeader -ErrorAction Stop) -ErrorAction Continue

    }


}

function Format-FoundationsDeploymentWorksheet {
    [CmdletBinding()]
    Param($Worksheet)

    $subscriptionName = $Worksheet[1].P2
    $account = $Worksheet[5].P7
    $pRegion    = $Worksheet[5].P4
    $sRegion  = $Worksheet[5].P12
    $pRgName    = $Worksheet[7].P5
    $sRgName  = $Worksheet[7].P13
    $pVnetName = $Worksheet[8].P5
    $sVnetName = $Worksheet[8].P13
    $pVnetIP = $Worksheet[9].P5
    $sVnetIP = $Worksheet[9].P13

    $pPeerInfo = @()
    $sPeerInfo = @()

    13..22 | ForEach-Object -Process { 
        if (-not ([string]::IsNullOrWhiteSpace($Worksheet[$_].P2))) {
            $pPeerInfo += [PSCustomObject]@{PeerName = $Worksheet[$_].P2; PeerTo = $Worksheet[$_].P5}
            $sPeerInfo += [PSCustomObject]@{PeerName = $Worksheet[$_].P10; PeerTo = $Worksheet[$_].P13}
        }
    }

    $pSubnets = @()
    $sSubnets = @()

    $row = 26

    while ($row -lt $Worksheet.Count) {
        if (-not ([string]::IsNullOrWhiteSpace($Worksheet[$row].P2))) {
            $pSubnets += [PSCustomObject]@{SubnetName = $Worksheet[$row].P2; AddressSpace = $Worksheet[$row].P5; NetworkSecurityGroup = $Worksheet[$row].P6}
            $sSubnets += [PSCustomObject]@{SubnetName = $Worksheet[$row].P10; AddressSpace = $Worksheet[$row].P13; NetworkSecurityGroup = $Worksheet[$row].P14}
        }

        ++$row
    }

    $pVirtualNetwork = [PSCustomObject]@{
        Name = $pVnetName
        AddressSpace = $pVnetIP
        Subnets = $pSubnets
        Peers = $pPeerInfo
    }

    $sVirtualNetwork = [PSCustomObject]@{
        Name = $sVnetName
        AddressSpace = $sVnetIP
        Subnets = $sSubnets
        Peers = $sPeerInfo
    }

    [PSCustomObject]@{
        SubscriptionName = $subscriptionName
        Account = $account
        PrimaryRegion = $pRegion
        SecondaryRegion = $sRegion
        PrimaryResourceGroupName = $pRgName
        SecondaryResourceGroupName = $sRgName
        PrimaryVirtualNetwork = $pVirtualNetwork
        SecondaryVirtualNetwork = $sVirtualNetwork
    }
}

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