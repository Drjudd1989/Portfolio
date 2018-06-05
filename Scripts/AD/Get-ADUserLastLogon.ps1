function Get-ADUserLastLogon {
    [CmdletBinding(
        PositionalBinding=$false
    )]

    Param (
        [Parameter(
            Mandatory=$true,
            Position=0
        )]
        [String[]]$Identity,
        [Parameter(
            Position=1
        )]
        [String]$Server = (Get-ADDomain).DNSRoot,
        [PSCredential]$Credential
    )

    Process {
        
        # Retrieving Domain Controllers for specified domain
        $DCParam = @{
            Server = $Server
            Filter = {Name -like "*"}
        }
        If ($Credential -ne $Null) {$DCParam.Add('Credential',$Credential)}
        $DomainControllers = Get-ADDomainController @DCParam | select -ExpandProperty Hostname
        
        # Processing each user
        ForEach($Ident in $Identity){
            $Time = 0

            # Querying each Domain Controller for the latest LastLogon date
            ForEach($DomainController in $DomainControllers){
                $UserParam = @{
                    Identity = $Ident
                    Server = $DomainController
                    Properties = 'LastLogon','Created'
                }
                If ($Credential -ne $Null) {$UserParam.Add('Credential',$Credential)}
                $UserLogon = Get-ADuser @UserParam | select LastLogon,Created
                If($UserLogon.LastLogon -gt $Time){
                    $Time = $UserLogon.LastLogon
                }
            }
            
            # Ascertaining either the actual LastLogon date or the date in which the account was created if account has not been used
            If([System.String]::IsNullOrEmpty($Time)){
                $LastLogon = $UserLogon.Created.ToString()
            }
            ElseIf($Time -eq '0'){
                $LastLogon = $UserLogon.Created.ToString()
            }
            Else{
                $LastLogon = [System.DateTime]::FromFileTime($Time).ToString()
            }

            # Calculating the days since last logon
            $DaysSinceLastLogon = New-TimeSpan -End (Get-Date) -Start $LastLogon | select -ExpandProperty Days

            [PSCustomObject]@{
                SAMAccountName = $Ident
                LastLogon = $LastLogon
                DaysSinceLastLogon = $DaysSinceLastLogon
            }
        } # End ForEach($Ident in $Identity)
    } # End Process
} # End Function