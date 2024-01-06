 <#
.SYNOPSIS
    Update all Azure Subscription GitHub Repository Secrets
.DESCRIPTION
     Loads all required GitHub actions secrets from an Azure Key Vault and sets the values.

.PARAMETER token
    GitHub Personal Access Token - Generate Here > https://github.com/settings/tokens 
    Create a new personal access token (classic) and select Repo Full Control

.EXAMPLE
    PS> .\Update-GitHub-All-Repo-Secrets.ps1 -token "ghp_ByGy8A3UGO8INYIdsadsadsa" "
.NOTES
    Filename: Update-All-Repository-Secrets.ps1
    Author: Thomas Butterfield
    Modified date: 2023-12-21
    Version 1.0
#>

param(
    [Parameter(Mandatory=$true,HelpMessage="Please Specficy: GitHub Personal Access Token")][string]$token
)

Install-Module -Name PSSodium
Import-Module -Name PSSodium

$keyVaultSubscriptionId = "<SubscriptionID>"
Connect-AzAccount -Subscription $keyVaultSubscriptionId

If (!((Get-AzContext).Subscription -ne $keyVaultSubscriptionId)){
    Write-Host "Error Setting Correct Az Subscription, Please Check Your Az Permissions" -ForegroundColor Red
    Break
}

Else {

    $vaultName = "<KeyVaultName>"
    $secrets = Get-AzKeyVaultSecret -VaultName $vaultName | Where-Object {$_.Name -like "GITHUB-*" -and $_.Name -ne "<PAT-TOKEN>"}

    $repoOwner = "<CompanyName>"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Accept" = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    $repolist = (Invoke-RestMethod -Method Get -Uri "https://api.github.com/orgs/$repoOwner/repos?type=member&per_page=100" -Headers $headers).name | Where-Object {$_ -like "az-*" }

    foreach ($repo in $repolist) {

        $repoName = $repo

        foreach ($secret in $secrets){

            $secretName = ($secret.Name).Replace("GITHUB-","").Replace("-","_") 
            $secretValue = (Get-AzKeyVaultSecret -VaultName $vaultName -Name $Secret.name).SecretValue | ConvertFrom-SecureString -AsPlainText
            # $secretName
            # $secretValue

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
    }
}