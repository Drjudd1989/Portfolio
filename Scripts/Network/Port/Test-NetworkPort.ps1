Function Test-NetworkPort{

<#
    .SYNOPSIS
    Test port avaialbility from a specified source and destination. This is a multithreaded command.
    .DESCRIPTION
    Test a port or list of ports from a source or list of sources to a destination
    .PARAMETER  Computername
    Specify the source(s) to run the port test from. If not specified, it will default to the local computer.
    .PARAMETER  Port
    Specify the port to be tested
    .PARAMETER  Destination
    Specify the destination to test the port against
    .PARAMETER  MaxThreads
    Specify how many threads to run at once. Threads are set for each computer. Default value is 64 threads.
    .EXAMPLE
    Test-NetworkPort -port 80 -destination DestinationServer3.contoso.com
    Tests connectivity with DestinationServer3.contoso.com over port 80 from the local computer
    .EXAMPLE
    Test-NetworkPort -computername Comp1,Comp2,Comp3 -port 80,553 -destination DestinationServer3.contoso.com
    Tests connectivier with DestinationServer3.contoso.com over port 80 and 553 from Comp1, Comp2, and Comp3.
    .INPUTS
    System.String
    System.Int32
    .OUTPUTS
    System.String
    .LINK
#>

    
    Param(
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [string[]]$Computername = $Env:COMPUTERNAME,
        [parameter(Mandatory = $True)]
        [int[]]$Port,
        [parameter(Mandatory = $True)]
        [string]$Destination,
        [int]$MaxThreads = 64
    )

    Begin{
        $Command = {
            Param(
                $Computer,
                [int[]]$Port,
                [string]$Destination
            )
            $Result = $Null
            $Message = $Null
            
            foreach($P in $Port){
                $Result = Invoke-Command -ComputerName $Computer -ArgumentList $Destination,$P -ScriptBlock {
                    New-Object System.Net.Sockets.TcpClient($($args[0]),$($args[1]))
                }
                if($Result -eq $Null){
                    $Message = "Cannot connect to destination over specified port"
                }

                [pscustomobject]@{
                    Name = $Computer
                    Destination = $Destination
                    Port = $P
                    Connected = $Result.Connected
                    Message = $Message
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
            Write-Progress -Activity "Multithreading" -Status "Starting threads ($($Jobs.count)/$($Computername.count))"

            #This is the actual creation of each thread. Additional arguments should be added to this line if any more are needed by adding ".AddArgument($Argument)" statements to the end of the line with no spaces.
            $PowershellThread = [powershell]::Create().AddScript($Command).AddArgument($Computer).AddArgument($Port).AddArgument($Destination)

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
            Write-Progress -Activity "Multithreading" -Status "Waiting for $(@($Jobs | Where {$_.Handle -ne $Null}).Count) threads to finish"
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