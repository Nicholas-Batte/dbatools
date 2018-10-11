﻿function Install-DbaInstance {
    <#
    .SYNOPSIS

    This function will help you to quickly install a SQL Server instance. 

    .DESCRIPTION

    This function will help you to quickly install a SQL Server instance. 

    The number of TempDB files will be set to the number of cores with a maximum of eight.
    
    The perform volume maintenance right can be granted to the SQL Server account. If you happen to activate this in an environment where you are not allowed to do this,
    please revert that operation by removing the right from the local security policy (secpol.msc).

    Note that the dowloaded installation file must be unzipped, an ISO has to be mounted. This will not be executed from this script.

    .PARAMETER Version will hold the SQL Server version you wish to install. The variable will support autocomplete
    
    .PARAMETER Appvolume will hold the volume letter of the application disc. If left empty, it will default to C, unless there is a drive named like App

    .PARAMETER DataVolume will hold the volume letter of the Data disc. If left empty, it will default to C, unless there is a drive named like Data

    .PARAMETER LogVolume will hold the volume letter of the Log disc. If left empty, it will default to C, unless there is a drive named like Log

    .PARAMETER TempVolume will hold the volume letter of the Temp disc. If left empty, it will default to C, unless there is a drive named like Temp

    .PARAMETER BackupVolume will hold the volume letter of the Backup disc. If left empty, it will default to C, unless there is a drive named like Backup

    .PARAMETER PerformVolumeMaintenance will set the policy for grant or deny this right to the SQL Server service account.

    .PARAMETER SqlServiceAccount will hold the name of the SQL Server service account

    .Inputs
    None

    .Outputs
    None

    .Example
    C:\PS> Install-DbaInstance

    This will run the installation with the default settings

    .Example

    C:\PS> Install-DbaInstance -AppVolume "G"

    This will run the installation with default setting apart from the application volume, this will be redirected to the G drive.

    .Example 

    C:\PS> Install-DbaInstance -Version 2016 -AppVolume "D" -DataVolume "E" -LogVolume "L" -PerformVolumeMaintenance "Yes" -SqlServerAccount "MyDomain\SvcSqlServer"

    This will install SQL Server 2016 on the D drive, the data on E, the logs on L and the other files on the autodetected drives. The perform volume maintenance
    right is granted and the domain account SvcSqlServer will be used as the service account for SqlServer.


    #>
    Param  (
        [ValidateSet("2012", "2014", "2016","2017","2019")][int]$Version,    
        [string]$AppVolume, 
        [string]$DataVolume, 
        [string]$LogVolume, 
        [string]$TempVolume, 
        [string]$BackupVolume,
        [ValidateSet("Yes", "No")][string]$PerformVolumeMaintenance,
        [string]$SqlServerAccount
    )

    $configini = Get-Content "$script:PSModuleRoot\bin\installtemplate\$version.ini"
    

    # Check if there are designated drives for Data, Log, TempDB, Back-up and Application.
    If ($DataVolume -eq $null -or $DataVolume -eq '') {
        $DataVolume = Get-Volume | 
            Where-Object {$_.DriveType -EQ 'Fixed' -and $null -ne $_.DriveLetter -and $_.FileSystemLabel -like '*Data*'} | 
            Select-Object -ExpandProperty DriveLetter
    }
    if ($LogVolume -eq $null -or $LogVolume -eq '') {
        $LogVolume = Get-Volume | 
            Where-Object {$_.DriveType -EQ 'Fixed' -and $null -ne $_.DriveLetter -and $_.FileSystemLabel -like '*Log*'} |  
            Select-Object -ExpandProperty DriveLetter
    }
    if ($TempVolume -eq $null -or $TempVolume -eq '') {
        $TempVolume = Get-Volume | 
            Where-Object {$_.DriveType -EQ 'Fixed' -and $null -ne $_.DriveLetter -and $_.FileSystemLabel -like '*TempDB*'} |  
            Select-Object -ExpandProperty DriveLetter
    }
    if ($AppVolume -eq $null -or $AppVolume -eq '') {
        $AppVolume = Get-Volume | 
            Where-Object {$_.DriveType -EQ 'Fixed' -and $null -ne $_.DriveLetter -and $_.FileSystemLabel -like '*App*'} |  
            Select-Object -ExpandProperty DriveLetter
    }
    if ($BackupVolume -eq $null -or $BackupVolume -eq '') {
        $BackupVolume = Get-Volume | 
            Where-Object {$_.DriveType -EQ 'Fixed' -and $null -ne $_.DriveLetter -and $_.FileSystemLabel -like '*Backup*'} |  
            Select-Object -ExpandProperty DriveLetter
    }
    #Check the number of cores available on the server. Summed because every processor can contain multiple cores
    $NumberOfCores = Get-WmiObject -Class Win32_processor |  
        Measure-Object NumberOfLogicalProcessors -Sum | 
        Select-Object -ExpandProperty sum

    IF ($NumberOfCores -gt 8)
    { $NumberOfCores = 8 }

    #Get the amount of available memory. If it's more than 40 GB, give the server 10% of the memory, else reserve 4 GB.

    $ServerMemory = Get-WmiObject -Class win32_physicalmemory | 
        Measure-Object Capacity -sum | 
        Select-Object -ExpandProperty sum
    $ServerMemoryMB = ($ServerMemory / 1024) / 1024

    If ($ServerMemoryMB -gt 40960) {
        $ServerWinMemory = $ServerMemoryMB * 0.1
        $ServerMemoryMB = $ServerMemoryMB - $ServerWinMemory
    }
    else {
        $ServerMemoryMB = $ServerMemoryMB - 4096
    }

    IF ($null -eq $DataVolume -or $DataVolume -eq '') {
        $DataVolume = 'C'
    }

    IF ($null -eq $LogVolume -or $LogVolume -eq '') {
        $LogVolume = $DataVolume
    }

    IF ( $null -eq $TempVolume -or $TempVolume -eq '') {
        $TempVolume = $DataVolume
    }

    IF ( $null -eq $AppVolume -or $AppVolume -eq '') {
        $AppVolume = 'C'
    }

    IF ( $null -eq $BackupVolume -or $BackupVolume -eq '') {
        $BackupVolume = $DataVolume
    }


    Write-Message -Level Verbose -Message 'Your datadrive:' $DataVolume
    Write-Message -Level Verbose -Message 'Your logdrive:' $LogVolume
    Write-Message -Level Verbose -Message 'Your TempDB drive:' $TempVolume
    Write-Message -Level Verbose -Message 'Your applicationdrive:' $AppVolume
    Write-Message -Level Verbose -Message 'Your Backup Drive:' $BackupVolume
    Write-Message -Level Verbose -Message 'Number of cores for your Database:' $NumberOfCores

    Write-Message -Level Verbose -Message  'Do you agree on the drives?'
    $AlterDir = Read-Host " ( Y / N )"

    $CheckLastTwoChar = ":\"
    $CheckLastChar = "\"

    Switch ($AlterDir) {
        Y {Write-Message -Level Verbose -Message "Yes, drives agreed, continuing"; }
        N {
            Write-Message -Level Verbose -Message "Datadrive: " $DataVolume
            $NewDataVolume = Read-Host "Your datavolume: "
            If ($NewDataVolume.Substring($NewDataVolume.Length - 2 -eq $CheckLastTwoChar) -and $NewDataVolume.Length -gt 2) {
                $NewDataVolume = $NewDataVolume.Substring(0, $NewDataVolume.Length - 2)
                $DataVolume = $NewDataVolume
                Write-Message -Level Verbose -Message "DataVolume moved to " $DataVolume
            }
            elseif ($NewDataVolume.Substring($NewDataVolume.Length - 1 -eq $CheckLastChar) -and $NewDataVolume.Length -gt 1) {
                $NewDataVolume = $NewDataVolume.Substring(0, $NewDataVolume.Length - 1)
                $DataVolume = $NewDataVolume
                Write-Message -Level Verbose -Message "DataVolume moved to " $DataVolume
            }
            else {
                $DataVolume = $NewDataVolume
                Write-Message -Level Verbose -Message "DataVolume moved to " $DataVolume
            }
            If ([string]::IsNullOrEmpty($NewDataVolume)) {
                Write-Message -Level Verbose -Message "Datavolume remains on " $DataVolume
            }
            Write-Message -Level Verbose -Message "logvolume: " $LogVolume
            $NewLogVolume = Read-Host "Your logvolume: "
            If ($NewLogVolume.Substring($NewLogVolume.Length - 2 -eq $CheckLastTwoChar) -and $NewLogVolume.Length -gt 2) {
                $NewLogVolume = $NewLogVolume.Substring(0, $NewLogVolume.Length - 2)
                $LogVolume = $NewLogVolume
                Write-Message -Level Verbose -Message "LogVolume moved to " $LogVolume
            }
            elseif ($NewLogVolume.Substring($NewLogVolume.Length - 1 -eq $CheckLastChar) -and $NewLogVolume.Length -gt 1) {
                $NewLogVolume = $NewLogVolume.Substring(0, $NewLogVolume.Length - 1)
                $LogVolume = $NewLogVolume
                Write-Message -Level Verbose -Message "LogVolume moved to " $LogVolume
            }
            else {
                $LogVolume = $NewLogVolume
                Write-Message -Level Verbose -Message "LogVolume moved to " $LogVolume
            }
            If ([string]::IsNullOrEmpty($NewLogVolume)) {
                Write-Message -Level Verbose -Message "Logvolume remains on " $LogVolume
            }

            Write-Message -Level Verbose -Message "TempVolume: " $TempVolume
            $NewTempVolume = Read-Host "Your TempVolume: "
            If ($NewTempVolume.Substring($NewTempVolume.Length - 2 -eq $CheckLastTwoChar) -and $NewTempVolume.Length -gt 2) {
                $NewTempVolume = $NewTempVolume.Substring(0, $NewTempVolume.Length - 2)
                $TempVolume = $NewTempVolume
                Write-Message -Level Verbose -Message "TempVolume moved to " $TempVolume
            }
            elseif ($NewTempVolume.Substring($NewTempVolume.Length - 1 -eq $CheckLastChar) -and $NewTempVolume.Length -gt 1) {
                $NewTempVolume = $NewTempVolume.Substring(0, $NewTempVolume.Length - 1)
                $TempVolume = $NewTempVolume
                Write-Message -Level Verbose -Message "TempVolume moved to " $TempVolume
            }
            else {
                $TempVolume = $NewTempVolume
                Write-Message -Level Verbose -Message "TempVolume moved to " $TempVolume
            }
            If ([string]::IsNullOrEmpty($NewTempVolume)) {
                Write-Message -Level Verbose -Message "TempVolume remains on " $TempVolume
            }

            Write-Message -Level Verbose -Message "AppVolume: " $AppVolume
            $NewAppVolume = Read-Host "Your AppVolume: "
            If ($NewAppVolume.Substring($NewAppVolume.Length - 2 -eq $CheckLastTwoChar) -and $NewAppVolume.Length -gt 2) {
                $NewAppVolume = $NewAppVolume.Substring(0, $NewAppVolume.Length - 2)
                $AppVolume = $NewAppVolume
                Write-Message -Level Verbose -Message "AppVolume moved to " $AppVolume
            }
            elseif ($NewAppVolume.Substring($NewAppVolume.Length - 1 -eq $CheckLastChar) -and $NewAppVolume.Length -gt 1) {
                $NewAppVolume = $NewAppVolume.Substring(0, $NewAppVolume.Length - 1)
                $AppVolume = $NewAppVolume
                Write-Message -Level Verbose -Message "AppVolume moved to " $AppVolume
            }
            else {
                $AppVolume = $NewAppVolume
                Write-Message -Level Verbose -Message "AppVolume moved to " $AppVolume
            }
            If ([string]::IsNullOrEmpty($NewAppVolume)) {
                Write-Message -Level Verbose -Message "AppVolume remains on " $AppVolume
            }

            Write-Message -Level Verbose -Message "BackupVolume: " $BackupVolume
            $NewBackupVolume = Read-Host "Your BackupVolume: "
            If ($NewBackupVolume.Substring($NewBackupVolume.Length - 2 -eq $CheckLastTwoChar) -and $NewBackupVolume.Length -gt 2) {
                $NewBackupVolume = $NewBackupVolume.Substring(0, $NewBackupVolume.Length - 2)
                $BackupVolume = $NewBackupVolume
                Write-Message -Level Verbose -Message "BackupVolume moved to " $BackupVolume
            }
            elseif ($NewBackupVolume.Substring($NewBackupVolume.Length - 1 -eq $CheckLastChar) -and $NewBackupVolume.Length -gt -1) {
                $NewBackupVolume = $NewBackupVolume.Substring(0, $NewBackupVolume.Length - 1)
                $BackupVolume = $NewBackupVolume
                Write-Message -Level Verbose -Message "BackupVolume moved to " $BackupVolume
            }
            else {
                $BackupVolume = $NewBackupVolume
                Write-Message -Level Verbose -Message "BackupVolume moved to " $BackupVolume
            }
            If ([string]::IsNullOrEmpty($NewBackupVolume)) {
                Write-Message -Level Verbose -Message "BackupVolume remains on " $BackupVolume
            }
        }
        Default {Write-Message -Level Verbose -Message "Drives agreed, continuing"; }
    }

    $CheckLastTwoChar = ":\"
    $CheckLastChar = "\"

    $SetupFile = Read-Host -Prompt 'Please enter the root location for Setup.exe'
    IF ($SetupFile.Length -gt 1) {
        $C2 = $SetupFile.Substring($SetupFile.Length - 2)
        $C1 = $SetupFile.Substring($SetupFile.Length - 1)
        If ($C2 -eq $CheckLastTwoChar) {
            $debug = $SetupFile.Substring($SetupFile.Length - 2)
            Write-Message -Level Verbose -Message $debug '/' $CheckLastTwoChar
            $SetupFile = $SetupFile.Substring(0, $SetupFile.Length - 2)
            Write-Message -Level Verbose -Message $SetupFile
        }
        elseif ($C1 -eq $CheckLastChar) {
            $SetupFile = $SetupFile.Substring(0, $SetupFile.Length - 1)
            Write-Message -Level Verbose -Message $SetupFile
        }
    }
    IF ($SetupFile.Length -eq 1) {
        $SetupFile = $SetupFile + ':\SQLEXPR_x64_ENU\SETUP.EXE'
        Write-Message -Level Verbose -Message 'Setup will start from ' + $SetupFile
    } 
    else {
        $SetupFile = $SetupFile + '\SQLEXPR_x64_ENU\SETUP.EXE'
        Write-Message -Level Verbose -Message 'Setup will start from ' + $SetupFile
    }


    $ConfigFile = 'c:\temp\'

    if ( -Not (Test-Path -Path $ConfigFile ) ) {
        New-Item -ItemType directory -Path $ConfigFile
    }

    Out-File -FilePath C:\Temp\ConfigurationFile2.ini -InputObject $startScript

    $FileLocation2 = $ConfigFile + 'ConfigurationFile2.ini'

    (Get-Content -Path $FileLocation2).Replace('SQLBACKUPDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Backup"', 'SQLBACKUPDIR="' + $BackupVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Backup"') | Out-File $FileLocation2

    (Get-Content -Path $FileLocation2).Replace('SQLUSERDBDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"', 'SQLUSERDBDIR="' + $DataVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"') | Out-File $FileLocation2

    (Get-Content -Path $FileLocation2).Replace('SQLTEMPDBDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"', 'SQLTEMPDBDIR="' + $TempVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"') | Out-File $FileLocation2

    (Get-Content -Path $FileLocation2).Replace('SQLUSERDBLOGDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Log"', 'SQLUSERDBLOGDIR="' + $LogVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Log"') | Out-File $FileLocation2

    (Get-Content -Path $FileLocation2).Replace('SQLSYSADMINACCOUNTS="WIN-NAJQHOBU8QD\Administrator"', 'SQLSYSADMINACCOUNTS="' + $env:COMPUTERNAME + '\Administrator"')| Out-File $FileLocation2

    #$SetupFile = 'C:\Users\Administrator\Downloads\SQLEXPR_x64_ENU\Setup.exe'
    #$ConfigFile = 'C:\temp\ConfigurationFile2.ini'

    $SAPassW = '[InsertPasswordHere]'

    & $SetupFile /ConfigurationFile=$FileLocation2 /Q /IACCEPTSQLSERVERLICENSETERMS /SAPWD=$SAPassW

    # Grant service account the right to perform volume maintenance
    # code found at https://social.technet.microsoft.com/Forums/windows/en-US/5f293595-772e-4d0c-88af-f54e55814223/adding-domain-account-to-the-local-policy-user-rights-assignment-perform-volume-maintenance?forum=winserverpowershell

    if ($PerformVolumeMaintenance) {
        ## <--- Configure here
        $accountToAdd = 'NT Service\MSSQL$AXIANSDB01'
        ## ---> End of Config
        $sidstr = $null


        try {
            $ntprincipal = new-object System.Security.Principal.NTAccount "$accountToAdd"
            $sid = $ntprincipal.Translate([System.Security.Principal.SecurityIdentifier])
            $sidstr = $sid.Value.ToString()
        }
        catch {
            $sidstr = $null
        }
        Write-Message -Level Verbose -Message "Account: $($accountToAdd)" -ForegroundColor DarkCyan
        if ( [string]::IsNullOrEmpty($sidstr) ) {
            Write-Message -Level Verbose -Message "Account not found!" -ForegroundColor Red
            #exit -1
        }

        Write-Message -Level Verbose -Message "Account SID: $($sidstr)" -ForegroundColor DarkCyan
        $tmp = ""
        $tmp = [System.IO.Path]::GetTempFileName()
        Write-Message -Level Verbose -Message "Export current Local Security Policy" -ForegroundColor DarkCyan
        secedit.exe /export /cfg "$($tmp)" 
        $c = ""
        $c = Get-Content -Path $tmp
        $currentSetting = ""
        foreach ($s in $c) {
            if ( $s -like "SeManageVolumePrivilege*") {
                $x = $s.split("=", [System.StringSplitOptions]::RemoveEmptyEntries)
                $currentSetting = $x[1].Trim()
            }
        }


        if ( $currentSetting -notlike "*$($sidstr)*" ) {
            Write-Message -Level Verbose -Message "Modify Setting ""Perform Volume Maintenance Task""" -ForegroundColor DarkCyan
       
            if ( [string]::IsNullOrEmpty($currentSetting) ) {
                $currentSetting = "*$($sidstr)"
            }
            else {
                $currentSetting = "*$($sidstr),$($currentSetting)"
            }
       
            Write-Message -Level Verbose -Message "$currentSetting"
       
            $outfile = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeManageVolumePrivilege = $($currentSetting)
"@
       
            $tmp2 = ""
            $tmp2 = [System.IO.Path]::GetTempFileName()
       
       
            Write-Message -Level Verbose -Message "Import new settings to Local Security Policy" -ForegroundColor DarkCyan
            $outfile | Set-Content -Path $tmp2 -Encoding Unicode -Force
            #notepad.exe $tmp2
            Push-Location (Split-Path $tmp2)
       
            try {
                secedit.exe /configure /db "secedit.sdb" /cfg "$($tmp2)" /areas USER_RIGHTS 
                #Write-Message -Level Verbose -Message "secedit.exe /configure /db ""secedit.sdb"" /cfg ""$($tmp2)"" /areas USER_RIGHTS "
            }
            finally {  
                Pop-Location
            }
        }
        else {
            Write-Message -Level Verbose -Message "NO ACTIONS REQUIRED! Account already in ""Perform Volume Maintenance Task""" -ForegroundColor DarkCyan
        }
        Write-Message -Level Verbose -Message "Done." -ForegroundColor DarkCyan 
    }

    

    #Now configure the right amount of TempDB files.

    $val = 1

    WHILE ($val -ne $NumberOfCores) {
        $sqlM = 'ALTER DATABASE tempdb ADD FILE ( NAME = N''tempdev' + $val + ''', FILENAME = N''' + $TempVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\DATA\tempdev' + $val + '.ndf'' , SIZE = 64MB , FILEGROWTH = 64MB)'
        Invoke-Sqlcmd -Database master -Query $sqlM

        $val++
    }

    #And make sure the standard one has the same configuration as the new ones to make sure the parallelism works
    $sql = @'
ALTER DATABASE TempDB   
MODIFY FILE  
(NAME = tempdev,  
SIZE = 64MB, FILEGROWTH = 64MB);  
GO  
'@

    Invoke-Sqlcmd -Database TempDB -Query $sql

    #Turn off SA, primary break-in point of the naughty users

    $sql = 'ALTER LOGIN sa DISABLE'

    Invoke-Sqlcmd -Database master -Query $sql
}