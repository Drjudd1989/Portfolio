Function Get-ServerInventory{
    <#
        .SYNOPSIS
        Gets the Inventory Information of a specified server(s).
        .DESCRIPTION
        Gets the Inventory Information of a specified server(s). This is a multithreaded command.
        .PARAMETER  Computername
        Specify one or more computers  By default, will run as the local computer.
        .PARAMETER  MaxThreads
        Specify how many threads to run at once. Threads are set for each computer. Default value is 64 threads.
        .PARAMETER Credential
        Specify credentials to run the Cmdlet as. 
        .EXAMPLE
        Get-ServerInventory -computername Comp1,Comp2,Comp3 -credential (Get-Credential)
        Runs the Cmdlet as the specified credentials and returns the inventory information for Comp1, Comp2, and Comp3.
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
        $Command = {
            Param(
                $Computer,
                $Credential
            )
            #Setting Message to Null
            $Message = $Null

            #Pinging server and outputting a true or false response
            $Ping = Test-Connection -ComputerName $Computer -Count 1 -Quiet

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
            #Attempting CIMSession over DCOM
            try{ 
                $CimSession = New-CimSession @CimParameters -SessionOption (New-CimSessionOption -Protocol Dcom)
                
            } 
            Catch{
                #If DCOM fails, attempting WSMAN Protocol
                try{
                    $CimSession = New-CimSession @CimParameters 
                }
                Catch{
                    #Outputting an error message and continuing on if neither protocol works.
                    $Message = "Cannot Connect over DCOM/WSMAN"

                    [pscustomobject]@{
                        ComputerName = $Computer
                        Domain = $Null
                        Ping = $Ping
                        CDriveSpace = $Null
                        TotalMemory = $null
                        CPUCount = $null
                        CoresPerCPU = $null
                        LogicalCPUs = $null
                        OperatingSystem = $null
                        Model = $null
                        PSVersion = $null
                        IP = $null
                        Message = $Message
                    }
                    Continue
                }  
            } #End CIMSession creation and WMI Connectivity Test

            If($Message -eq $Null){

                #OS
                $OSClass = Get-CimInstance -CimSession $CimSession -ClassName cim_operatingsystem -OperationTimeoutSec 30
                $OS = $OSClass.Caption

                #Domain, Model, and Processors
                $SystemInfo = Get-CimInstance -CimSession $CimSession -ClassName cim_computersystem -OperationTimeoutSec 30
                $Model = $Systeminfo.Model
                $LogicalProcs = $SYsteminfo.Numberoflogicalprocessors
                $CPUCount = $SystemInfo.NumberofProcessors
                

                #HDD Free Space and Total
                $HDSpace = Get-CimInstance -CimSession $CimSession -ClassName cim_logicaldisk -OperationTimeoutSec 30 | select * | Where-Object {$_.deviceID -eq 'C:'} | select size,freespace
                #$FreeSpace = [math]::Round($($HDSpace.freespace / 1GB))
                $TotalSpace = [math]::Round($($HDSpace.size / 1GB))

                #RAM Utilization
                $Memory = $OSClass | ForEach {“{0:N2}” -f ($_.TotalVisibleMemorySize / 1024)}

                #CPU Utilization
                $CPU = Get-CimInstance -CimSession $CimSession -ClassName Cim_Processor -OperationTimeoutSec 30 | select numberofcores,numberoflogicalprocessors
                if($CPUCount -eq "1"){
                    $CPUCoreCount = $CPU.numberofcores
                }
                Else{
                    #If more than 1 CPU, display the number of cores in the first processor
                    $CPUCoreCount = $CPU[0].numberofcores
                }

                #Powershell Version
                $HKLocalMachine = [Convert]::ToUInt32(80000002, 16)
                $EnumArgs = @{
                    hDefKey = $HKLocalMachine
                    sSubKeyName = 'SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine'
                    sValueName = 'PowerShellVersion'
                }

                $CIMMethodParams = @{
                    CIMSession = $CimSession
                    Namespace = 'root\cimv2'
                    ClassName = 'StdRegProv'
                    MethodName = 'GetSTRINGValue'
                    Arguments = $EnumArgs
                    OperationTimeOutSec = 15
                    ErrorAction = 'Stop'

                }
                $POSHVersion = $Result = Invoke-CimMethod @CIMMethodParams

                if (-not $PoshVersion.svalue){
                    $EnumArgs = @{
                        hDefKey = $HKLocalMachine
                        sSubKeyName = 'SOFTWARE\Microsoft\PowerShell\1\PowerShellEngine'
                        sValueName = 'PowerShellVersion'
                    }

                    $CIMMethodParams = @{
                        CIMSession = $CimSession
                        Namespace = 'root\cimv2'
                        ClassName = 'StdRegProv'
                        MethodName = 'GetSTRINGValue'
                        Arguments = $EnumArgs
                        OperationTimeOutSec = 15
                        ErrorAction = 'Stop'

                    }
                    $POSHVersion = $Result = Invoke-CimMethod @CIMMethodParams
                }


                <#Try{
                $POSHVersion = Invoke-Command -ComputerName $Computer -ScriptBlock {$PSVersionTable.PSVersion.Major} -Credential $Credential -SessionOption (New-PSSessionOption -OperationTimeout 30)
                }
                Catch{$POSHVersion = "TimedOut"}#>
                
                #Gather IP Addresses attached to any NIC that is not IPv6
                $IPInfo = Get-ciminstance -cimsession $CimSession -Class Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -OperationTimeoutSec 60 | select -ExpandProperty ipaddress | Where-Object {$_ -notlike "*:*"}
                if ($IPInfo.count -gt "1"){
                    $IP = $IPInfo -join ", "
                }
                Else{
                    $IP = $IPInfo        
                }
                #Removing CIMSession
                Remove-CimSession -CimSession $CimSession
            }
           #Outputting data
           $OutputObject = [pscustomobject]@{
                Computername = $Computer
                Domain = $SystemInfo.Domain
                Ping = $Ping
                CDriveSpace = $Totalspace
                TotalMemory = $Memory
                CPUCount = $CPUCount
                CoresPerCPU = $CPUCoreCount
                LogicalCPUs = $LogicalProcs
                OperatingSystem = $OS
                Model = $Model
                PSVersion = $POSHVersion.sValue
                IP = $IP
                Message = $Message
            }
            <#[int]$i = 1
            foreach($IP in ($IPInfo | Where-Object {$_.ipaddress -notlike "*:*"})){
                #$OutputObject | Add-Member -NotePropertyName "IPAlias$i" -NotePropertyValue $IP.InterfaceAlias
                $OutputObject | Add-Member -NotePropertyName "IPAddress$i" -NotePropertyValue $IP
                $i++
            }#>
            $OutputObject
            
            
             
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
            Write-Progress -Activity "Getting Server Inventory" -Status "Loading Computers ($($Jobs.count)/$($Computername.count))"

            #This is the actual creation of each thread. Additional arguments should be added to this line if any more are needed by adding ".AddArgument($Argument)" statements to the end of the line with no spaces.
            $PowershellThread = [powershell]::Create().AddScript($Command).AddArgument($Computer).AddArgument($Credential)

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
                    while(@($Jobs | Where {$_.Handle -ne $Null}).Count -gt 7){
                Write-Progress -Activity "Checking Servers" -Status "Waiting for $(@($Jobs | Where {$_.Handle -ne $Null}).Count) servers to finish"
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
                Write-Progress -Activity "Checking Servers" -Status "Waiting for $Remaining to finish"

                ForEach ($Job in $($Jobs | Where-Object {$_.Handle.IsCompleted -eq $True})){
                    $Job.Thread.EndInvoke($Job.Handle)
                    $Job.Thread.Dispose()
                    $Job.Thread = $null
                    $Job.Handle = $null
            }
        }

        #Closing Progress Bar
        Write-Progress -Activity "Getting Server Inventory" -Completed

        #Necessary statements to ensure the runspace pool is no longer running in the background in Powershell.
        $RunspacePool.Close()
        $RunspacePool.Dispose()
    }
}