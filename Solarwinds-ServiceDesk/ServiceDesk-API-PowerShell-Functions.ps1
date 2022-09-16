<#
.SYNOPSIS
    Solarwinds Service Desk API PowerShell functions

.DESCRIPTION
    A collection of useful PowerShell fucnctions that utilize the Solarwinds 
    Service Desk API. More details on API can be found here https://apidoc.samanage.com
  
.EXAMPLE
    PS> .\ServiceDesk-API-PowerShell-Functions.ps1

.NOTES
    Filename: ServiceDesk-API-PowerShell-Functions.ps1
    Author: Thomas Butterfield
    Modified date: 2022-09-16
    Version 1.0
#>

param(
    [string]$APIServiceURL = "https://api.samanage.com", # Update URL to Development or Production Instance
    [int]$RecordsPerPage = 100,
    [int]$MaxRetry = 3,
    [int]$MaxJobs = 16,
    [string]$APIToken = "YourAPIToken" # Set API Token
)

$headers = @{}
$headers.Add("X-Samanage-Authorization", "Bearer {0}" -f $apiToken)

function Get-SDCategory{
    param([int]$Id,[Switch]$All)
    if($All){
        $allItems = @()

        $baseUri = "{0}/categories.json" -f $apiServiceUrl
        $i = 0
        do{
            $i += 1
            $requestUri = "{0}?per_page={1}&page={2}" -f $baseUri, $RecordsPerPage, $i
            $response = Invoke-RestMethod -Uri $requestUri -Method Get -Headers $headers -ContentType "application/json"
            $allItems += $response
        }while(($response | measure).Count -gt 0)

        return $allItems
    }
    elseif($Id){
        $requestUri = "{0}/hardwares/{1}.json" -f $apiServiceUrl, $Id
        $response = Invoke-RestMethod -Uri $requestUri -Method Get -Headers $headers -ContentType "application/json"
        return $response
    }
}

function Get-SDHardwareAsset{
    param([int]$Id,[Switch]$All)
    if($All){
        $start = Get-Date
        $allAssets = @()
        $assetsUri = "{0}/hardwares.json" -f $apiServiceUrl

        $requestUri = "{0}?per_page={1}" -f $assetsUri, $RecordsPerPage
        $response = Invoke-WebRequest -Uri $requestUri -Method Get -Headers $headers
        $pageCount = [int]$response.Headers["X-Total-Pages"]
        $recordCount = [int]$response.Headers["X-Total-Count"]

        $pages = @()
        1..$pageCount | %{
            $page = $_
            $pages += New-Object PSObject -Property @{
                "Number"     = $page
                "Uri"        = "{0}?per_page={1}&page={2}" -f $assetsUri, $RecordsPerPage, $page
                "QueryCount" = "0"
                "Status"     = "New"
                "Data"       = @()
            }
        }
        
        foreach($page in $pages){
            Start-Job -Name $page.Number -ScriptBlock { Invoke-RestMethod -Uri $args[0] -Method Get -Headers $args[1] -ContentType "application/json" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue } -argumentlist $page.Uri,$headers | Out-Null
            if( (Get-Job -State Running | measure).Count -ge $MaxJobs ){ Get-Job -State Running | Wait-Job -Any | Out-Null }
        }

        while(Get-Job){
            $complete = Get-Job | Wait-Job -Any
            foreach($job in $complete){
                $page = $pages | WHERE Number -eq $job.name
                if($job.State -eq "Completed" -and $job.HasMoreData -eq $true){
                    $page.Data = $job | Receive-Job
                    $page.Status = "Complete"
                    $job | Remove-Job | Out-Null
                }
                else{
                    $job | Remove-Job | Out-Null
                    $page.QueryCount += 1
                    if($page.QueryCount -ge $maxRetry){
                        $page.Status = "Error"
                    }
                    else{
                        $page.Status = "Retry"
                        if( (Get-Job -State Running | measure).Count -ge $MaxJobs ){ Get-Job -State Running | Wait-Job -Any | Out-Null }
                        Start-Job -Name $page.Number -ScriptBlock { Invoke-RestMethod -Uri $args[0] -Method Get -Headers $args[1] -ContentType "application/json" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue } -argumentlist $page.Uri,$headers | Out-Null
                    }
                }
                
            }
            
        }
        return $pages
    }
    elseif($Id){
        $requestUri = "{0}/hardwares/{1}.json" -f $apiServiceUrl, $Id
        $response = Invoke-RestMethod -Uri $requestUri -Method Get -Headers $headers -ContentType "application/json"
        return $response
    }
}

