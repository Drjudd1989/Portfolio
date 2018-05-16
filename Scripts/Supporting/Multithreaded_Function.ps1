Function verb-noun{
    
    Param(
        [string[]]$Computername,
        [int]$MaxThreads = 64
    )

    Begin{
        $Command = {
            Param(
                $Computer
            )
            #Most of the Command will go here
            Write-Output $Computer
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
            Write-Progress -Activity "Multithreading" -Status "Starting threads ($($Jobs.count)/$($Computername.count))"

            #This is the actual creation of each thread. Additional arguments should be added to this line if any more are needed by adding ".AddArgument($Argument)" statements to the end of the line with no spaces.
            $PowershellThread = [powershell]::Create().AddScript($Command).AddArgument($Computer)

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
            Write-Progress -Activity "Multithreading" -Status "Waiting for $(@($Jobs | Where {$_.Handle -ne $Null}).Count -gt 0) threads to finish"
            ForEach ($Job in $($Jobs | Where-Object {$_.Handle.IsCompleted -eq $True})){
                $Job.Thread.EndInvoke($Job.Handle)
                $Job.Thread.Dispose()
                $Job.Thread = $null
                $Job.Handle = $null
            }
        }

        #Closing Progress Bar
        Write-Progress -Activity "Multthreading" -Completed

        #Necessary statements to ensure the runspace pool is no longer running in the background in Powershell.
        $RunspacePool.Close()
        $RunspacePool.Dispose()
    }
}