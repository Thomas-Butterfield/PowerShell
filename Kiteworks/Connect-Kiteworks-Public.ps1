<#
.SYNOPSIS
    Generate new OAuth 2.0 token for a custom Kiteworks application using the 'Signature Authorization' workflow.

.DESCRIPTION
    Assembles mandatory paramters, encodes the secrets and executes post request and returns new OAuth token.

.LINK
    https://github.com/Thomas-Butterfield/PowerShell

.NOTES
    Filename: Connect-Kiteworks-Public.ps1
    Author: Thomas Butterfield 
    Modified date: 2022-08-24
    Version 1.0
#>

$kiteworksServer = "https://Kiteworks-URL"
$apiVersion = 24 # Update if using newer Version

function Get-Base64 {

param([Parameter(Mandatory=$true,HelpMessage='Specficy string to be converted to Base64 in UTF8 Encoding')][string]$text)

[string]$sStringToEncode = "$text"
$sEncodedString=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($sStringToEncode))

return $sEncodedString

}

function Get-Kiteworks-Token {

    # Custom Application Parameter Secrets
    $appId = "Client Application ID"
    $appSecret = "Client Secret Key" # Application Secret
    $clientEmail = "username@domain.com" # Email Address Of The User Account For Impersonation
    $sigSecret = "Signature Secret" # Application Signature Secret
    $redirectURI = "$kiteworksServer/rest/callback.html" # Set desired redirect URI, must match the value set inside Custom Application
    $scope = ""
    
    # Base64 Encode The Secrets
    $base64AppId = Get-Base64 -text $appId
    $base64ClientEmail = Get-Base64 -text $clientEmail

    $timeStamp = [Math]::Floor([decimal](Get-Date(Get-Date).ToUniversalTime()-uformat "%s"))  # Timestamp calculated from Epoch total seconds in UTC Timezone
    $nonce = Get-Random -Minimum 255555 -Maximum 999999 # Randomized seed

    <# Generate encoded & decoded base URL's #>
    $baseCode = '{0}|@@|{1}|@@|{2}|@@|{3}' -f $appId,$clientEmail,$timeStamp,$nonce
    $baseCode64 = '{0}|@@|{1}|@@|{2}|@@|{3}' -f $base64AppId,$base64ClientEmail,$timeStamp,$nonce

    <# Executre HMAC SHA1 calculation against Signature Secret & $basecode variable and convert to hexlower Format #>
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA1
    $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($sigSecret)
    $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($baseCode))
    $signature = -join($signature |ForEach-Object ToString X2).ToLower()
    $authToken = $basecode64 + "|@@|" + $signature

    <# OAuth Token Post request Header & Body #>
    
    $reqHeader = @{'Content-Type' = 'application/x-www-form-urlencoded'}

    $reqBody = [ordered]  @{
    
        client_id = $appId
        client_secret = $appSecret
        grant_type = 'authorization_code'
        code = $authToken
        redirect_uri = $redirectURI
        scope = $scope

    }

    try {
            $result = Invoke-RestMethod -Uri '$kiteworksServer/oauth/token' -Method Post -Body $reqBody -Headers $reqHeader
    }
    catch {
        
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Error $responseBody
            
    }

    return $result.access_token
    
}

$token = Get-Kiteworks-Token

If ($token){

    Write-Host "OAuth Token = $token" -ForegroundColor Magenta
    Start-Sleep -Seconds 2
    
    $authorizedheader = @{
    
        'accept' = 'application/json'
        'X-Accellion-Version' = $apiVersion
        'Authorization' = "Bearer $token"

    }

    $getMyUser = Invoke-RestMethod -Headers $authorizedheader -Method Get -Uri "$kiteworksServer/rest/users/me"
    
    If ($getMyUser.data){Write-Host "API Connected Sucessfully" -ForegroundColor Green}

}

Else {Write-Host "No Bearer Token Found, see error descriptione from Get-Kiteworks-Token function" -ForegroundColor Red}