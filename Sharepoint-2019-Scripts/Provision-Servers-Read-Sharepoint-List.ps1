<#
.SYNOPSIS
    Automation Of Server Provisioning On Nutanix AHV Cluster From A Sharepoint 2019 List 

.DESCRIPTION
    Pulls the list of server provisioning requests from an on-premise Sharepoint 2019 instance & 
    builds VM's from template on Nutanix AHV Cluster.
  
.EXAMPLE
    PS> .\Sharepoint-List-Nutanix-Server-Provisioning.ps1

.NOTES
    Filename: Sharepoint-List-Nutanix-Server-Provisioning.ps1
    Author: Thomas Butterfield
    Modified date: 2022-08-08
    Version 1.0
#>

# Sharepoint PSSnapin
if ($null -eq (Get-PSSnapin | Where-Object { $_.Name -eq "Microsoft.SharePoint.PowerShell" })) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell;
}

# Nutanix PowerShell SnapIns
Add-PSSnapin NutanixCmdletsPSSnapin

# Nutanix Prism Element Credentials
[string]$userName = "username"
[string]$userPassword = "password"
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force

# Nutanix Prism Element Cluster IP
$server = '10.1.1.1'

# Create Connection to Cluster
write-host "Connecting to Cluster..."
Connect-NTNXCluster -Server $server -UserName $username -Password $secStringPassword -AcceptInvalidSSLCerts -ForcedConnection

# Get list of all Virtual Machines on Nutanix Cluster
$allvms = @()
$allVms += Get-NTNXVM

# Definie Sharepoint List Location & Objects To Read From Sharepoint List
$sourceWebURL = "https://intranet.contoso.com/department/site"
$sourceListName = "SharePoint List Name"
$spSourceWeb = Get-SPWeb $sourceWebURL
$spSourceList = $spSourceWeb.Lists[$sourceListName]
$spSourceItems = $spSourceList.GetItems()
$spSourceItems = $spSourceList.Items | Where-Object { $_.Xml -match "Server Provisioning Request" }
$requests = @()

# Added Delay To Allow Sharepoint List Objects To load Correctly
Start-Sleep -Seconds 5

If ($spSourceItems.count -ge 1) {
    
    Foreach ($serverRequest in $spSourceItems) {

        $id = $null
        $tasks = $null
        $serverName = $null
        $serverType = $null
        $instance = $null
        $os = $null
        $domain = $null
        $cores = $null
        $memory = $null
        $network = $null
        $disk1 = $null
        $disk2 = $null
        $disk3 = $null

        $id = $serverRequest.ID
        $tasks = $spSourceList.GetItemById($id)
        $serverName = $tasks["Title"].tostring()
        $serverType = $tasks["Server Type"].tostring()
        $instance = $tasks["Instance"].tostring()
        $os = $tasks["OS"].tostring()
        $domain = $tasks["Domain Join"].tostring()
        $cores = $tasks["Cores"].tostring()
        $memory = $tasks["Memory"].tostring()
        $networks = ($tasks["Network"].tostring() -replace '#', '').split(';') -notlike $null
        $disk1 = $tasks["HardDisk1"].tostring() 
        $disk2 = $tasks["HardDisk2"].tostring()
        $disk3 = $tasks["HardDisk3"].tostring()

        $request = New-Object PSObject -Property @{ID = $id; ServerName = $serverName; ServerType = $serverType; Instance = $instance; OS = $os; Domain = $domain; Cores = $cores; Memory = $memory; Network = $networks; Disk1 = $disk1; Disk2 = $disk2; Disk3 = $disk3; }
        $requests += $request   
    }
}

