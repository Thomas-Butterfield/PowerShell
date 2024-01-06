<#
.SYNOPSIS
    Places the Stars Oracle Application in maintenance mode

.DESCRIPTION
     Stops / Starts Websites configured on IIS during Stars Scheduled Maintenance or Outage

.PARAMETER Location
    Defines Oracle Stars Production or Maintenance Mode
  
.EXAMPLE
    PS> .\Start-Stop-Remote-IIS-Sites.ps1 -location Production

.NOTES
    Filename: Start-Stop-Remote-IIS-Sites.ps1
    Author: Thomas Butterfield
    Modified date: 2022-08-08
    Version 1.0
#>

param([Parameter(Mandatory=$false,HelpMessage="Please Specficy: Development or Production")][ValidateSet("Maintenance","Production")][string]$location)

If(!$location){
    Write-Host "No location parameter was set... Setting Oracle Aflex Rules To Production" -ForegroundColor Red -BackgroundColor White
    Start-Sleep -Seconds 3
    $location = "Production"
}

# Load required PowerShell Modules
Import-Module "IISAdministration"
Import-Module "Microsoft.PowerShell.SecretManagement"
Import-Module "Microsoft.PowerShell.SecretStore"

# Load CMSUAdmin Credentials From Local PowerShell Vault
$SWUser = (Get-Secret -Name secretName).GetNetworkCredential().Username
$SWPwSS = (Get-Secret -Name secretName).GetNetworkCredential().Password
[securestring]$SWsecStringPassword = ConvertTo-SecureString $SWPwSS -AsPlainText -Force
$cmsuAdminCred = [System.Management.Automation.PSCredential]::New($SWUser,$SWsecStringPassword)

# Stars Application Web Servers
$starsSrv = "server1.contoso.com","server2.contoso.com"
$webSrv = "server3.contoso.com"

# Proceed if credential object is loaded from Vault
If ($cmsuAdminCred){

    # Configured WSmanCredSSP
    Enable-WSmanCredSSP -Role "Client" -DelegateComputer "server1.contoso.com" -Force
    Enable-WSmanCredSSP -Role "Client" -DelegateComputer "server2.contoso.com" -Force
    Enable-WSmanCredSSP -Role "Client" -DelegateComputer "server3.contoso.com" -Force

    If ($location -eq "Maintenance"){
    
        $starsSrvSciptBlock = {

            Import-Module IISAdministration
            Stop-IISSite -Name "Application-Prod" -Confirm:$false
            Start-IISSite -Name "Application-Maintenance"
        }

        Invoke-Command -ComputerName $starsSrv -ScriptBlock $starsSrvSciptBlock -Credential $cmsuAdminCred -Authentication Negotiate

        $webSrvSciptBlock = {

            Import-Module IISAdministration
            Stop-IISSite -Name "CustomApp-Prod" -Confirm:$false
            Start-IISSite -Name "CustomApp-Prod-Maintenance"
        }

        Invoke-Command -ComputerName $webSrv -ScriptBlock $webSrvSciptBlock -Credential $cmsuAdminCred -Authentication Negotiate
    }

    Elseif ($location -eq "Production"){
    
        $starsSrvSciptBlock = {

            Import-Module IISAdministration
            Stop-IISSite -Name "Application-Maintenance" -Confirm:$false
            Start-IISSite -Name "Application-Prod"
        }

        Invoke-Command -ComputerName $starsSrv -ScriptBlock $starsSrvSciptBlock -ArgumentList($newPassword) -Credential $cmsuAdminCred -Authentication Negotiate

        $webSrvSciptBlock = {

            Import-Module IISAdministration
            Stop-IISSite -Name "CustomApp-Prod-Maintenance" -Confirm:$false
            Start-IISSite -Name "CustomApp-Prod"
        }

        Invoke-Command -ComputerName $servers -ScriptBlock $webSrvSciptBlock -ArgumentList($newPassword) -Credential $cmsuAdminCred -Authentication Negotiate

    }
}