<#
.SYNOPSIS
    Create / Update Required GitHub Branch Protection Rules
.DESCRIPTION
     Sets the required branch protection rules for a GitHub repo
.PARAMETER subscriptionId
    Azure Subscription Id
.PARAMETER secretName
    Key Vault Secret for Github Personal Access Token
.NOTES
    Filename: GitHub-Branch-Protection.ps1
    Author: Thomas Butterfield
    Modified date: 2023-10-31
    Version 1.0
#>

param(
    [Parameter(Mandatory=$true,HelpMessage="Please Specficy: Subscription ID containing Azure Key Vault")][string]$subscriptionId,
    [Parameter(Mandatory=$true,HelpMessage="Please Specficy: Keyvault Secret Naming Containing GitHub Personal Access Token")][string]$secretName
)

# Branch to be updated
$branch = "main"

# List of repositories to apply GitHub branch protection rules against.
$destinationRepoName = Get-Content -Path "./Documents/GitHub/github-repos.txt"

# SubscriptionID Containing Key Vault
$subscriptionId = "<SubscriptionId>"

# Key Vault Name
$vaultName = "<KeyVaultName>"

# GitHub Secret Name In Azure Key Vault
$secretName = "<SecretName>"

# Connect To Azure To Retrieve KeyVault Secret
Write-Host "Connecting to Azure Subscription" -ForegroundColor Cyan
Connect-AzAccount -Subscription $subscriptionId

If (!((Get-AzContext).Subscription -ne $subscriptionId)){
    Write-Host "Error Setting Correct Az Subscription, Please Check Your Az Permissions" -ForegroundColor Red
    Break
}

Write-Host "Retrieving Github Personal Access Token From Key Vault" -ForegroundColor Cyan
$token = (Get-AzKeyVaultSecret -VaultName $vaultName -Name $secretName).SecretValue | ConvertFrom-SecureString -AsPlainText

foreach ($repo in $destinationRepoName){

    $destinationURL = "https://api.github.com/repos/$repoOwner/$repo/branches/$branch/protection"
    
    If ($null -ne $token){

        Write-Host "Updating GitHub Repo Branch Protection Rules" -ForegroundColor Green
        $repoOwner = "<CompanyName>"
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/vnd.github+json"
            "X-GitHub-Api-Version" = "2022-11-28"
        }

        $body = @{
            "required_status_checks" = $null
            "enforce_admins"         = $true
            "required_pull_request_reviews" = @{
                "dismiss_stale_reviews" = $false
                "dismissal_restrictions" = @{
                    "users" = @('')
                    "teams" = @('cloud-infrastructure-team')
                }
                "bypass_pull_request_allowances" = @{
                "teams" = @('cloud-infrastructure-team')
                }
            }
            "restrictions" = $null
        }

        $response = Invoke-RestMethod -Method Put -Uri $destinationURL -Headers $headers -Body ($body | ConvertTo-Json -Depth 20)

        # Check the response from the GitHub API for any errors
        if ($response.errors) {
            throw $response.errors[0].message
        } else {
            Write-Output "$repo branch protection rules updated"
        }
    }
}

# Used to retrieve existing branch protection rules for troubleshooting & future updates
#$sourceRepoName = "<RepoName>"
#$protection = ((Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$repoOwner/$sourceRepoName/branches/$branch/protection" -Headers $headers) | ConvertTo-Json -Depth 20)
#$response = Invoke-RestMethod -Method Put -Uri $destinationURL -Headers $headers -Body $result
#$rule = $protection.Replace("$sourceRepoName","$destinationRepoName")
#$rule = ($rule | ConvertFrom-Json -Depth 20 )
