Function Get-ServerService{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string[]]$Service,
        [string[]]$Computername = $env:COMPUTERNAME,
        [int]$MaxThreads = 64
    )

    Begin{
        $Command = {
            Param(
                $Computer,
                [string[]]$Service
            )
            $Name = $Null
            $State = $Null
            $ServiceResult = $null
            $GatheredServices = $Null

            $CimParameters = @{
                Computername = $Computer
                erroraction = "stop"
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
                        $Service = "Computer Not Responding"
                        [pscustomobject]@{
                            'Computer'  = $Computer
                            'Service'   = $Service
                            'State'     = $null
                            'StartMode' = $null
                    } 
                        Continue
                    }
                }

                foreach ($Name in $Service){
                    $ServiceResult = Get-CimInstance  -cimsession $CIMSession -ClassName win32_service -Filter "Name='$($Name)'" -ErrorAction SilentlyContinue | select name,state,startmode
                    if($ServiceResult -ne $Null){
                        $State = $ServiceResult.state
                        $Startmode = $ServiceResult.startmode
                    }
                    Else{
                        $State = "Not Installed"
                        $null = $Startmode
                    }
                    [pscustomobject]@{
                        'Computer'  = $Computer
                        'Service'   = $Name
                        'State'     = $State
                        'StartMode' = $Startmode
                    }  
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
            Write-Progress -Activity "Checking Services" -Status "Loading computers ($($Jobs.count)/$($Computername.count))"

            #This is the actual creation of each thread. Additional arguments should be added to this line if any more are needed by adding ".AddArgument($Argument)" statements to the end of the line with no spaces.
            $PowershellThread = [powershell]::Create().AddScript($Command).AddArgument($Computer).AddArgument($Service)

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
            Write-Progress -Activity "Checking Services" -Status "Waiting for $(@($Jobs | Where {$_.Handle -ne $Null}).Count) computers to finish"
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
            Write-Progress -Activity "Checking Services" -Status "Waiting for $Remaining computers to finish"

            ForEach ($Job in $($Jobs | Where-Object {$_.Handle.IsCompleted -eq $True})){
                $Job.Thread.EndInvoke($Job.Handle)
                $Job.Thread.Dispose()
                $Job.Thread = $null
                $Job.Handle = $null
            }
        }

        #Closing Progress Bar
        Write-Progress -Activity "Multithreading" -Completed

        #Necessary statements to ensure the runspace pool is no longer running in the background in Powershell.
        $RunspacePool.Close()
        $RunspacePool.Dispose()
    }
}

