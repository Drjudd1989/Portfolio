function Get-ADUser{

<#
    .SYNOPSIS
    Gets a list of all Active Directory User Objects within a specified domain
    .DESCRIPTION
    Gets a list of all Active Directory User Objects within a specified domain.
    .PARAMETER  Server
    Specify the domain to grab the user list from. If no domain is specified, it will default to the local domain.
    .PARAMETER  Credential
    Specify credentials to be used when running.
    .PARAMETER  Searchbase
    Filter down the user list to a specific OU by specifying the search base.
    .PARAMETER  FilterUser
    Filter results by the a partial or full username.
    .EXAMPLE
    Get-ADUser

    Returns a list of all User objects for the local domain
    .EXAMPLE
    Get-ADServer -server contoso.com -credential (Get-Credential)

    Asks for credentials to be specified and will then return a list of all user objects in the Contoso.com domain
    .EXAMPLE
    Get-ADServer -server contoso.com -filteruser "TestUser"

    Returns a list of all user objects with a name like TestUser in Contoso.com
    .EXAMPLE
    .INPUTS
    None. This commandlet does not accept any pipeline input
    .OUTPUTS
    System.String
    .LINK
#>

    param(
        [parameter(ValueFromPipeline=$True)]
        [string]$Server = $(get-addomain | select -ExpandProperty dnsroot),
        [PSCredential]$Credential,
        [string]$Searchbase,
        [string]$FilterUser,
        [switch]$LastLogon

    )
    function Get-PDADUserLastLogon {
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
        [String]$Server,
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

        $Message = $Null
        $Info = $Null
        $Time = $Null
        $UserProperties = $Null
        

        $ADUserProperties = @{
            Properties = "samaccountname","CanonicalName","enabled","PasswordNeverExpires","modified"
            Server = $Server
            ErrorAction = "Stop"
            filter = "*"
        }
        If($Credential){
            $ADUserProperties.Add('Credential',$Credential)
        }
        If($Searchbase){
            $ADUserProperties.Add('Searchbase',$Searchbase)
        }
        if($FilterUser){
            $ADUserProperties.Remove('Filter')
            $FilterString = "samaccountname -like ""$FilterUser"""
            $ADUserProperties.add('Filter',$FilterString)
        }

        try{
        Write-Progress -Activity "Gathering Users" -Status "Getting User Objects"
        $UserProperties = @(Get-ADUser @ADUserProperties | select samaccountname,CanonicalName,enabled,PasswordNeverExpires,modified)
        }
        Catch{
            throw "Cannot perform the requested lookup. Please verify the Server, Searchbase, Credentials are correct"
            }
    Write-Progress -Activity "Gathering Users" -Completed
    $i = 0
    foreach($User in $UserProperties){
        $i++
        Write-Progress -Activity 'Getting LastLogon Dates' -Status "Getting LastLogon date for $($User.samaccountname) ($i/$($UserProperties.count))" -PercentComplete (($i/$UserProperties.count) * 100)
        <#if($User.Lastlogondate -eq $Null){
            $Lastlogon = $User.Modified
        }
        Else{
            $Lastlogon = $User.LastLogonDate
        }#>


        $CNFull = $User.CanonicalName
        $RemovalValue = ($CNFull -split "/")[-1]
        $CN = $CNFull.trimend($RemovalValue)
        $Output = [pscustomobject]@{
            User = $User.Samaccountname
            Domain = $Server
            Enabled = $User.Enabled
            PasswordNeverExpires = $User.PasswordNeverExpires
            CanonicalName = $CN
        }
        if($LastLogon){
            $UserLastLogonParams = @{
                Identity = $User.SamAccountName
                Server = $Server
            }
            If($Credential){
                $UserLastLogonParams.Add('Credential',$Credential)
            }
            $LastLogonDate = Get-PDADUserLastLogon @UserLastLogonParams | select lastlogon,dayssincelastlogon
            $Output | Add-Member -NotePropertyName 'LastLogon' -NotePropertyValue $LastLogonDate.lastlogon
            $Output | Add-Member -NotePropertyName 'DaysSinceLastLogon' -NotePropertyValue $LastLogonDate.dayssincelastlogon
            }
        $Output
    }
    Write-Progress -Activity 'Getting LastLogon Dates' -Completed
}
