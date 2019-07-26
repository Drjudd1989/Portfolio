Function Get-ServerActivity{
    <#
        .SYNOPSIS
        Gets activity information for a specified server(s).
        .DESCRIPTION
        Gets activity information for a specified server(s). Activity information such as the last time a user logged in and the state of non-system services and IIS application pools. This is a multithreaded command.
        .PARAMETER  Computername
        Specify one or more computers to get the activity information. By default, will run as the local computer.
        .PARAMETER  MaxThreads
        Specify how many threads to run at once. Threads are set for each computer. Default value is 10 threads.
        .PARAMETER Credential
        Specify credentials to run the Cmdlet as. 
        .EXAMPLE
        Get-ServerActivity -computername Comp1,Comp2,Comp3 -credential (Get-Credential)
        Runs the Cmdlet as the specified credentials and returns the activity for Comp1, Comp2, and Comp3.
        .INPUTS
        System.String
        .OUTPUTS
        System.String
        .LINK
    #>
    Param(
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [string[]]$Computername = [System.Net.DNS]::GetHostEntry('').HostName,
        [int]$MaxThreads = 10,
        $Credential
    )

    Begin{
        $Command = {
            Param(
                [string]$Computer,
                $Credential
            )
            #Most of the Command will go here  
            $WQLFilter="NOT SID = 'S-1-5-18' AND NOT SID = 'S-1-5-19' AND NOT SID = 'S-1-5-20'"
            $DOMNetBios = $null
            $Message = $Null
            $Info = $Null
            $OS = $Null
            $Servicesnotstarted = $Null
            $ServiceAccounts = $Null
            $ServiceNames = $null
            $IIS = $Null
            $IISAppPools = $Null
            $IISPools = $Null

            $CimParameters = @{
                Computername = $Computer
                ErrorAction = "Stop"
                OperationTimeOutSec = 60
            }

            If ($Credential) {
                $CIMParameters.Add('Credential',$Credential)
            }

            try{ 
                $CimSession = New-CimSession @CimParameters -SessionOption (New-CimSessionOption -Protocol Dcom)  
            } 
            Catch{
                try{
                        $CimSession = New-CimSession @CimParameters 
                    }
                    Catch{
                        $Message = "Cannot Connect over DCOM/WSMAN"
                        [pscustomobject]@{
                            ComputerName = $Computer
                            OperatingSystem = $OS
                            User = $($($Info.Localpath)-split '\\')[-1]
                            LastUseTime = $Time
                            ServicesNotStarted = $ServiceNames
                            ServiceAccounts = $ServiceAccounts
                            IIS = $IIS
                            ApplicationPools = $IISAppPools
                            Message = $Message
                        }
                        Continue
                    }                 
                
                } #End CIMSession creation and WMI Connectivity Test
            try{
                $Info = (Get-CimInstance -CimSession $Cimsession -Class Win32_UserProfile -Filter $WQLFilter -ErrorAction stop -OperationTimeoutSec 60 | Sort-Object -Property lastusetime -Descending | select localpath,sid,lastusetime)[0]
                $OS = Get-CimInstance -CimSession $Cimsession -ClassName win32_operatingsystem -OperationTimeoutSec 60 -ErrorAction Stop | select -ExpandProperty caption
                $ServicesNotStarted = Get-CimInstance -CimSession $Cimsession -Class win32_service -OperationTimeoutSec 120 | Where-Object {$_.Startname -like "$DomNetBios*" -and $_.state -ne "Running"} | select name,startname
                $ServiceNames = $ServicesNotStarted.name -join ", "
                $ServiceAccounts = $ServicesNotStarted.startname -join ", "
            }
            Catch{
                $Message = "WMI Lookup failed or timed out"
            }
            if($Message -eq $Null){
                if((get-ciminstance -class win32_serverfeature -CimSession $CimSession | Where-Object {$_.name -like "*Web Server*"}) -ne $Null){
                    $IIS = "Installed"
                    $IISPools = invoke-command -ComputerName $Computer -ScriptBlock{
                        [void][reflection.assembly]::LoadWithPartialName("Microsoft.Web.Administration")
                        $OutputofPools = New-Object Microsoft.web.administration.servermanager
                        $OutputofPools.ApplicationPools
                       
                    }
                    $IISAppPools = $IISPools | Where-Object {$_.name -ne "DefaultAppPool" -and $_.name -notlike "*.NET*"}  | foreach{$_.Name + " - " + $_.State}
                    $IISAppPools = $IISAppPools -join ", "
                }
                Else{
                    $IIS = "Not Installed"
                }
            }
            Remove-CimSession $Cimsession

            [pscustomobject]@{
                ComputerName = $Computer
                OperatingSystem = $OS
                User = $($($Info.Localpath)-split '\\')[-1]
                LastUseTime = $Info.lastusetime
                ServicesNotStarted = $ServiceNames
                ServiceAccounts = $ServiceAccounts
                IIS = $IIS
                ApplicationPools = $IISAppPools
                Message = $Message
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
            Write-Progress -Activity "Computer Activity" -Status "Starting Threads ($($Jobs.count)/$($Computername.count))"

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
        While (@($Jobs | Where {$_.Handle -ne $Null}).Count -gt 0){
            #Progress Bar detailing remaining jobs. This can be modified to reflect what the function is doing
            Write-Progress -Activity "Computer Activity" -Status "Waiting for $(@($Jobs | Where {$_.Handle -ne $Null}).Count) computers to finish"
            ForEach ($Job in $($Jobs | Where-Object {$_.Handle.IsCompleted -eq $True})){
                $Job.Thread.EndInvoke($Job.Handle)
                $Job.Thread.Dispose()
                $Job.Thread = $null
                $Job.Handle = $null
            }
        }

        #Closing Progress Bar
        Write-Progress -Activity "Computer Activity" -Completed

        #Necessary statements to ensure the runspace pool is no longer running in the background in Powershell.
        $RunspacePool.Close()
        $RunspacePool.Dispose()
    }
}