<#
.SYNOPSIS
    Gitlab API Functions

.DESCRIPTION
    A collection of useful GitLab API Queries
  
.NOTES
    Filename: GitLab-API-Calls.ps1
    Author: Thomas Butterfield
    Modified date: 2022-08-12
    Version 1.0
#>

# GitLab Connection Variables
$gitLabPrivateToken = (Get-Secret -Name GitLab).GetNetworkCredential().Password
$headers = @{'PRIVATE-TOKEN'="$gitLabPrivateToken"}
$APIServiceURL = (Get-SecretInfo -Name GitLab).Metadata['WebServiceURL']
$PageCount = Invoke-Webrequest -Headers $headers -Uri "$APIServiceURL/users" -Method Get

function Get-GitLabUsers{

    $assetsUri = "{0}/users" -f $APIServiceURL
    $requestUri = "{0}?per_page={1}" -f $assetsUri, 20
    $response = Invoke-WebRequest -Uri $requestUri -Method Get -Headers $headers
    $pageCount = [int]$response.Headers["X-Total-Pages"]
    $RecordsPerPage = [int]$response.Headers["X-Per-Page"]

    $pages = @()
    1..$pageCount | ForEach-Object{
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
        if( (Get-Job -State Running | Measure-Object).Count -ge $MaxJobs ){ Get-Job -State Running | Wait-Job -Any | Out-Null }
    }

    while(Get-Job){
            $complete = Get-Job | Wait-Job -Any
            foreach($job in $complete){
                $page = $pages | Where-Object Number -eq $job.name
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
                    if( (Get-Job -State Running | Measure-Object).Count -ge $MaxJobs ){ Get-Job -State Running | Wait-Job -Any | Out-Null }
                    Start-Job -Name $page.Number -ScriptBlock { Invoke-RestMethod -Uri $args[0] -Method Get -Headers $args[1] -ContentType "application/json" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue } -argumentlist $page.Uri,$headers | Out-Null
                }
            }      
        }    
    }
    return $pages
}

Write-Host "Saving List Of GitLab Users to C:\Temp\GitLabUsers.csv" -ForegroundColor Green
(Get-GitLabUsers).Data | Sort-Object -Property 'namespace_id' | Export-Csv -Path C:\Temp\GitLabUsers.csv -NoTypeInformation