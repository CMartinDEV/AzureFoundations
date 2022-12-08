
<#PSScriptInfo

.VERSION 0.0.1

.GUID a96ec6b8-e6ef-45a7-9dbd-0244cd71858c

.AUTHOR Chris Martin

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
#Requires -Module ImportExcel

<# 

.DESCRIPTION 
 Use the PSSubnetCarver module to turn the CIDR blocks in the Azure foundations worksheet into a carved network. 

#> 
[CmdletBinding()]
Param(
    $Path
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'Import-AzureFoundationFunctions.ps1' -Resolve)

$cover = Import-Excel -Path $Path -WorksheetName 'Cover' -NoHeader -ErrorAction Stop

$availableNetworkSpace = $cover[6].P4

Set-SCContext -Name AllAzure -RootAddressSpace $availableNetworkSpace -ErrorAction Stop

$deployments = Get-DeploymentInfo -Path $Path -ErrorAction Stop

$deployments = $deployments | ForEach-Object -Process {

    $primaryVirtualNetwork = $_.PrimaryVirtualNetwork
    $secondaryVirtualNetwork = $_.SecondaryVirtualNetwork

    $primaryAddressSpace = Get-SCSubnet -ContextName AllAzure -ReserveCIDR $primaryVirtualNetwork.AddressSpace -ErrorAction Stop
    $secondaryAddressSpace = Get-SCSubnet -ContextName AllAzure -ReserveCIDR $secondaryVirtualNetwork.AddressSpace -ErrorAction Stop

    Set-SCContext -Name "$($_.SubscriptionName)-$($_.PrimaryVirtualNetwork.Name)" -RootAddressSpace $primaryAddressSpace -ErrorAction Stop
    Set-SCContext -Name "$($_.SubscriptionName)-$($_.SecondaryVirtualNetwork.Name)" -RootAddressSpace $secondaryAddressSpace -ErrorAction Stop

    $primarySubnets = $primaryVirtualNetwork.Subnets | ForEach-Object -Process {
        Get-SCSubnet -ContextName "$($_.SubscriptionName)-$($_.PrimaryVirtualNetwork.Name)" -ReserveCIDR $_.AddressSpace -ErrorAction Stop
    }

    $secondarySubnets = $secondaryVirtualNetwork.Subnets | ForEach-Object -Process {
        Get-SCSubnet -ContextName "$($_.SubscriptionName)-$($_.SecondaryVirtualNetwork.Name)" -ReserveCIDR $_.AddressSpace -ErrorAction Stop
    }

    [PSCustomObject]@{
        SubscriptionName = $_.SubscriptionName
        PrimaryVirtualNetwork = [PSCustomObject]@{
            Name = $_.PrimaryVirtualNetwork.Name
            AddressSpace = $primaryAddressSpace
            Subnets = $primarySubnets
        }
        SecondaryVirtualNetwork = [PSCustomObject]@{
            Name = $_.SecondaryVirtualNetwork.Name
            AddressSpace = $secondaryAddressSpace
            Subnets = $secondarySubnets
        }
    }
}