function Add-SDHardwareAsset{
    param([Parameter(Mandatory=$true)][string]$Name, [Parameter(Mandatory=$true)][string]$SerialNumber, [string]$Description, [string]$Site, [string]$Department, [string]$Category, [string]$IPAddress, [string]$ExternalIP,
          [ValidateSet("Broken","Disposed","Duplicate","Hold","In Repair","Lost","Operational","Replacement","Spare","Stolen")][string]$Status, [string]$TechnicalContact, 
          [string]$Owner, [string]$Notes, [string]$CPU, [string]$Memory, [string]$Swap, [string]$Domain, [string]$OperatingSystem, [string]$ActiveDirectory, [string]$Address, 
          [string]$ProductNumber, [string]$Tag, [string]$AssetTag, [string]$Manufacturer, [string]$Model)

    $reqBody = @{ "hardware"=
        [ordered]@{ "name"              = $Name
                    "description"       = $Description
                    "site"              = if($site){@{"name" = $Site}}else{$Null}
                    "department"        = if($Department){@{"name" = $Department}}else{$Null}
                    "category"          = if($Category){@{"name" = $Category}}else{$Null}
                    "ip_address"        = $IPAddress
                    "external_ip"       = $ExternalIP
                    "status"            = if($Status){@{"name" = $Status}}else{$Null}
                    "technical_contact" = if($TechnicalContact){@{"email" = $TechnicalContact}}else{$Null}
                    "owner"             = if($Owner){@{"email" = $Owner}}else{$Null}
                    "notes"             = $Notes
                    "cpu"               = $CPU
                    "memory"            = $Memory
                    "swap"              = $Swap
                    "domain"            = $Domain
                    "operating_system"  = $OperatingSystem
                    "active_directory"  = $ActiveDirectory
                    "address"           = $Address
                    "product_number"    = $ProductNumber
                    "tag"               = $Tag
                    "asset_tag"         = $AssetTag
                    "bio"               = [ordered]@{
                                            "manufacturer" = $Manufacturer
                                            "ssn"          = $SerialNumber
                                            "model"        = $Model
                                            }
         }
    }
    $remove = @()
    foreach($key in $reqBody.hardware.bio.Keys){ if($reqBody.hardware.bio[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.hardware.bio.Remove($key) }

    if($reqBody.hardware.bio.Keys.Count -eq 0){ $reqBody.hardware.Remove("bio") }

    $remove = @()
    foreach($key in $reqBody.hardware.Keys){ if($reqBody.hardware[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.hardware.Remove($key) }
    
    $reqBody = $reqBody | ConvertTo-Json -Compress
    
    $requestUri = "{0}/hardwares.json" -f $APIServiceURL
    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Post -Headers $headers -ContentType "application/json" -Body $reqBody
        $response = @{"Status" = "OK"; "Data" = $response; "URI" = $requestUri; "Body" = $reqBody}
    }
    catch{
        $response = @{"Status" = "Error"; "Data" = $Error[-1]; "URI" = $requestUri; "Body" = $reqBody}
        $Error.Clear()
    }
    return $response
}

function Set-SDHardwareAsset{
    param([Parameter(Mandatory=$true)][int]$id, [string]$Name, [string]$SerialNumber, [string]$Description, [string]$Site, [string]$Department, [string]$Category, [string]$IPAddress, [string]$ExternalIP,
          [ValidateSet("Broken","Disposed","Duplicate","Hold","In Repair","Lost","Operational","Replacement","Spare","Stolen")][string]$Status, [string]$TechnicalContact, 
          [string]$Owner, [string]$Notes, [string]$CPU, [string]$Memory, [string]$Swap, [string]$Domain, [string]$OperatingSystem, [string]$ActiveDirectory, [string]$Address, 
          [string]$ProductNumber, [string]$Tag, [string]$AssetTag, [string]$Manufacturer, [string]$Model)

    $reqBody = @{ "hardware"=
        [ordered]@{ "name"              = $Name
                    "description"       = $Description
                    "site"              = if($site){@{"name" = $Site}}else{$Null}
                    "department"        = if($Department){@{"name" = $Department}}else{$Null}
                    "category"          = if($Category){@{"name" = $Category}}else{$Null}
                    "ip_address"        = $IPAddress
                    "external_ip"       = $ExternalIP
                    "status"            = if($Status){@{"name" = $Status}}else{$Null}
                    "technical_contact" = if($TechnicalContact){@{"email" = $TechnicalContact}}else{$Null}
                    "owner"             = if($Owner){@{"email" = $Owner}}else{$Null}
                    "notes"             = $Notes
                    "cpu"               = $CPU
                    "memory"            = $Memory
                    "swap"              = $Swap
                    "domain"            = $Domain
                    "operating_system"  = $OperatingSystem
                    "active_directory"  = $ActiveDirectory
                    "address"           = $Address
                    "product_number"    = $ProductNumber
                    "tag"               = $Tag
                    "asset_tag"         = $AssetTag
                    "bio"               = [ordered]@{
                                            "manufacturer" = $Manufacturer
                                            "ssn"          = $SerialNumber
                                            "model"        = $Model
                                            }
         }
    }
    $remove = @()
    foreach($key in $reqBody.hardware.bio.Keys){ if($reqBody.hardware.bio[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.hardware.bio.Remove($key) }

    if($reqBody.hardware.bio.Keys.Count -eq 0){ $reqBody.hardware.Remove("bio") }

    $remove = @()
    foreach($key in $reqBody.hardware.Keys){ if($reqBody.hardware[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.hardware.Remove($key) }
    
    $reqBody = $reqBody | ConvertTo-Json -Compress
    
    $requestUri = "{0}/hardwares/{1}.json" -f $APIServiceURL, $Id
    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Put -Headers $headers -ContentType "application/json" -Body $reqBody
    }
    catch{
        $response = @{"Status" = "Error"; "Error" = $Error[-1]; "URI" = $requestUri; "Body" = $reqBody}
        $Error.Clear()
    }
    return $response
}

function Remove-SDHardwareAsset{
    param([Parameter(Mandatory=$true)][int]$Id)

    $requestUri = "{0}/hardwares/{1}.json" -f $APIServiceURL, $Id

    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Delete -Headers $headers -ContentType "application/json"
        $response = @{"Status" = "OK"; "Data" = $response; "URI" = $requestUri}
    }
    catch{
        $response = @{"Status" = "Error"; "Data" = $Error[-1].Exception; "URI" = $requestUri}
        $Error.Clear()
    }
    return $response
}

function Get-SDMobileAsset{
    param([int]$Id,[Switch]$All)
    if($All){
        $start = Get-Date
        $allAssets = @()
        $assetsUri = "{0}/mobiles.json" -f $apiServiceUrl

        $requestUri = "{0}?per_page={1}" -f $assetsUri, $RecordsPerPage
        $response = Invoke-WebRequest -Uri $requestUri -Method Get -Headers $headers
        $pageCount = [int]$response.Headers["X-Total-Pages"]
        $recordCount = [int]$response.Headers["X-Total-Count"]

        $pages = @()
        1..$pageCount | %{
            $page = $_
            $pages += New-Object PSObject -Property @{
                "Number"     = $page
                "Uri"        = "{0}?per_page={1}&page={2}" -f $assetsUri, $RecordsPerPage, $page
                "QueryCount" = "0"
                "Status"     = "New"
                "Data"       = @()
            }
        }
        
        foreach($page in $pages){
            Start-Job -Name $page.Number -ScriptBlock { Invoke-RestMethod -Uri $args[0] -Method Get -Headers $args[1] -ContentType "application/json" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue } -argumentlist $page.Uri,$headers | Out-Null
            if( (Get-Job -State Running | measure).Count -ge $MaxJobs ){ Get-Job -State Running | Wait-Job -Any | Out-Null }
        }

        while(Get-Job){
            $complete = Get-Job | Wait-Job -Any
            foreach($job in $complete){
                $page = $pages | WHERE Number -eq $job.name
                if($job.State -eq "Completed" -and $job.HasMoreData -eq $true){
                    $page.Data = $job | Receive-Job
                    $page.Status = "Complete"
                    $job | Remove-Job | Out-Null
                }
                else{
                    $job | Remove-Job | Out-Null
                    $page.QueryCount += 1
                    if($page.QueryCount -ge $maxRetry){
                        $page.Status = "Error"
                    }
                    else{
                        $page.Status = "Retry"
                        if( (Get-Job -State Running | measure).Count -ge $MaxJobs ){ Get-Job -State Running | Wait-Job -Any | Out-Null }
                        Start-Job -Name $page.Number -ScriptBlock { Invoke-RestMethod -Uri $args[0] -Method Get -Headers $args[1] -ContentType "application/json" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue } -argumentlist $page.Uri,$headers | Out-Null
                    }
                }
                
            }
            
        }
        return $pages
    }
    elseif($Id){
        $requestUri = "{0}/mobiles/{1}.json" -f $apiServiceUrl, $Id
        $response = Invoke-RestMethod -Uri $requestUri -Method Get -Headers $headers -ContentType "application/json"
        return $response
    }
}

function Set-SDMobileAsset{
    param([Parameter(Mandatory=$true)][int]$id, [string]$Name, [string]$SerialNumber, [string]$Description, [string]$Site, [string]$Department, [string]$Category, [string]$IPAddress, [string]$ExternalIP,
          [ValidateSet("Broken","Disposed","Duplicate","Hold","In Repair","Lost","Operational","Replacement","Spare","Stolen")][string]$Status, [string]$TechnicalContact, 
          [string]$Owner, [string]$Notes, [string]$CPU, [string]$Memory, [string]$Swap, [string]$Domain, [string]$OperatingSystem, [string]$ActiveDirectory, [string]$Address, 
          [string]$ProductNumber, [string]$Tag, [string]$AssetTag, [string]$Manufacturer, [string]$Model)

    $reqBody = @{ "hardware"=
        [ordered]@{ "name"              = $Name
                    "description"       = $Description
                    "site"              = if($site){@{"name" = $Site}}else{$Null}
                    "department"        = if($Department){@{"name" = $Department}}else{$Null}
                    "category"          = if($Category){@{"name" = $Category}}else{$Null}
                    "ip_address"        = $IPAddress
                    "external_ip"       = $ExternalIP
                    "status"            = if($Status){@{"name" = $Status}}else{$Null}
                    "technical_contact" = if($TechnicalContact){@{"email" = $TechnicalContact}}else{$Null}
                    "owner"             = if($Owner){@{"email" = $Owner}}else{$Null}
                    "notes"             = $Notes
                    "cpu"               = $CPU
                    "memory"            = $Memory
                    "swap"              = $Swap
                    "domain"            = $Domain
                    "operating_system"  = $OperatingSystem
                    "active_directory"  = $ActiveDirectory
                    "address"           = $Address
                    "product_number"    = $ProductNumber
                    "tag"               = $Tag
                    "asset_tag"         = $AssetTag
                    "bio"               = [ordered]@{
                                            "manufacturer" = $Manufacturer
                                            "ssn"          = $SerialNumber
                                            "model"        = $Model
                                            }
         }
    }
    $remove = @()
    foreach($key in $reqBody.hardware.bio.Keys){ if($reqBody.hardware.bio[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.hardware.bio.Remove($key) }

    if($reqBody.hardware.bio.Keys.Count -eq 0){ $reqBody.hardware.Remove("bio") }

    $remove = @()
    foreach($key in $reqBody.hardware.Keys){ if($reqBody.hardware[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.hardware.Remove($key) }
    
    $reqBody = $reqBody | ConvertTo-Json
    
    $requestUri = "{0}/hardwares/{1}.json" -f $APIServiceURL, $Id
    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Put -Headers $headers -ContentType "application/json" -Body $reqBody
    }
    catch{
        $response = @{"Status" = "Error"; "Error" = $Error[-1]; "URI" = $requestUri; "Body" = $reqBody}
        $Error.Clear()
    }
    return $response
}

function Get-SDUser{
    param([int]$Id,[Switch]$All)
    if($All){
        $allUsers = @()

        $usersUri = "{0}/users.json" -f $apiServiceUrl
        $i = 0
        do{
            $i += 1
            $requestUri = "{0}?per_page={1}&page={2}" -f $usersUri, $RecordsPerPage, $i
            $response = Invoke-RestMethod -Uri $requestUri -Method Get -Headers $headers -ContentType "application/json"
            $allUsers += $response
        }while(($response | measure).Count -gt 0)
        return $allUsers
    }
    elseif($Id){
        $requestUri = "{0}/users/{1}.json" -f $apiServiceUrl, $Id
        $response = Invoke-RestMethod -Uri $requestUri -Method Get -Headers $headers -ContentType "application/json"
        return $response
    }
}

function Set-SDUserCustomField{
    param([int]$Id,[string]$Name,[String]$Value)
    
    If($Value -match "^(?<month>\d{1,2})/(?<day>\d{1,2})/(?<year>\d{2,4})$"){
        $value = "{0}-{1}-{2}" -f $Matches["year"], $Matches["month"], $Matches["day"]
    }

    $reqBody = @{ "user"=
        @{ "custom_fields_values"=
            @{ "custom_fields_value"=
                @( 
                    @{ "value"=$Value; "name"=$Name }
                )
            } 
        }
    }
    $reqBody = $reqBody | ConvertTo-Json -Compress -Depth 10

    $requestUri = "{0}/users/{1}.json" -f $apiServiceUrl, $Id
    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Put -Headers $headers -ContentType "application/json" -Body $reqBody
    }
    catch{
        $response = $Error
    }
    return $response
}

function Get-SDOtherAsset{
    param([int]$Id,[Switch]$All)
    if($All){
        $start = Get-Date
        $allAssets = @()
        $assetsUri = "{0}/other_assets.json" -f $apiServiceUrl

        $requestUri = "{0}?per_page={1}" -f $assetsUri, $RecordsPerPage
        $response = Invoke-WebRequest -Uri $requestUri -Method Get -Headers $headers
        $pageCount = [int]$response.Headers["X-Total-Pages"]
        $recordCount = [int]$response.Headers["X-Total-Count"]

        $pages = @()
        1..$pageCount | %{
            $page = $_
            $pages += New-Object PSObject -Property @{
                "Number"     = $page
                "Uri"        = "{0}?per_page={1}&page={2}" -f $assetsUri, $RecordsPerPage, $page
                "QueryCount" = "0"
                "Status"     = "New"
                "Data"       = @()
            }
        }
        
        foreach($page in $pages){
            Start-Job -Name $page.Number -ScriptBlock { Invoke-RestMethod -Uri $args[0] -Method Get -Headers $args[1] -ContentType "application/json" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue } -argumentlist $page.Uri,$headers | Out-Null
            if( (Get-Job -State Running | measure).Count -ge $MaxJobs ){ Get-Job -State Running | Wait-Job -Any | Out-Null }
        }

        while(Get-Job){
            $complete = Get-Job | Wait-Job -Any
            foreach($job in $complete){
                $page = $pages | WHERE Number -eq $job.name
                if($job.State -eq "Completed" -and $job.HasMoreData -eq $true){
                    $page.Data = $job | Receive-Job
                    $page.Status = "Complete"
                    $job | Remove-Job | Out-Null
                }
                else{
                    $job | Remove-Job | Out-Null
                    $page.QueryCount += 1
                    if($page.QueryCount -ge $maxRetry){
                        $page.Status = "Error"
                    }
                    else{
                        $page.Status = "Retry"
                        if( (Get-Job -State Running | measure).Count -ge $MaxJobs ){ Get-Job -State Running | Wait-Job -Any | Out-Null }
                        Start-Job -Name $page.Number -ScriptBlock { Invoke-RestMethod -Uri $args[0] -Method Get -Headers $args[1] -ContentType "application/json" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue } -argumentlist $page.Uri,$headers | Out-Null
                    }
                }
                
            }
            
        }
        return $pages
    }
    elseif($Id){
        $requestUri = "{0}/other_assets/{1}.json" -f $apiServiceUrl, $Id
        $response = Invoke-RestMethod -Uri $requestUri -Method Get -Headers $headers -ContentType "application/json"
        return $response
    }
}

function Add-SDOtherAsset{
    param([Parameter(Mandatory=$true)][string]$Name, [string]$Description, [string]$Site, [string]$Department, [string]$AssetID, [Parameter(Mandatory=$true)][string]$AssetType, 
          [Parameter(Mandatory=$true)][ValidateSet("Broken","Disposed","Duplicate","Hold","In Repair","Lost","Operational","Replacement","Spare","Stolen")][string]$Status, 
          [Parameter(Mandatory=$true)][string]$Manufacturer, [string]$IPAddress, [string]$Model, [string]$SerialNumber, [string]$User, [string]$Owner)

    $reqBody = @{ "other_asset"=
        [ordered]@{ "name" = $Name
                    "description"   = $Description
                    "site"          = if($site){@{"name" = $Site}}else{$Null}
                    "department"    = if($Department){@{"name" = $Department}}else{$Null}
                    "asset_id"      = $AssetID
                    "asset_type"    = if($AssetType){@{"name" = $AssetType}}else{$Null}
                    "status"        = if($Status){@{"name" = $Status}}else{$Null}
                    "manufacturer"  = $Manufacturer
                    "model"         = $Model
                    "serial_number" = $SerialNumber
                    "user"          = if($User){@{"email" = $User}}else{$Null}
                    "owner"         = if($User){@{"email" = $User}}else{$Null}
         }
    }
    $remove = @()
    foreach($key in $reqBody.other_asset.Keys){ if($reqBody.other_asset[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.other_asset.Remove($key) }

    $reqBody = $reqBody | ConvertTo-Json -Compress
    
    $requestUri = "{0}/other_assets.json" -f $APIServiceURL
    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Post -Headers $headers -ContentType "application/json" -Body $reqBody
        $response = @{"Status" = "OK"; "Error" = $response; "URI" = $requestUri; "Body" = $reqBody}
    }
    catch{
        $response = @{"Status" = "Error"; "Data" = $Error[-1].Exception; "URI" = $requestUri; "Body" = $reqBody}
        $Error.Clear()
    }
    return $response
}

function Remove-SDOtherAsset{
    param([Parameter(Mandatory=$true)][int]$Id)

    $requestUri = "{0}/other_assets/{1}.json" -f $APIServiceURL, $Id

    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Delete -Headers $headers -ContentType "application/json"
        $response = @{"Status" = "OK"; "Data" = $response; "URI" = $requestUri}
    }
    catch{
        $response = @{"Status" = "Error"; "Data" = $Error[-1].Exception; "URI" = $requestUri}
        $Error.Clear()
    }
    return $response
}

function Set-SDOtherAsset{
    param([Parameter(Mandatory=$true)][string]$Id, [string]$Name, [string]$Description, [string]$Site, [string]$Department, [string]$AssetID, [string]$AssetType, 
          [ValidateSet("Broken","Disposed","Duplicate","Hold","In Repair","Lost","Operational","Replacement","Spare","Stolen")][string]$Status, [string]$Manufacturer, [string]$IPAddress, 
          [string]$Model, [string]$SerialNumber, [string]$User, [string]$Owner, [hashtable]$CustomFields)

    $reqBody = @{ "other_asset"=
        [ordered]@{ "name"          = $Name
                    "description"   = $Description
                    "site"          = if($site){@{"name" = $Site}}else{$Null}
                    "department"    = if($Department){@{"name" = $Department}}else{$Null}
                    "asset_id"      = $AssetID
                    "asset_type"    = if($AssetType){@{"name" = $AssetType}}else{$Null}
                    "status"        = if($Status){@{"name" = $Status}}else{$Null}
                    "manufacturer"  = $Manufacturer
                    "model"         = $Model
                    "serial_number" = $SerialNumber
                    "user"          = if($User){@{"email" = $User}}else{$Null}
                    "owner"         = if($User){@{"email" = $User}}else{$Null}
         }
    }
    $remove = @()
    foreach($key in $reqBody.other_asset.Keys){ if($reqBody.other_asset[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.other_asset.Remove($key) }
    
    if($CustomFields){
        $pairs = @()
        foreach($key in $CustomFields.Keys){
            #$pairs += @{custom_fields_value = @{Value = $CustomFields[$key]; Name = $key}}
            $pairs += @{value = $CustomFields[$key]; name = $key}
        }
        $reqBody.other_asset.Add("custom_fields_values", 
                        @{custom_fields_value =  $pairs } 
                    )
    }


    $reqBody = $reqBody | ConvertTo-Json -Compress -Depth 5

    $requestUri = "{0}/other_assets/{1}.json" -f $APIServiceURL, $Id

    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Put -Headers $headers -ContentType "application/json" -Body $reqBody
        $response = @{"Status" = "OK"; "Error" = $response; "URI" = $requestUri; "Body" = $reqBody}
    }
    catch{
        $response = @{"Status" = "Error"; "Error" = $Error[-1]; "URI" = $requestUri; "Body" = $reqBody}
        $Error.Clear()
    }
    return $response
}

function Create-ServiceRequest {

    param(
        
        [Parameter(Mandatory=$true)][int]$CatalogID,
        [string]$SiteID,
        [string]$DepartmentID,
        [string]$RequesterEmail = "ServiceDeskAPI@us.medical.canon",
        [string]$Priority,
        [datetime]$DueAt,
        [hashtable]$RequestInputs
    )

    $reqBody = @{ "incident"=

        [ordered]@{ "site_id"        = $SiteID
                    "department_id"  = $DepartmentID
                    "requester_name" = $RequesterEmail
                    "priority"       = $Priority
                    "due_at"         = $DueAt
         }
    }

    $remove = @()
    foreach($key in $reqBody.incident.Keys){ if($reqBody.incident[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.incident.Remove($key) }
    
    if($RequestInputs){
        $pairs = @()
        foreach($key in $RequestInputs.Keys){
            $pairs += @{value = $RequestInputs[$key]; name = $key}
        }
        $reqBody.incident.Add("request_variables_attributes", $pairs)
    }

    $reqBody = $reqBody | ConvertTo-Json -Compress -Depth 5
    
    $requestUri = "{0}/catalog_items/{1}/service_requests.json" -f $APIServiceURL, $CatalogID
    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Post -Headers $headers -ContentType "application/json" -Body $reqBody
        $response = @{"Status" = "OK"; "Content" = $response; "URI" = $requestUri; "Body" = $reqBody}
    }
    catch{
        $response = @{"Status" = "Error"; "Data" = $Error[-1].Exception; "URI" = $requestUri; "Body" = $reqBody}
        $Error.Clear()
    }
    return $response


}

function Set-Incident {

    param(
        
        [Parameter(Mandatory=$true)][int]$IncidentID,
        [string]$SiteID,
        [string]$Name,
        [string]$DepartmentID,
        [string]$Description,
        [string]$StateID,
        [string]$Assignee,
        [string]$Priority,
        [string]$Requester,
        [string]$Category,
        [string]$SubCategory,
        [datetime]$DueAt,
        [hashtable]$CustomFields
    )

    $reqBody = @{ "incident"=
        [ordered]@{ "name"          = $Name
                    "site_id"       = $SiteID
                    "department_id" = $DepartmentID
                    "description"   = $Description
                    "state_id"      = $StateID
                    "assignee"      = if($Assignee){@{"email" = $Assignee}}else{$Null}
                    "priority"      = $Priority
                    "requester"     = if($Requester){@{"email" = $Requester}}else{$Null}
                    "category"      = $Category
                    "subcategory"   = $SubCategory
                    "due_at"        = $DueAt
         }
    }
    $remove = @()
    foreach($key in $reqBody.incident.Keys){ if($reqBody.incident[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.incident.Remove($key) }

    if ($CustomFields) {

        $pairs = @()
        foreach($key in $CustomFields.Keys){

            $pairs += @{value = $CustomFields[$key]; name = $key}
        }
        $reqBody.incident.Add("custom_fields_values", @{ custom_fields_value =  $pairs } )
    }

    $reqBody = $reqBody | ConvertTo-Json -Compress -Depth 5
    
    $requestUri = "{0}/incidents/{1}.json" -f $APIServiceURL, $IncidentID

    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Put -Headers $headers -ContentType "application/json" -Body $reqBody
        $response = @{"Status" = "OK"; "Content" = $response; "URI" = $requestUri; "Body" = $reqBody}
    }
    catch{
        $response = @{"Status" = "Error"; "Error" = $Error[-1]; "URI" = $requestUri; "Body" = $reqBody}
        $Error.Clear()
    }
    return $response

}

function Get-Incident {
    
    param(
        
        [Parameter(Mandatory=$true)][int]$IncidentID
    )


    $requestUri = "{0}/incidents/{1}.json" -f $APIServiceURL, $IncidentID

    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Put -Headers $headers -ContentType "application/json" -Body $reqBody
        $response = @{"Status" = "OK"; "Content" = $response; "URI" = $requestUri; "Body" = $reqBody}
    }
    catch{
        $response = @{"Status" = "Error"; "Error" = $Error[-1]; "URI" = $requestUri; "Body" = $reqBody}
        $Error.Clear()
    }
    return $response

}

function Set-Task {
    
    param(
        
        [Parameter(Mandatory=$true)][int]$IncidentID,
        [Parameter(Mandatory=$true)][int]$TaskId,
        [string]$Name,
        [string]$Assignee,
        [datetime]$DueAt,
        [boolean]$IsComplete
    )

    $reqBody = @{ "task"=
        [ordered]@{ "name"        = $Name
                    "assignee"    = if($Assignee){@{"email" = $Assignee}}else{$Null}
                    "due_at"      = $DueAt
                    "is_complete" = $IsComplete

         }
    }
    $remove = @()
    foreach($key in $reqBody.task.Keys){ if($reqBody.task[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.task.Remove($key) }

    $reqBody = $reqBody | ConvertTo-Json -Compress -Depth 5
    
    $requestUri = "{0}/incidents/{1}/tasks/{2}.json" -f $APIServiceURL, $IncidentID, $TaskId

    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Put -Headers $headers -ContentType "application/json" -Body $reqBody
        $response = @{"Status" = "OK"; "Error" = $response; "URI" = $requestUri; "Body" = $reqBody}
    }
    catch{
        $response = @{"Status" = "Error"; "Error" = $Error[-1]; "URI" = $requestUri; "Body" = $reqBody}
        $Error.Clear()
    }
    return $response

}

function Get-Task {
    
    param(
        
        [Parameter(Mandatory=$true)][int]$IncidentID,
        [int]$TaskId
    )
    
    if ($TaskId) {
        
        $requestUri = "{0}/incidents/{1}/tasks/{2}.json" -f $APIServiceURL, $IncidentID, $TaskId
    }
    else {
        
        $requestUri = "{0}/incidents/{1}/tasks.json" -f $APIServiceURL, $IncidentID
    }

     try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Get -Headers $headers -ContentType "application/json"
        $response = @{"Status" = "OK"; "Content" = $response; "URI" = $requestUri; "Body" = $null}
    }
    catch{
        $response = @{"Status" = "Error"; "Error" = $Error[-1]; "URI" = $requestUri; "Body" = $null}
        $Error.Clear()
    }
    return $response

}

function Create-Comment{
    param([Parameter(Mandatory=$true)][string]$Id, [ValidateSet("Incidents")][string]$objectType="incidents",[string]$comments)
    $body = $comment
    $reqBody = @{ "comment"=
        [ordered]@{ "body" = [string]"$comments"
            
         }
    }
    $remove = @()
    foreach($key in $reqBody.other_asset.Keys){ if($reqBody.other_asset[$key] -like $null){ $remove += $key } }
    foreach($key in $remove){ $reqBody.other_asset.Remove($key) }
    
    if($CustomFields){
        $pairs = @()
        foreach($key in $CustomFields.Keys){
            $pairs += @{value = $CustomFields[$key]; name = $key}
        }
        $reqBody.other_asset.Add("custom_fields_values", 
                        @{custom_fields_value =  $pairs } 
                    )
    }

    $reqBody = $reqBody | ConvertTo-Json -Compress -Depth 5

    $requestUri = "{0}/{1}/{2}/comments.json" -f $APIServiceURL, $objectType.ToLower() , $Id

    try{
        $response = Invoke-RestMethod -Uri $requestUri -Method Post -Headers $headers -ContentType "application/json" -Body $reqBody
        $response = @{"Status" = "OK"; "Error" = $response; "URI" = $requestUri; "Body" = $reqBody}
    }
    catch{
        $response = @{"Status" = "Error"; "Error" = $Error[-1]; "URI" = $requestUri; "Body" = $reqBody}
        $Error.Clear()
    }
    return $response
}
