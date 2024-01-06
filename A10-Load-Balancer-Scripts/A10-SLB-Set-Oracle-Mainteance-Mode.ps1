<#
.SYNOPSIS
    Places Oracle in maintenance mode by updating A10 SLB with aflex rule assignment and closes existing connections using session filter

.DESCRIPTION
    Changes the production Oracle SLB VIP to use either the 'ebsprod-oracle-cmsu' or 'oracle-outage-redirect' aflex rule

.PARAMETER Location
    Defines Oracle Production or Maintenance Mode aflex rule on A10.
  
.EXAMPLE
    PS> .\A10-SLB-Set-Oracle-Mainteance-Mode -location Production

.NOTES
    Filename: A10-SLB-Set-Oracle-Mainteance-Mode
    Author: Thomas Butterfield
    Modified date: 2022-08-08
    Version 1.0
#>

param([Parameter(Mandatory=$false,HelpMessage='Please Specficy: Development or Production')][ValidateSet("Maintenance","Production")][string]$location)

If(!$location){
    Write-Host "No location parameter was set... Setting Oracle Aflex Rules To Production" -ForegroundColor Red -BackgroundColor White
    Start-Sleep -Seconds 3
    $location = "Production"
}

# A10 Credentials
$username = "Username"
$password = "Password"

# A10 Credential Json
$jsoncreds = @"
{"credentials": {"username": "$username", "password": "$password"}}
"@

# A10 Variables
$a10ipaddr = "10.1.1.1" #Change This For IP A10
$prefix = "https://" #Prefix Https
$base = "/axapi/v3" #Base Uri
$a10apiURI = $prefix + $a10ipaddr + $base
$apiauth = $prefix + $a10ipaddr + $base +"/auth"
$logOffURI = "$a10apiURI/logoff"
$getActivePartitionURI = "$a10apiURI/active-partition"

# API always defaults to Shared Partition, this may not be necessary depnding on your A10 partition configuration.
$LANPartitionURI = "$a10apiURI/active-partition/LAN_Partition"

# Oracle SLB Virtual Server Name
$slb = @("vip-oracle-ebsprod-cmsu-API")
$Port80URI = "$a10apiURI/slb/virtual-server/$slb/port/80+http"
$Port8010URI = "$a10apiURI/slb/virtual-server/$slb/port/8010+http"
$redirFilterName = "Oracle-Outage-VIP"
$oraProdFilterName = "Oracle-API-VIP-Filter"


# Create Aflex Class & Object For JSON requests
class aflex {
    [string]$aflex

}

$aflexProduction = @([aflex]@{aflex='ebsprod-oracle-cmsu'})
$aflexOutage = @([aflex]@{aflex='oracle-outage-redirect'})

#Obtain Token Connection
$request = Invoke-RestMethod -Method Post -Uri "$apiauth" -Body $jsoncreds -ContentType application/json -ErrorVariable lostconnection | Select-Object -ExpandProperty authresponse
$signature = $request.Signature

If ($signature){
    
    # Define Header With Authorization Token
    $head = @{ Authorization= "A10 $signature"}


    Function Save-Changes-A10 {
        # Write to Memory To Save Changes
        $writeMemURI = "$a10apiURI/write/memory"
        Invoke-RestMethod -Uri $writeMemURI -Method Post -Headers $head -ContentType application/json
    }

    Function Set-LAN-Partition{
        # Get Current Active Partition
        $request = (Invoke-RestMethod -Uri $getActivePartitionURI -Method Get -Headers $head -ContentType application/json).'active-partition'

        # Set Partition To LAN_Partition to access Prodcution Oracle VIP
        If ($request.'partition-name' -eq "shared"){
            Write-Host "Changing Active Partition to LAN_Partition" -ForegroundColor Cyan
            Invoke-RestMethod -Uri $LANPartitionURI -Method Post -Headers $head -ContentType application/json
        }
    }

    Set-LAN-Partition
    # Get Oracle CMSU VIP
    # $oracleVIP = Invoke-RestMethod -Uri $uriOracleVIP -Method Get -Headers $head -ContentType application/json
    
    If ($location -eq "Maintenance"){

        #Get Existing Port Settings For VIP
        $oracle8010Port = Invoke-RestMethod -Uri $Port8010URI -Method Get -Headers $head -ContentType application/json
        $oracle80Port = Invoke-RestMethod -Uri $Port80URI -Method Get -Headers $head -ContentType application/json
        #Set New Values & Convert to JSON
        $oracle80Port.port | Add-Member -Name 'aflex-scripts' -MemberType NoteProperty -Value $aflexOutage -Force
        $oracle8010Port.port | Add-Member -Name 'aflex-scripts' -MemberType NoteProperty -Value $aflexOutage -Force
        $80json = $oracle80Port | ConvertTo-Json -Depth 20
        $8010json = $oracle8010Port | ConvertTo-Json -Depth 20

        # Update Aflex Rule And Place In Maintenance Mode
        Write-Host "Updating Aflex Rules to Maintenance Mode " -ForegroundColor Green
        Invoke-RestMethod -Uri $Port80URI -Method Post -Headers $head -ContentType application/json -Body $80json
        Invoke-RestMethod -Uri $Port8010URI -Method Post -Headers $head -ContentType application/json -Body $8010json
        Write-Host "Closing existing connections on A10 to Oracle " -ForegroundColor Cyan
        Invoke-RestMethod -Uri "$a10apiURI/sessions/oper?filter_type=filter&name-str=$oraProdFilterName" -Method Delete -Headers $head -ContentType application/json

        # Save Changes
        Write-Host "Saving Changes To A10 Config" -ForegroundColor Green
        Save-Changes-A10

    }

    Elseif ($location -eq "Production"){

        #Get Existing Port Settings For VIP
        $oracle8010Port = Invoke-RestMethod -Uri $Port8010URI -Method Get -Headers $head -ContentType application/json
        $oracle80Port = Invoke-RestMethod -Uri $Port80URI -Method Get -Headers $head -ContentType application/json
        #Set New Values & Convert to JSON
        $oracle80Port.port | Add-Member -Name 'aflex-scripts' -MemberType NoteProperty -Value $aflexProduction -Force
        $oracle8010Port.port.'aflex-scripts' = $null
        $80json = $oracle80Port | ConvertTo-Json -Depth 20
        $8010json = $oracle8010Port | ConvertTo-Json -Depth 20

        # Update Aflex Rule And Place In Maintenance Mode
        Write-Host "Updating Aflex Rules to Production Mode " -ForegroundColor Green
        Invoke-RestMethod -Uri $Port80URI -Method Post -Headers $head -ContentType application/json -Body $80json
        Invoke-RestMethod -Uri $Port8010URI -Method Post -Headers $head -ContentType application/json -Body $8010json
        Write-Host "Closing existing connections on A10 to Oracle Maintenance Page" -ForegroundColor Cyan
        Invoke-RestMethod -Uri "$a10apiURI/sessions/oper?filter_type=filter&name-str=$redirFilterName" -Method Delete -Headers $head -ContentType application/json
    
        # Save Changes
        Write-Host "Saving Changes To A10 Config" -ForegroundColor Green
        Save-Changes-A10
    }

    # Log Off Session
    Invoke-RestMethod -Uri $logOffURI -Method Post -Headers $head -ContentType application/json
}