If ($null -ne $allvms) {
    Foreach ($virtualMachine in $requests) {

        ### Variables
        $vminfo = $null
        $name = $virtualMachine.ServerName.ToUpper().replace(' ', '')
        $domain = $virtualMachine.Domain
        $vmOS = $virtualMachine.OS
        $containerLocation = "Dedup_Compression"
        $vmMemory = [INT]$virtualMachine.Memory.Replace('GB', '') * 1024
        $vDisk2 = $null
        $vDisk3 = $null
        If ($virtualMachine.Disk2 -notlike "*N/A*") { $vDisk2 = [INT]$virtualMachine.Disk2.Replace('GB', '') * 1024 }
        If ($virtualMachine.Disk3 -notlike "*N/A*") { $vDisk3 = [INT]$virtualMachine.Disk3.Replace('GB', '') * 1024 }
        $disks = @($vdisk2, $vDisk3) -notlike $null
        $vCPU = "1"
        $vCPUCores = $virtualMachine.Cores
        Foreach ($network in $networks) {}

        ### Check if VM already exists
        $vminfo = Get-NTNXVM | Where-Object { $_.vmName -eq $Name }
        if ($allVms.vmName -contains $vminfo.vmName) { Write-Host "$name is already provisioned, please check Prism" }
        if ($allVms.vmName -notcontains $vminfo.vmName) {
   
            Write-Host "Creating VM $name"

            If ($vmOS -match "Windows*") {
                ### Create VM
                If ($vmOS -eq "Windows 2019") {
                    $masterImage = Get-NTNXVM | Where-Object { $_.vmname -eq "SERVER-2019-TEMPLATE" }
                    $AnswerFile = "C:\nutanix-answer-files\server2019\2019-answerfile.xml"
                }
                Elseif ($vmOS -eq "Windows 2016") {
                    $masterImage = Get-NTNXVM | Where-Object { $_.vmname -eq "SERVER-2016-TEMPLATE" }
                    $AnswerFile = "C:\nutanix-answer-files\server2016\2016-answerfile.xml"
                }

                Elseif ($vmOS -eq "Windows 10") {
                    $masterImage = Get-NTNXVM | Where-Object { $_.vmname -eq "WINDOWS-10-TEMPLATE" }
                    $AnswerFile = "C:\nutanix-answer-files\windows10\autounattend.xml"
                }

                $answer = [xml] (get-content $AnswerFile)

                If ($domain -eq "CONTOSO.COM") {
                    $component = $answer.GetElementsByTagName("component") | Where-Object { $_.name -eq "Microsoft-Windows-Shell-Setup" -and $_.ComputerName }
                    $component.GetElementsByTagName("ComputerName").item(0).Innertext = "$name"
                    $component = $answer.GetElementsByTagName("component") | Where-Object name -eq "Microsoft-Windows-UnattendedJoin"
                    $component.GetElementsByTagName("JoinDomain").item(0).Innertext = "contoso.com"
                    $component.GetElementsByTagName("Domain").item(0).Innertext = "contoso.com"
                    $component.GetElementsByTagName("MachineObjectOU").item(0).Innertext = "OU=Workstations,DC=CONTOSO,DC=COM"
                    $component.GetElementsByTagName("Username").item(0).Innertext = "domainJoinUserName"
                    $component.GetElementsByTagName("Password").item(0).Innertext = "domainJoinPassword"
            
                }

                If ($domain -eq "FABRIKAM.COM") {
                    $component = $answer.GetElementsByTagName("component") | Where-Object { $_.name -eq "Microsoft-Windows-Shell-Setup" -and $_.ComputerName }
                    $component.GetElementsByTagName("ComputerName").item(0).Innertext = "$name"
                    $component = $answer.GetElementsByTagName("component") | Where-Object name -eq "Microsoft-Windows-UnattendedJoin"
                    $component.GetElementsByTagName("JoinDomain").item(0).Innertext = "fabrikam.com"
                    $component.GetElementsByTagName("Domain").item(0).Innertext = "fabrikam.com"
                    $component.GetElementsByTagName("MachineObjectOU").item(0).Innertext = "OU=Workstations,DC=FABRIKAM,DC=COM"
                    $component.GetElementsByTagName("Username").item(0).Innertext = "domainJoinUserName"
                    $component.GetElementsByTagName("Password").item(0).Innertext = "domainJoinPassword"
                }

                $file = $AnswerFile
                $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
                $sw = New-Object System.IO.StreamWriter($file, $false, $utf8WithoutBom)
                $answer.Save($sw)
                $sw.Close()

                $sysprepdata = get-content $AnswerFile

                $vmId = ($masterImage.vmid.split(":"))[2]
                $templateVM = Get-NTNXVM -VmId $vmID
                $custom = New-NTNXObject -Name VMCloneDTO
                $VMCustomizationConfigDTO = New-NTNXObject -Name VMCustomizationConfigDTO
                $VMCustomizationConfigDTO.freshInstall = $false
                $VMCustomizationConfigDTO.userdata = $sysprepdata
                $custom.vmCustomizationConfig = $VMCustomizationConfigDTO
                $spec = New-NTNXObject -Name VMCloneSpecDTO
                $spec.name = $name
                Clone-NTNXVirtualMachine -Vmid $templateVM.vmId -VmCustomizationConfig $custom.vmCustomizationConfig -SpecList $spec
                Start-Sleep -Seconds 45

                ### Virtual Machine Network
                $vminfo = Get-NTNXVM | Where-Object { $_.vmName -eq $Name }
                $vmId = ($vminfo.vmid.split(":"))[2]
                $allVMs += $vminfo

                Set-NTNXVirtualMachine -Vmid $vmId -NumVcpus $vCPU -NumCoresPerVcpu $vCPUCores -MemoryMb $vmMemory -Description ""

                # Connect All Selected Network Adapters In Request
                Foreach ($network in $networks) {
    
                    If ($network -eq "DMZ") { $vmVlan = "16" }
                    If ($network -eq "LAN") { $vmVlan = "101" }
    
                    $networkUID = Get-NTNXNetwork | Where-object { $_.vlanId -eq "$vmVlan" }
                    $uuid = $networkUID.uuid
                    $nic = New-NTNXObject -Name VMNicSpecDTO
                    $nic.networkUuid = $uuid
                    Add-NTNXVMNic -Vmid $vmId -SpecList $nic
                }
        
                ### Storage
                Foreach ($disk in $disks) {

                    If ($disk -ge '1') {
                        ### Storage
                        $container = Get-NTNXContainer | Where-Object { $_.name -eq $containerLocation }
                        $containerID = $container.id.Split('::')[$container.id.Split('::').count - 1]

                        $diskCreateSpec = New-NTNXObject -Name VmDiskSpecCreateDTO
                        $diskcreatespec.containerid = $containerID
                        $diskCreateSpec.sizeMB = "$disk"
                        # Creating the Disk
                        $vmDisk = New-NTNXObject –Name VMDiskDTO
                        $vmDisk.vmDiskCreate = $diskCreateSpec
                        # Adding the Disk to the VM
                        Add-NTNXVMDisk -Vmid $vmId -Disks $vmDisk
                    }
                }
                Start-Sleep -Seconds 20
                $VM2PowerOn = Get-NTNXVM | Where-Object { $_.vmname -eq $name }
                Set-NTNXVMPowerOn -Vmid $VM2PowerOn.vmId     
            }
            
            If ($vmOS -match "RHEL*") { Write-Host "$name is a Linux VM, please manually provision this server on Nutanix" }
        }
    }
}