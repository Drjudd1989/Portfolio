function Get-PDADServer{

<#
    .SYNOPSIS
    Gets a list of all Active Directory Computer Objects within a specified domain
    .DESCRIPTION
    Gets a list of all Active Directory Computer Objects within a specified domain. Results can be filtered by OS or if enabled.
    .PARAMETER  Server
    Specify the domain to grab the computer list from. If no domain is specified, it will default to the local domain.
    .PARAMETER  Credential
    Specify credentials to be used when running.
    .PARAMETER  Searchbase
    Filter down the computer list to a specific OU by specifying the search base.
    .PARAMETER  FilterOS
    Filter results by the specified Operating System (Windows, Linux, or Cent).
    .PARAMETER  Enabled
    Filter results to only show computer objects that are enabled.
    .PARAMETER  PingCheck
    Ping each computer object returned and output a true or false value based on the response of the ping.
    .PARAMETER  ConnectivityCheck
    Attempt to establish a connection with each computer object and return a value based on if the connection was successful or not. Connection attempts include DCOM and WSMAN.
    .EXAMPLE
    Get-PDADServer

    Returns a list of all computer objects for the local domain
    .EXAMPLE
    Get-PDADServer -server contoso.com -credential (Get-Credential) -filteros Windows

    Asks for credentials to be specified and will then return a list of all Windows computer objects in the Contoso.com domain
    .EXAMPLE
    Get-PDADServer -server contoso.com -filteros Windows -enabled -pingcheck -connectivitycheck

    Returns a list of all enabled Windows computer objects in Contoso.com and checks to see if those objects respond to a ping and can be connected too.
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
        $Credential,
        [string]$Searchbase,
        [validateset("Windows","Linux","Cent")]
        [string]$FilterOS,
        [Switch]$Enabled,
        [switch]$PingCheck,
        [switch]$ConnectivityCheck
    )
        $Message = $Null
        $Info = $Null
        $Time = $Null
        $ComputerProperties = $Null
        $CIMSession = $Null
        
        

        $ADComputerProperties = @{
            Properties = "operatingsystem","CanonicalName","enabled","description"
            Server = $Server
            ErrorAction = "Stop"
            filter = "*"
        }
        If($Credential){
            $ADComputerProperties.Add('Credential',$Credential)
        }

        If($Searchbase){
            $ADComputerProperties.Add('Searchbase',$Searchbase)
        }

        if($FilterOS){
            $ADComputerProperties.Remove('Filter')
            $FilterString = "Operatingsystem -like ""*$FilterOS*"""
            $ADComputerProperties.add('Filter',$FilterString)
        }

        try{
            Write-Progress -Activity "Gathering Objects" -Status "Getting Computer Objects"
            $ComputerProperties = Get-ADComputer @ADComputerProperties | select name,dnshostname,operatingsystem,CanonicalName,enabled,description
            
            if($Enabled){
                $ComputerProperties = $ComputerProperties | Where-Object {$_.enabled -eq "True"}
            }
        }
        Catch{
            throw "Cannot perform the requested lookup. Please verify the Server, Searchbase, Credentials are correct"
            }
    $i = 0      
    foreach ($Computerproperty in $ComputerProperties){
        if(!($Computerproperty.description | Where-Object {$_ -eq "Failover cluster virtual network name account"})){
            $DCOM = $Null
            $WSMAN = $Null
            $Ping = $Null
            $FQDNCompName = $Computerproperty.name + "." + $Server

            $i++
            if($PingCheck){
            Write-Progress -Activity "Gathering Objects" -Status "Pinging $($FQDNCompName) - $i/$($ComputerProperties.count)" -PercentComplete ($i/$($ComputerProperties.count) * 100)
            $Ping = Test-Connection -ComputerName $FQDNCompName -Count 1 -quiet -ErrorAction SilentlyContinue
            }

            If($ConnectivityCheck){
            
                if($ComputerProperty.Operatingsystem -like "*Windows*" -and $Computerproperty.Enabled -eq "True"){
                    try{
                        $CIMParam = @{
                            Computername = $FQDNCompName
                            Erroraction = "Stop"
                        }
                    if($Credential){
                        $CIMParam.Add('Credential',$Credential)
                        }
                        Write-Progress -Activity "Gathering Objects" -Status "Testing DCOM on $($FQDNCompName) - $i/$($ComputerProperties.count)" -PercentComplete ($i/$($ComputerProperties.count) * 100)
                        $CIMSession = New-CimSession @CIMParam -SessionOption (New-CimSessionOption -Protocol Dcom) -OperationTimeoutSec 5
                        $ConnectedMessage = "DCOM"
                        Remove-CimSession -CimSession $Cimsession
                    }
                    Catch{
                        try{
                            Write-Progress -Activity "Gathering Objects" -Status "DCOM Failed. Testing WSMAN on $($FQDNCompName) - $i/$($ComputerProperties.count)" -PercentComplete ($i/$($ComputerProperties.count) * 100)
                            $CIMSession = New-CimSession @CIMParam -OperationTimeoutSec 5
                            $ConnectedMessage = "WSMAN"
                            Remove-CimSession -CimSession $Cimsession
                        }
                        catch{
                            $ConnectedMessage = "Failed"
                        }
                    }
                
                }
                Else{
                    $ConnectedMessage = $Null
                }
            }

            $CNFull = $ComputerProperty.CanonicalName
            $RemovalValue = ($CNFull -split "/")[-1]
            $CN = $CNFull.trimend($RemovalValue)
            Write-Progress -Activity "Gathering Objects" -Status "Adding to Output for $($FQDNCompName) - $i/$($ComputerProperties.count)" -PercentComplete ($i/$($ComputerProperties.count) * 100)
            $OutputObject = [pscustomobject]@{
                ComputerName = $Computerproperty.name
                Server = $Server
                OperatingSystem = $ComputerProperty.Operatingsystem
                CanonicalName = $CN
                Enabled = $ComputerProperty.Enabled
            }
            if($PingCheck){
                $OutputObject | add-member -NotePropertyName "Ping" -NotePropertyValue $Ping
            }
            if($ConnectivityCheck){
                $OutputObject | add-member -NotePropertyName "ConnectedProtocol" -NotePropertyValue $ConnectedMessage
                #$OutputObject | add-member -NotePropertyName "WSMAN" -NotePropertyValue $WSMAN
            }
            Write-Progress -Activity "Gathering Objects" -Completed
            $OutputObject
        }
    }
}