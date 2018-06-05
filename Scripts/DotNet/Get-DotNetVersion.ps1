Function Get-DotNetVersion {
    
    <#
    .Synopsis
       Gets all versions of the .Net framework currently installed.
    .DESCRIPTION
       Gets all versions of the .Net framework currently installed on one or more computers. This is a multithreaded Cmdlet.
    .PARAMETER ComputerName
       Specify one or more Fully Qualified Domain Names (FQDN).

       Ex: 'server1.contoso.com'
    .PARAMETER MaxThreads
       Specify the maximum number of threads to be used by this Cmdlet.
    .EXAMPLE
       C:\PS>Get-DotNetVersion

       Gets the installed versions of the .Net framework for your local computer.
    .EXAMPLE
       C:\PS>Get-DotNetVersion -Computername 'server1.contoso.com','server2.contoso.com','dc1.contoso.com'

       Gets the installed versions of the .Net framework for server1.contoso.com, server2.contoso.com and dc1.contoso.com.
    .EXAMPLE
       C:\PS>$Servers = Get-ADComputer -Filter {OperatingSystem -like '*Windows Server*'} | Select -ExpandProperty DNSHostName
       C:\PS>Get-DotNetVersion -Computername $Servers


       Gets the installed versions of the .Net framework for all Windows servers in the current domain.
    .INPUTS
       None. This Cmdlet does not accept any pipeline input.
    .OUTPUTS
       PSCustomObject
    #>

    [CmdletBinding()]
    Param (
        [String[]]$Computername = $([System.Net.Dns]::GetHostEntry('').HostName),

        [Int32]$MaxThreads = 64
    )

    Begin {
        Write-Progress -Activity 'Getting .Net Version' -Status 'Setting up Runspaces'

        $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads)
        $RunspacePool.Open()
        $RunspaceCollection = New-Object System.Collections.ArrayList
        $i = 0

        $ScriptBlock = {
            Param (
                $Computer
            )

            Function ConvertFileVersion {
                Param ($Version)
                $Version = ($Version -split '\.')[-1]
                If ($Version -ge '0' -and $Version -le '17000') {
                    '4.0'
                }
                ElseIf ($Version -ge '17001' -and $Version -le '18400') {
                    '4.5'
                }
                ElseIf ($Version -ge '18401' -and $Version -le '34000') {
                    '4.5.1'
                }
                ElseIf ($Version -gt '34000') {
                    '4.5.2'
                }
                Else {
                    $False
                }

            }

            Function ConvertRegistryVersion {
                Param ($Version)
                Switch ($Version){
                    378389 {'4.5'}
                    378675 {'4.5.1'}
                    378758 {'4.5.1'}
                    379893 {'4.5.2'}
                    393295 {'4.6'}
                    393297 {'4.6'}
                    394254 {'4.6.1'}
                    394271 {'4.6.1'}
                }
            }

            Try {
                $Session = New-CimSession -ComputerName $Computer -ErrorAction Stop
                $null = get-ciminstance -CIMSession $Session win32_operatingsystem -ErrorAction Stop
            }
            Catch {
                
                Try {
                    $Session = New-CimSession -ComputerName $Computer -SessionOption (New-CimSessionOption -Protocol Dcom) -ErrorAction Stop
                }
                Catch {
                    $Result = [PSCustomObject]@{
                        Computername = $Computer
                        OperatingSystem = $null
                        Architecture = $null
                        V2_0 = $null
                        V3_0 = $null
                        V3_5 = $null
                        V4 = $null
                        Status = "Cannot Connect"
                    }
                    
                }

                
            }

            If ($Session.TestConnection() -eq $true) {
                $Result = [PSCustomObject]@{
                    Computername = $Computer
                    OperatingSystem = $null
                    Architecture = $null
                    V2_0 = $null
                    V3_0 = $null
                    V3_5 = $null
                    V4 = $null
                    Status = 'Connected'
                }
                $Result.OperatingSystem = (Get-CimInstance -CimSession $Session -ClassName Win32_Operatingsystem).Caption
                $Result.Architecture = If((Get-CimInstance -CimSession $Session -ClassName Win32_Operatingsystem).OSArchitecture -ne $Null){(Get-CimInstance -CimSession $Session -ClassName Win32_Operatingsystem).OSArchitecture}else{"32-bit"}
                Try {
                    $Result.V2_0 = If((Invoke-CimMethod -ErrorAction Stop -CimSession $Session -ClassName stdregprov -MethodName GetStringValue -Arguments @{hDefKey = [uint32]2147483650;sSubkeyName = "SOFTWARE\Microsoft\Net Framework Setup\NDP\v2.0.50727\";sValueName = "Version"}).ReturnValue -eq 0){"2.0"}Else{$False}
                }
                Catch {
                    $Result.V2_0 = $False
                }

                Try {
                    $Result.V3_0 = If((Invoke-CimMethod -ErrorAction Stop -CimSession $Session -ClassName stdregprov -MethodName GetStringValue -Arguments @{hDefKey = [uint32]2147483650;sSubkeyName = "SOFTWARE\Microsoft\Net Framework Setup\NDP\v3.0\";sValueName = "Version"}).ReturnValue -eq 0){"3.0"}Else{$False}
                }
                Catch {
                    $Result.V3_0 = $False
                }

                Try {
                    $V3_5Installed = Invoke-CimMethod -ErrorAction Stop -CimSession $Session -ClassName stdregprov -MethodName GetDWORDValue -Arguments @{hDefKey = [uint32]2147483650;sSubkeyName = "SOFTWARE\Microsoft\Net Framework Setup\NDP\v3.5\";sValueName = "Install"} | Select -ExpandProperty UValue
                    $V3_5ServicePack = Invoke-CimMethod -ErrorAction Stop -CimSession $Session -ClassName stdregprov -MethodName GetDWORDValue -Arguments @{hDefKey = [uint32]2147483650;sSubkeyName = "SOFTWARE\Microsoft\Net Framework Setup\NDP\v3.5\";sValueName = "SP"} | Select -ExpandProperty UValue
                    $V3_5Version = Invoke-CimMethod -ErrorAction Stop -CimSession $Session -ClassName stdregprov -MethodName GetStringValue -Arguments @{hDefKey = [uint32]2147483650;sSubkeyName = "SOFTWARE\Microsoft\Net Framework Setup\NDP\v3.5\";sValueName = "Version"} | Select -ExpandProperty SValue
                }
                Catch {
                    $Result.V3_5 = $False
                }

                If ($Result.OperatingSystem -like '*2012*' -or $Result.OperatingSystem -like '*2003*'){
                    If ($V3_5Version -ne $Null -and $V3_5Version -ne "" -and $V3_5Installed -ne 0){
                        $Result.V3_5 = '3.5'
                    }
                    Else {
                        $Result.V3_5 = $False
                    }
                }
                ElseIf ($Result.OperatingSystem -like '*2008*') {
                    If ($V3_5Version -ne $Null -and $V3_5Version -ne '' -and $V3_5Installed -ne 0){
                        $Result.V3_5 = '3.5.1'
                    }
                    Else {
                        $Result.V3_5 = $False
                    }
                }

                If ($Result.Operatingsystem -like '*2012*') {
                    Try{
                        $Result.V4 = ConvertRegistryVersion -Version ((Invoke-CimMethod -CimSession $Session -ClassName stdregprov -MethodName GetDWORDValue -Arguments @{hDefKey = [uint32]2147483650;sSubkeyName = 'SOFTWARE\Microsoft\Net Framework Setup\NDP\v4\Full\';sValueName = 'Release'}).UValue)
                    }
                    Catch {
                        $Result.V4 = $False
                    }
                }
                Else {
                    Try {
                        $Result.V4 = ConvertFileVersion -Version (Get-CimInstance -CimSession $Session -ClassName CIM_DataFile -Filter "Name = 'C:\\Windows\\Microsoft.NET\\Framework\\v4.0.30319\\clr.dll'").Version
                    }
                    Catch {
                        $Result.V4 = $False
                    }
                }
            }
            Else {
                $Result = [PSCustomObject]@{
                    Computername = $Computer
                    OperatingSystem = $null
                    Architecture = $null
                    V2_0 = $null
                    V3_0 = $null
                    V3_5 = $null
                    V4 = $null
                    Status = 'Cannot Connect'
                }
            }

            $Result
            $Session.Close()
            Remove-Variable Result
            Remove-CimSession $Session
        } #$ScriptBlock
    } #Begin

    Process {
        
        ForEach ($Computer in $Computername) {
            $i++
            Write-Progress -Activity 'Getting .Net Version' -Status "Creating thread for $Computer ($i/$($Computername.Count))"
            $Powershell = [Powershell]::Create()
            $Powershell.RunspacePool = $RunspacePool
            $Null = $Powershell.AddScript($ScriptBlock).AddArgument($Computer)
            $Handle = $Powershell.BeginInvoke()
            $Null = $RunspaceCollection.Add([PSCustomObject]@{
                                        ComputerName = $Computer
                                        Thread = $Powershell
                                        Handle = $Handle
                                    })
        }
    } #Process

    End {
        While ($($RunspaceCollection | where {$_.Handle.IsCompleted -ne 'Completed'}).count -ne 0) {
            Write-Progress -Activity 'Getting .Net Version' -Status "Waiting for $(($RunspaceCollection | where {$_.Handle.IsCompleted -ne 'Completed'}).count) threads to finish"
            Start-Sleep -Milliseconds 200
        }

        Write-Progress -Activity 'Getting .Net Version' -Status 'Retrieving results'

        $RunspaceCollection | Foreach {
            $_.Thread.EndInvoke($_.Handle)
            $_.Thread.Dispose()
        }

        Write-Progress -Activity 'Getting .Net Version' -Completed

        $RunspacePool.Close()
        $RunspacePool.Dispose()
    } #End
}