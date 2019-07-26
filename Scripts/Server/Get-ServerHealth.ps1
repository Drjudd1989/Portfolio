Function Get-ServerHealth{
    <#
        .SYNOPSIS
        Gets the Health of a specified server(s).
        .DESCRIPTION
        Gets the Health of a specified server(s). This is a multithreaded command.
        .PARAMETER  Computername
        Specify one or more computers  By default, will run as the local computer.
        .PARAMETER  MaxThreads
        Specify how many threads to run at once. Threads are set for each computer. Default value is 64 threads.
        .PARAMETER Credential
        Specify credentials to run the Cmdlet as. 
        .EXAMPLE
        Get-ServerHealth -computername Comp1,Comp2,Comp3 -credential (Get-Credential)
        Runs the Cmdlet as the specified credentials and returns the health for Comp1, Comp2, and Comp3.
        .INPUTS
        System.String
        .OUTPUTS
        System.String
        .LINK
    #>
    
    Param(
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [string[]]$Computername = [System.Net.DNS]::GetHostEntry('').HostName,
        [int]$MaxThreads = 64,
        $Credential
    )

    Begin{
        $ServiceExceptionList = @('RemoteRegistry','ShellHWDetection','sppsvc')
        $Command = {
            Param(
                $Computer,
                $Credential,
                $ServiceExceptionList
            )
            
            #Nulling out variables to prevent cross-runspace contamination
            $Services = $Null
            $SMB = $Null
            $Ping = $Null
            $State = $Null
            $Connected = $Null
            $OSClass = $Null
            $OS = $Null
            $LastBootTime = $Null

            #Pinging server and outputting a true or false response
            $Ping = Test-Connection -ComputerName $Computer -Count 1 -Quiet

            #CIMSession creation and WMI Connectivity Test
            #Defining Parameters for CIMSession
            $CimParameters = @{
                Computername = $Computer
                erroraction = "stop"
                OperationTimeOut = 60
            }
            #Adding in Credentials if specified as parameter
            If ($Credential) {
                $CIMParameters.Add('Credential',$Credential)
            }
            #Attempting CIMSession over DCOM and gathering OS Information (Helps to determine potnetial issues with the ciminstance call)
            try{
                $CimSession = New-CimSession @CimParameters
                $OSClass = Get-CIMInstance -cimsession $CimSession -Class win32_operatingsystem -ErrorAction stop -OperationTimeoutSec 20
                $WSMAN = "True"
            }
            Catch{
                #If DCOM fails, attempting WSMAN Protocol, also gathering OS Information. (Helps to determine potnetial issues with the ciminstance call)
                try{
                    $WSMAN = "False"
                    $CimSession = New-CimSession @CimParameters  -SessionOption (New-CimSessionOption -Protocol Dcom)
                    $OSClass = Get-CIMInstance -cimsession $CimSession -Class win32_operatingsystem -ErrorAction stop -OperationTimeoutSec 20
                    $DCOM = "True"
                }
                Catch{
                    $DCOM = "False"
                } 
            } #End CIMSession creation and WMI Connectivity Test

            #Testing SMB
            $TestPath = "\\$Computer\c$\"
            if($Credential){
                $PSDriveName = ($Computer -split "\.")[0]
                $PSDriveParameters = @{
                    PSProvider = "Filesystem"
                    Name = $PSDriveName
                    Root = "\\$Computer\C$"
                    ErrorAction = "SilentlyContinue"
                    Credential = $Credential
                }
                New-PSDrive @PSDriveParameters | out-null
                $TestPath = $PSDriveName + ":\"
            }

            if(Test-Path $TestPath){
                $SMB = "True"
            }
            Else{
                $SMB = "False"
            }
            if($Credential){Remove-PSDrive -Name $PSDriveName}

            If($DCOM -eq "True" -or $WSMAN -eq "True"){
                $Connected = "True"
                #OS
                #$OSClass = Get-CimInstance -CimSession $CimSession -ClassName cim_operatingsystem
                $OS = $OSClass.Caption
                $LastBootTime = $OSClass.LastBootUpTime
                #Domain
                $Domain = Get-CimInstance -CimSession $CimSession -ClassName cim_computersystem -OperationTimeoutSec 30 | select -ExpandProperty Domain

                #HDD Free Space and Total
                $HDSpace = Get-CimInstance -CimSession $CimSession -ClassName cim_logicaldisk | select * | Where-Object {$_.deviceID -eq 'C:'} | select size,freespace
                $FreeSpace = [math]::Round($($HDSpace.freespace / 1GB))
                $TotalSpace = [math]::Round($($HDSpace.size / 1GB))

                #RAM Utilization
                $MemoryUtilization = $OSClass | ForEach {“{0:N2}” -f ((($_.TotalVisibleMemorySize - $_.FreePhysicalMemory)*100)/ $_.TotalVisibleMemorySize)}

                #CPU Utilization
                $CPUUtilization = [Math]::Round((Get-CimInstance -CimSession $CIMSession -ClassName Cim_Processor | Measure-Object -property LoadPercentage -Average | Select -ExpandProperty Average),2)

                #$LastPatchTime = Get-CimInstance -class win32_quickfixengineering -CimSession $CimSession -OperationTimeoutSec 60 | Sort-Object installedon | select -Last 1
                #Gathering Services set to automatic and no started, filtering out exceptions
                try{
                    $Services = Get-CimInstance -CimSession $CimSession -ClassName cim_service -ErrorAction stop -OperationTimeoutSec 200 | Where-Object {$_.Startmode -eq "Auto" -and $_.State -ne "Running" -and $_.Name -notin $ServiceExceptionList} | select -ExpandProperty Name
                    $Services = $Services -join ", "
                }
                Catch{
                    $Services = "Error: Could Not Gather Services"
                }
                #Removing Cimsession
                Remove-CimSession -CimSession $CimSession
            }#End If($DCOM -eq "True" -or $WSMAN -eq "True")
            #Nulling out variables to eliminate cross-runspace contamination if WMI/DCOM fail.
            Else{
 
                $Domain = $Null
                $OS = $Null
                $LastBootTime = $Null
                $Freespace = $Null
                $TotalSpace = $Null
                $MemoryUtilization = $Null
                $CPUUtilization = $Null
            }
            if($WSMAN -eq "True"){
                $Protocol = "WSMAN"
            }
            Elseif($WSMAN -eq "False" -and $DCOM -eq "True"){
                $Protocol = "DCOM"
            }
            Else{
                $Protocol = "Failed"
            }
            #Determining if server is healthy or not
            If($Ping -eq "True" -and $SMB -eq "True" -and $Connected -eq "True" -and $Freespace -gt 4){
            $State = "Healthy"
            }

            Else{
            $State = "Unhealthy"
            }

            [pscustomobject]@{
                Computername = $Computer
                Domain = $Domain
                State = $State
                Ping = $Ping
                Protocol = $Protocol
                SMB = $SMB
                OSFreeSpace = $Freespace
                OSTotalSpace = $Totalspace
                MemoryUtilization = $MemoryUtilization
                CPUUtilization = $CPUUtilization
                OperatingSystem = $OS
                LastBootTime = $LastBootTime
                #LastPatchTime = $(get-date ($LastPatchTime.installedon) -Format MM/dd/yyyy)
                ServicesNotStarted = $Services
            }       

        }
        
        #Specification for the amount of threads to use put in as a parameter by the user to set the thread count at runtime.
        $RunspacePool = [runspacefactory]::CreateRunspacePool(1,$MaxThreads)
        $RunspacePool.open()

        #Array to hold all of the threads
        $Jobs = @()

    }

    Process{
        ForEach($Computer in $Computername){
            #Progress bar for the creation of the threads. This can be modified to reflect what the function is doing.
            Write-Progress -Activity "Checking Servers" -Status "Gathering Servers ($($Jobs.count)/$($Computername.count))"

            #This is the actual creation of each thread. Additional arguments should be added to this line if any more are needed by adding ".AddArgument($Argument)" statements to the end of the line with no spaces.
            $PowershellThread = [powershell]::Create().AddScript($Command).AddArgument($Computer).AddArgument($Credential).AddArgument($ServiceExceptionList)

            #This is where the new thread is assigned to the runspace pool and executed.
            $PowershellThread.RunspacePool = $RunspacePool
            $Handle = $PowershellThread.BeginInvoke()

            #Storing information about the thread
            $Jobs += [PSCustomObject]@{
                Handle = $Handle
                Thread = $PowershellThread
                Computername = $Computer
            }
        }
    }

    End{
        #While statement will keep running until all of the job results are returned
            #Progress Bar detailing remaining jobs. This can be modified to reflect what the function is doing
            while(@($Jobs | Where {$_.Handle -ne $Null}).Count -gt 7){
                Write-Progress -Activity "Checking Servers" -Status "Waiting for $(@($Jobs | Where {$_.Handle -ne $Null}).Count) servers to finish health check"
                ForEach ($Job in $($Jobs | Where-Object {$_.Handle.IsCompleted -eq $True})){
                    $Job.Thread.EndInvoke($Job.Handle)
                    $Job.Thread.Dispose()
                    $Job.Thread = $null
                    $Job.Handle = $null
                }
            }

            While (@($Jobs | Where {$_.Handle -ne $Null}).Count -gt 0){
                $Remaining = ($Jobs | Where {$_.Handle -ne $Null}).computername
                $Remaining = $Remaining -join ", "
                Write-Progress -Activity "Checking Servers" -Status "Waiting for $Remaining to finish health check"

                ForEach ($Job in $($Jobs | Where-Object {$_.Handle.IsCompleted -eq $True})){
                    $Job.Thread.EndInvoke($Job.Handle)
                    $Job.Thread.Dispose()
                    $Job.Thread = $null
                    $Job.Handle = $null
            }
        }

        #Closing Progress Bar
        net use * /delete /y | out-null
        Write-Progress -Activity "Checking Servers" -Completed

        #Necessary statements to ensure the runspace pool is no longer running in the background in Powershell.
        $RunspacePool.Close()
        $RunspacePool.Dispose()
    }
}