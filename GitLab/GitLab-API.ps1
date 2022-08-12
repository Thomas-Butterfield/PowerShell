glpat-8zvNRB1jMe6u5ot8C9Sd




# https://docs.gitlab.com/ee/api/projects.html
# https://docs.gitlab.com/ee/api/issues.html
# https://docs.gitlab.com/ee/api/notes.html

# Project List
$r = Invoke-RestMethod -Headers @{ 'PRIVATE-TOKEN'='glpat-8zvNRB1jMe6u5ot8C9Sd' } -Uri https://tusgitlabp01.tams.com/users 
$r | Sort-Object -Property id | Format-Table -Property id, name

# Issues List
$r = Invoke-RestMethod -Headers @{ 'PRIVATE-TOKEN'='xxxxx' } -Uri http://xxxxx/api/v4/projects/<xx>/issues
$r | Sort-Object -Property id | Format-Table -Property id, state, title

# New Issue
Invoke-RestMethod -Method Post -Headers @{ 'PRIVATE-TOKEN'='xxxxx' } -Uri 'http://xxxxx/api/v4/projects/<xx>/issues?title=<xxx>&labels=bug'