Function Get-ServerSoftware{
    <#
    .Synopsis
       Obtain a full list of installed software.
    .DESCRIPTION
       Obtain a full list of installed software. Data is gathered by scanning the uninstall keys within the registry to return a full list of installed software. This is a multithreaded command.
    .PARAMETER Computername
        The computer hostname(s) to query. Default value is the local computer name.
    .PARAMETER Filter
        Filters the output of the command. Filter accepts wildcard characters.
    .PARAMETER MaxThreads
        The number of threads that can be running at one time. Default is 64 threads.
    .PARAMETER Credential
        A Credential object from Get-Credential.
    .EXAMPLE
        Get-ServerSoftware

        Gets installed software from the local server.
    .EXAMPLE
        Get-ServerSoftware -computername "server1.contoso.com","server2.contoso.com"

        Gets installed software from server1.contoso.com and server2.contoso.com.
    .EXAMPLE
        Get-ServerSoftware -computername "server1.contoso.com","server2.contoso.com" -filter "*chrome*"

        Shows all installed software with "chrome" in the name from server1.contoso.com and server2.contoso.com.
    .EXAMPLE
        Get-ServerSoftware -computername "server1.contoso.com","server2.contoso.com" -credentials (get-credentials)

        Gets installed software from server1.contoso.com and server2.contoso.com using the credentials specified by user.
    .EXAMPLE
        $Creds = get-credential
        Get-ServerSoftware -computername "server1.contoso.com","server2.contoso.com" -credentials $Creds -filter *microsoft*

        Stores user inputted credentials into the "Creds" variable. Gets installed software with "Microsoft" in the name from server1.contoso.com and server2.contoso.com using the credentials specified stored in the "Creds" variable.
    #>
    
    Param(
        [string[]]$Computername = $env:COMPUTERNAME,
        [pscredential]$Credential,
        [string]$Filter,
        [int]$MaxThreads = 64
    )

    Begin{
        
        $Timestamp = Get-date -Format g
        $Command = {
            Param(
                $Computer,
                $Credential,
                $Filter,
                $Timestamp
            )

            $OS,$IP,$Message,$Domain, $scope = $null

            $HKLocalMachine = [Convert]::ToUInt32(80000002, 16)
            $HKU = [Convert]::ToUInt32(80000003, 16)
            $Userkey = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
            $SubKeys = New-Object System.Collections.ArrayList
            $null = $Subkeys.Add("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
            $null = $SubKeys.Add("SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall")



            $CimParameters = @{
                Computername = $Computer
                erroraction = "stop"
                OperationTimeoutSec = 90
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
                        [pscustomobject]@{
                            ComputerName = $Computer
                            Domain = $Null
                            IP = $Null
                            OS = $Null
                            ApplicationName = $Null
                            InstallDate = $Null
                            CurrentVersion = $Null
                            Scope = $null
                            Timestamp = $Timestamp
                            Message = "Cannot Connect over DCOM/WSMAN"
                        }
                        Continue
                    }
                }
                try{$OS = (Get-CimInstance -CimSession $CimSession -ClassName cim_operatingsystem -OperationTimeoutSec 30).caption}catch{$OS = $Null}
                try{$Domain = (Get-CimInstance -CimSession $CimSession -ClassName cim_computersystem -OperationTimeoutSec 30).domain}catch{$Domain = $Null}
                try{$IP = (Test-Connection $Computer -Count 1 -ErrorAction Stop).IPV4Address.ipaddresstostring}Catch{$Message = "Could Not Resolve DNS Name";$IP = $Null}

            $EnumArgs = @{
                hDefKey = $HKLocalMachine
                sSubKeyName = $UserKey
            }
            $CIMMethodParams = @{
                Namespace = 'root\cimv2'
                ClassName = 'StdRegProv'
                MethodName = 'EnumKey'
                Arguments = $EnumArgs
                CIMSession = $CimSession
                ErrorAction = 'SilentlyContinue'
            }

            $UserSIDs = (Invoke-CimMethod @CIMMethodParams).snames | Where-Object {$_ -like "S-1-5*"}
            foreach($UserSID in $UserSIDs){
                $Null = $SubKeys.Add("$UserSID\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
                $Null = $SubKeys.Add("$UserSid\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall")
            }

            Foreach($Subkey in $Subkeys){
                if($Subkey -like "S-1-5*"){
                    $hdefkey = $HKU
                    $scope = 'User'
                }
                Else{
                    $hdefkey = $HKLocalMachine
                    $scope = 'LocalMachine'
                }
                $EnumArgs = @{
                    hDefKey = $hdefkey
                    sSubKeyName = $Subkey
                }
                $CIMMethodParams = @{
                    Namespace = 'root\cimv2'
                    ClassName = 'StdRegProv'
                    MethodName = 'EnumKey'
                    Arguments = $EnumArgs
                    CIMSession = $CimSession
                    ErrorAction = 'SilentlyContinue'

                }
                $Results = Invoke-CimMethod @CIMMethodParams
                Foreach($Result in $Results.snames){

                    $Values = $Null
                    $DisplayName = $Null
                    $InstallDate = $Null
                    $DisplayVersion = $Null

                        $EnumArgs = @{
                            hDefKey = $hdefkey
                            sSubKeyName = $Subkey + '\' + $Result
                        }
                        $CIMMethodParams = @{
                            Namespace = 'root\cimv2'
                            ClassName = 'StdRegProv'
                            MethodName = 'EnumValues'
                            Arguments = $EnumArgs
                            CIMSession = $CimSession
                            ErrorAction = 'SilentlyContinue'

                        }
                        $Values = Invoke-CimMethod @CIMMethodParams
                        $Values = $Values.snames | Where-Object {$_ -eq 'Displayname' -or $_ -eq 'InstallDate' -or $_ -eq 'DisplayVersion' -and $_ -ne $Null}
                        #If displayname does not equal one of the filters, then run the other queries for the values. Also, try new-psdrive - Will still allow for creds but will allow a more filesystem like browsing, similarly to the profile and folder sizes.
                        foreach($Value in $Values){
                            $EnumArgs = @{
                                hDefKey = $hdefkey
                                sSubKeyName = $Subkey + '\' + $Result
                                sValueName = $Value
                            }
                            $CIMMethodParams = @{
                                Namespace = 'root\cimv2'
                                ClassName = 'StdRegProv'
                                MethodName = 'GetSTRINGValue'
                                Arguments = $EnumArgs
                                CIMSession = $CimSession
                                ErrorAction = 'SilentlyContinue'
                            }
                            $StringValue = (Invoke-CimMethod @CIMMethodParams).svalue
                            Switch($Value){
                                DisplayName{$DisplayName = $StringValue}
                                InstallDate{$InstallDate = $StringValue}
                                DisplayVersion{$DisplayVersion = $StringValue}
                            }
                        }
                        if($Values -ne $Null){
                            if($Filter){
                                if($DisplayName -like "$Filter"){
                                    [PSCustomObject]@{
                                        ComputerName = $Computer
                                        Domain = $Domain
                                        IP = $IP
                                        OS = $OS
                                        ApplicationName = $DisplayName
                                        InstallDate = $InstallDate
                                        CurrentVersion = $DisplayVersion
                                        Scope = $scope
                                        Timestamp = $Timestamp
                                        Message = $Message
                                    }
                                }
                            }
                            else{
                                [PSCustomObject]@{
                                    ComputerName = $Computer
                                    Domain = $Domain
                                    IP = $IP
                                    OS = $OS
                                    ApplicationName = $DisplayName
                                    InstallDate = $InstallDate
                                    CurrentVersion = $DisplayVersion
                                    Scope = $scope
                                    Timestamp = $Timestamp
                                    Message = $Message
                                }
                            }
                        }
                }
            }
            Remove-CimSession $CimSession
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
            $PowershellThread = [powershell]::Create().AddScript($Command).AddArgument($Computer).AddArgument($Credential).AddArgument($Filter).AddArgument($Timestamp)

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
            Write-Progress -Activity "Multithreading" -Status "Waiting for $(@($Jobs | Where {$_.Handle -ne $Null}).Count) threads to finish"
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
            Write-Progress -Activity "Multithreading" -Status "Waiting for $Remaining to finish"

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