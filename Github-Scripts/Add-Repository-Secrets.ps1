 <#
.SYNOPSIS
    Create / Update Required GitHub Actions Repository Secrets
.DESCRIPTION
     Loads all required GitHub actions secrets from an Azure Key Vault and sets the values.

.PARAMETER repoName
    GitHub Repository Name

.PARAMETER token
    GitHub Personal Access Token - Generate Here > https://github.com/settings/tokens 
    Create a new personal access token (classic) and select Repo Full Control
  
.PARAMETER subscriptionId
    Azure Subscription Id

.EXAMPLE
    PS> .\Add-Github-Repo-Secrets.ps1 -repoName "my-repo-name" -token "ghp_ByGy8ADLKKJS9U" -subscriptionId "538df992-5c5a-42d6-abfb-831ce89a703e"
.NOTES
    Filename: Add-Repository-Secrets.ps1
    Author: Thomas Butterfield
    Modified date: 2023-02-17
    Version 1.0
#>

param(
    [Parameter(Mandatory=$true,HelpMessage="Please Specficy: GitHub Repository Name")][string]$repoName,
    [Parameter(Mandatory=$true,HelpMessage="Please Specficy: GitHub Personal Access Token")][string]$token,
    [Parameter(Mandatory=$true,HelpMessage="Please Specficy: New Azure Subscription ID")][string]$subscriptionId,
    [Parameter(Mandatory=$true,HelpMessage="Please Specficy: New Azure Subscription Terraform State Container Name")][string]$containerName
)

# Get PS Modules for encrypting GitHub repo secrets
Install-Module -Name PSSodium
Import-Module -Name PSSodium

$keyVaultSubscriptionId = "<Subscription-ID>"
Connect-AzAccount -Subscription $keyVaultSubscriptionId

If (!((Get-AzContext).Subscription -ne $keyVaultSubscriptionId)){
    Write-Host "Error Setting Correct Az Subscription, Please Check Your Az Permissions" -ForegroundColor Red
    Break
}

Else {

    $vaultName = "<vault-name>"
    $secrets = Get-AzKeyVaultSecret -VaultName $vaultName | Where-Object {$_.Name -like "GITHUB-*" -and $_.Name -ne "GITHUB-<UserName>-PAT"}

    $repoOwner = "<Your-Company-Name>"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Accept" = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    foreach ($secret in $secrets){

        $secretName = ($secret.Name).Replace("GITHUB-","").Replace("-","_") 
        $secretValue = (Get-AzKeyVaultSecret -VaultName $vaultName -Name $Secret.name).SecretValue | ConvertFrom-SecureString -AsPlainText

        $getKey = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$repoOwner/$repoName/actions/secrets/public-key" -Headers $headers
        $publickey = $getkey.key
        $keyid = $getkey.key_id

        # Create the secret in the repository using the GitHub API
        $url = "https://api.github.com/repos/$repoOwner/$repoName/actions/secrets/$secretName"
        $body = @{
            "encrypted_value" = ConvertTo-SodiumEncryptedString -Text $secretValue -PublicKey $publicKey
            "key_id"          = $keyid
        }
        $response = Invoke-RestMethod -Method Put -Uri $url -Headers $headers -Body ($body | ConvertTo-Json)

        # Check the response from the GitHub API for any errors
        if ($response.errors) {
            throw $response.errors[0].message
        } else {
            Write-Output "Secret '$secretName' added to repository '$repoOwner/$repoName'."
        }
    }

    $secretName = "SUBSCRIPTION_ID"
    $getKey = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$repoOwner/$repoName/actions/secrets/public-key" -Headers $headers
    $publickey = $getkey.key
    $keyid = $getkey.key_id

    # Create the secret in the repository using the GitHub API
    $url = "https://api.github.com/repos/$repoOwner/$repoName/actions/secrets/$secretName"
    $encryptedValue = ConvertTo-SodiumEncryptedString -Text $subscriptionId -PublicKey $publicKey
    $body = @{
        "encrypted_value" = $encryptedValue
        "key_id"          = $keyid
    }

    $response = Invoke-RestMethod -Method Put -Uri $url -Headers $headers -Body ($body | ConvertTo-Json)

    # Check the response from the GitHub API for any errors
    if ($response.errors) {
        throw $response.errors[0].message
    } else {
        Write-Output "Secret '$secretName' added to repository '$repoOwner/$repoName'."
    }

    $secretName = "TFSTATE_CONTAINER"
    $getKey = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$repoOwner/$repoName/actions/secrets/public-key" -Headers $headers
    $publickey = $getkey.key
    $keyid = $getkey.key_id

    # Create the secret in the repository using the GitHub API
    $url = "https://api.github.com/repos/$repoOwner/$repoName/actions/secrets/$secretName"
    $encryptedValue = ConvertTo-SodiumEncryptedString -Text $containerName -PublicKey $publicKey
    $body = @{
        "encrypted_value" = $encryptedValue
        "key_id"          = $keyid
    }

    $response = Invoke-RestMethod -Method Put -Uri $url -Headers $headers -Body ($body | ConvertTo-Json)

    # Check the response from the GitHub API for any errors
    if ($response.errors) {
        throw $response.errors[0].message
    } else {
        Write-Output "Secret '$secretName' added to repository '$repoOwner/$repoName'."
    }
}