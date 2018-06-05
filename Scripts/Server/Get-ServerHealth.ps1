<#
.SYNOPSIS
Gets the health of one or more servers.
.DESCRIPTION
Gets the health of one or more servers. Currently checks for the ability to use remote management protocols, checks freedisk space, checks CPU utilization, checks RAM utilization, Checks last boot time, and checks services that are not started but are set to start automatically.
.PARAMETER Computername
Specify one or more computers to get health for.
.PARAMETER MaxThreads
Specify the amount of threads to use or how many jobs can run at once 
.PARAMETER ProgressAction
Specify the behavior of the progress bar.

    Continue:  Display the progress bar.
    SilentlyContinue:  Do not display the progress bar.
.EXAMPLE
Get-ServerHealth

Gets the health of the server that you are logged into.
.EXAMPLE
Get-ServerHealth -computername '[Computer1]','[Computer2]'

Gets the health of [Computer1] and '[Computer2].
.EXAMPLE
Get-ServerHealth -Computername (Get-WSAADComputer -Domain [domain])

Gets the health of all servers in [domain].
.INPUTS
System.String[]
.OUTPUTS
PSCustomObject
#>
Function Get-ServerHealth {
    [CmdletBinding()]

    Param (
        [Parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String[]]$Computername = [System.Net.DNS]::GetHostEntry('').HostName,

        [Int]$MaxThreads = 64,

        [ValidateSet('Continue','SilentlyContinue')]
        [String]$ProgressAction = 'Continue'
    )

    Begin {
        $Command = {
            Param (
                $Computer,
                $Credential,
                $ServiceExceptionList
            )

            $CIMParameters = @{
                SessionOption = New-CimSessionOption -Protocol Dcom
                ComputerName = $Computer
            }

            If ($Credential) {
                $CIMParameters.Add('Credential',$Credential)
            }


            $Ping = Test-Connection -ComputerName $Computer -Count 1 -Quiet

            Try {
                Get-WmiObject -Class Win32_OperatingSystem -ComputerName $Computer -ErrorAction Stop | Out-Null
                $CIMSession = New-CimSession @CIMParameters
                $WMI = $True
            }
            Catch {
                $WMI = $False
            }


            Try {
                $WinRM = Invoke-Command -ComputerName $Computer -ScriptBlock {$True} -ErrorAction Stop
            } Catch {
                $WinRM = $False
            }

            If (Test-Path -Path "\\$Computer\C$\") {
                $SMB = $True
            }
            Else {
                $SMB = $False
            }

            If ($WMI) {
                $DiskSpace = [Math]::Round(((Get-CimInstance Win32_volume -CimSession $CimSession -Filter 'DriveLetter = "C:"' | Select -ExpandProperty FreeSpace) / 1GB),2)
            }
            Else {
                $DiskSpace = $null
            }

            If ($WMI) {
                $MemoryUtilization = Get-CimInstance -CimSession $CIMSession -ClassName Cim_OperatingSystem | ForEach {“{0:N2}” -f ((($_.TotalVisibleMemorySize - $_.FreePhysicalMemory)*100)/ $_.TotalVisibleMemorySize)}
            }
            Else {
                $MemoryUtilization = $null
            }

            If ($WMI) {
                $CPUUtilization = [Math]::Round((Get-CimInstance -CimSession $CIMSession -ClassName Cim_Processor | Measure-Object -property LoadPercentage -Average | Select -ExpandProperty Average),2)
            }
            Else {
                $CPUUtilization = $null
            }
            
            If ($WMI) {
                $VerifiedServices = @()

                $Services = (Get-CimInstance Win32_Service -CimSession $CIMSession -Filter "StartMode = 'Auto'" | Where {$_.State -ne "Running"} | select -expand Name)
                ForEach ($Service in $Services) {
                    If ((Get-CimInstance -ClassName Cim_OperatingSystem -CimSession $CIMSession | Select -ExpandProperty Caption) -notlike '*2003*') {
                        If ((Invoke-CimMethod -ClassName stdregprov -CimSession $CIMSession -MethodName enumkey -Arguments @{hDefKey = [uint32]2147483650;sSubkeyName = "SYSTEM\CurrentControlSet\Services\$Service\TriggerInfo"}).ReturnValue -ne 0 -and $ServiceExceptionList -NotContains $Service) {
                            $VerifiedServices += $Service
                        }
                    }
                    Else {
                        $VerifiedServices += $Service
                    }
                }
                $ServicesNotStarted = $VerifiedServices -Join ', '
            }
            Else {
                $ServicesNotStarted = $null
            }

            If ($WMI) {
                $LastBootTime = (Get-CimInstance Cim_OperatingSystem -CimSession $CIMSession | Select -ExpandProperty LastBootupTime).ToString()
            }
            Else {
                $LastBootTime = $null
            }

            If ($WMI) {
                Remove-CimSession $CIMSession
            }

            If (($Ping -eq $True) -and ($WMI -eq $True) -and ($WinRM -eq $True) -and ($SMB -eq $True) -and ($DiskSpace -gt 2) -and ([string]::IsNullOrEmpty($ServicesNotStarted))) {
                $Status = 'Healthy'
            }
            Else {
                $Status = 'Unhealthy'
            }

            [PSCustomObject]@{
                ComputerName = $Computer
                Status = $Status
                Ping = $Ping
                WMI = $WMI
                WinRM = $WinRM
                SMB = $SMB
                FreeDiskSpace = $DiskSpace
                MemoryUtilization = $MemoryUtilization
                CPUUtilization = $CPUUtilization
                LastBootTime = $LastBootTime
                ServicesNotStarted = $ServicesNotStarted
            }
        }

        # This is where we specify the amount of threads to use. This is put into the parameter of the function so the user can set the thread count at runtime.
        $RunspacePool = [runspacefactory]::CreateRunspacePool(1,$MaxThreads)
        $RunspacePool.Open()

        # This array will hold all of our threads
        $Jobs = @()

        $Credential = $null
        $ServiceExceptionList = Get-Content "$(Split-Path $PSScriptRoot)\ServiceExceptionList.txt"

        $ProgressPreference = $ProgressAction
        
    }

    Process {
        If ($Computername.Count -ne 1) {
            ForEach ($Computer in $Computername) {
                # You will want to change the progress bar to reflect what your function is doing.
                Write-Progress -Activity 'Getting Server Health' -Status "Starting Threads ($($Jobs.Count)/$($Computername.Count))"


                While (($Jobs | Where {$_.Handle.IsCompleted -eq $false}).Count -ge $MaxThreads) {
                    Sleep -Milliseconds 250
                }

                # This is where you will create each thread. If you have additional arguments that you need passed into the thread, add additional ".AddArgument($ArgumentHere)" statements to the end of the line (no spaces)
                $PowershellThread = [Powershell]::Create().AddScript($Command).AddArgument($Computer).AddArgument($Credential).AddArgument($ServiceExceptionList)

                #This is where you assign your new thread to the runspace pool and execute it
                $PowershellThread.RunspacePool = $RunspacePool
                $Handle = $PowershellThread.BeginInvoke()

                # Now that your thread is running, this is storing information about it.
                $Jobs += [PSCustomObject]@{
                    Handle = $Handle
                    Thread = $PowershellThread
                    Computername = $Computer
                }
            }
        }
        Else {
            & $Command -Computer $Computername -Credential $Credential -ServiceExceptionList $ServiceExceptionList
        }
    }

    End {
        If ($Computername.Count -ne 1) {
            # This while statement will keep running until all of your job results are returned
            While (@($Jobs | Where {$_.Handle -ne $Null}).Count -gt 0) {
                # You will want to change the progress bar to reflect what your function is doing.
                Write-Progress -Activity 'Getting Server Health' -Status "Waiting for $(@($Jobs | Where {$_.Handle -ne $Null}).Count) threads to finish"
                ForEach ($Job in $($Jobs | Where-Object {$_.Handle.IsCompleted -eq $True})) {
                    # This statement actually is what stops your job AND returns the data of your job to the host
                    $Job.Thread.EndInvoke($Job.Handle)
                    $Job.Thread.Dispose()
                    $Job.Thread = $Null
                    $Job.Handle = $Null
                }
            }
        }


        # These 2 statements are necessary, because if you dont close your runspace pool when you are finished, Powershell will still run in the background within this runspace pool, even after you close powershell.
        $RunspacePool.Close()
        $RunspacePool.Dispose()
        Write-Progress -Activity 'Getting Server Health' -Completed
    }
}