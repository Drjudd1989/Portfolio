<#
.SYNOPSIS
Gets the Active Directory health of one or more domain controllers or Active Directory Domains.
.DESCRIPTION
Gets the Active Directory health of one or more domain controllers or Active Directory Domains. Checks for General Server/Operating System Health, the ability to make LDAP Queries, Replication Health, and the ability to communicate DNS Queries.
.PARAMETER Server
Specify Fully Qualified Domain Names for one or more servers. Alternatively, you may specify an Active Directory Domain to get the health for all Domain Controllers within it.
.PARAMETER ProgressAction
Specify the behavior of the progress bar.

    Continue:  Display the progress bar.
    SilentlyContinue:  Do not display the progress bar.
.EXAMPLE
Get-ADHealth

Gets the Active Directory health for all domain controllers of the domain you are currently authenticated to.
.EXAMPLE
Get-ADHealth -Server contoso.com

Gets the Active Directory health for all domain controllers in contoso.com.
.EXAMPLE
Get-ADHealth -Server contoso.com,contoso.dev

Gets the Active Directory health for all domain controllers in contoso.com and contoso.dev.
.EXAMPLE
Get-ADHealth -Server contoso1.contoso.com,contoso2.contoso.dev

Gets the Active Directory Health for contoso1.contoso.com,contoso2.contoso.dev.
.INPUTS
System.String[]
.OUTPUTS
PSCustomObject
#>

Function Get-ADHealth {
    [CmdletBinding(PositionalBinding=$false)]

    Param (
        [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)]
        [String[]]$Server = (Get-ADDomain).DNSRoot,

        [ValidateSet('Continue','SilentlyContinue')]
        [String]$ProgressAction = 'Continue'
    )

    Begin {
        $ProgressPreference = $ProgressAction
    } # Begin

    Process {
        $Results = @()

        Foreach ($D in $Server) {
            # If domain name is specified strip Domain and get domain controller list
            $TempDomain = (($D -split '\.')[-2,-1] -join '.')
            $TempDCs = Get-ADDomainController -Filter * -Server $TempDomain -ErrorAction SilentlyContinue | Select -ExpandProperty Hostname

            If ($D -match '^Domain\w*?\.\w*$') {
                $DCs = $TempDCs
            }
            Else {
                $DCs = $D
            }

            # Get health for all of the individual domains specified
            Write-Progress -Activity "Verifying Active Directory Health for $D" -Status "Checking Server Health on $D"
            $Healths = Get-WSAServerHealth -Computername $DCs -ProgressAction SilentlyContinue

            # Recording offline systems for use later in the code
            $OfflineSystems = $Healths | where {$_.ping,$_.WMI,$_.WinRM,$_.SMB -notcontains $True} | Select -ExpandProperty ComputerName

            # Compiling DNS list to check against
            $DNS = $TempDCs
            $DNS += 'yahoo.com'
            $DNS += $TempDomain
            $DNS += Get-ADTrust -Filter *  -Server $TempDomain | Select -ExpandProperty Target

            $i = 0

            Foreach ($Health in $Healths){
            $i++
               Write-Progress -Activity "Verifying Active Directory Health for $D" -Status "Checking Health on $($Health.Computername) ($i/$($Healths.Count))" -PercentComplete ($i/$($Healths.Count) * 100) 
                $Message = @()

                # Check if System is online
                If ($OfflineSystems -contains $Health.ComputerName){
                    $Message += 'System Offline'
                }
                Else {
                    # AD Services online

                    # Check CPU
                    if ($Health.CPUUtilization -gt 90){
                        $Message += "CPU at $($Health.CPUUtilization)% Utilization"
                    }
                    
                    # Check Memory
                    if ($Health.MemoryUtilization -gt 90){
                        $Message += "Memory at $($Health.MemoryUtilization)% Utilization"
                    }

                    # Check Operating System
                    If ($Health.Status -eq 'Unhealthy') {
                        if ($Health.Ping -eq $false){
                            $Message += 'Cannot Ping'
                        }

                        if ($Health.WMI -eq $false){
                            $Message += 'Cannot Connect via WMI'
                        }

                        if ($Health.WinRM -eq $false){
                            $Message += 'Cannot Connect via WinRM'
                        }

                        if ($Health.SMB -eq $false){
                            $Message += 'Cannot Connect via SMB'
                        }

                        if ($Health.FreeDiskSpace -le 2){
                            $Message += "C: at $($Health.FreeDiskSpace) GB of Free Space"
                        }

                        if ($Health.ServicesNotStarted -ne [String]::Empty){
                            $Message += "$($Health.ServicesNotStarted) service(s) have not started"
                        }
                        # $Message += 'Operating System not Healthy'
                    }

                    Write-Progress -Activity "Verifying Active Directory Health for $D" -Status "Checking DNS Health on $($Health.Computername) ($i/$($Healths.Count))" -PercentComplete ($i/$($Healths.Count) * 100) 
                    # Check DNS
                    If (($DNS | Foreach {((Resolve-DnsName -Name $_ -Server $Health.ComputerName -ErrorAction SilentlyContinue) -ne $Null)}) -Contains $False) {
                        $Message += 'Failed DNS Lookup'
                    }

                    Write-Progress -Activity "Verifying Active Directory Health for $D" -Status "Checking LDAP Health on $($Health.Computername) ($i/$($Healths.Count))" -PercentComplete ($i/$($Healths.Count) * 100) 
                    # Check LDAP
                    If ((Test-WSAADLDAPConnection -ComputerName $Health.ComputerName).Connected -eq $False) {
                        $Message += 'Failed LDAP Connection'
                    }

                    Write-Progress -Activity "Verifying Active Directory Health for $D" -Status "Checking Replication Health on $($Health.Computername) ($i/$($Healths.Count))" -PercentComplete ($i/$($Healths.Count) * 100) 
                    # Check Replication
                    If ((Get-WSAADReplicationData -ComputerName $Health.ComputerName -ErrorAction SilentlyContinue | Where {($_.NumberOfFailures -ne 0) -and ($_.Partner -notin $OfflineSystems)}) -ne $Null) {
                        $Message += 'Failed Replication'
                    }
                }

                If (($Message -Join '; ') -ne '') {
                    $Results += [PSCustomObject]@{
                        Computername = $Health.ComputerName
                        Status = 'Unhealthy'
                        Message = $Message -Join '; '
                    }
                }
                Else {
                    $Results += [PSCustomObject]@{
                        Computername = $Health.ComputerName
                        Status = 'Healthy'
                        Message = ''
                    }
                }
            } # Foreach ($Health in $Healths)
            Write-Progress -Activity "Verifying Active Directory Health for $D" -Completed

        } # Foreach ($D in $Server)

        $Results | Sort Computername
    } # Process

    End {

    } # End
} # Function Get-WSAADHealth 