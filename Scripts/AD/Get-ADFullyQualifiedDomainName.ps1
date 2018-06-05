<#
.SYNOPSIS
Gets Fully Qualified Computer names from non-FQDN computer names.
.DESCRIPTION
Gets Fully Qualified Computer names from non-FQDN computer names.
.PARAMETER Name
Input single or multiple Computer names.
.PARAMETER DomainFilter
Allows for the filtering of the search to a single domain.
.EXAMPLE
Get-ADFullyQualifiedDomainName -name contoso1

Returns the fully qualified domain name for contoso1
.EXAMPLE
Get-ADFullyQualifiedDomainName -name contoso1,contoso2,contoso3

Returns the fully qualified domain name for contoso1,contoso2,contoso3
.EXAMPLE
Get-ADFullyQualifiedDomainName -name (get-content c:\temp\Serverlist.txt)

Gets the content from a list of servers within a text document and Returns the fully qualified domain names.
.EXAMPLE
Get-ADFullyQualifiedDomainName -name contoso -domainfilter contoso.com

Returns the fully qualified domain name for all servers in contoso.com with contoso in the name.
.INPUTS
System.String[]
.OUTPUTS
System.String
#>

function Get-ADFullyQualifiedDomainName {
    [CmdletBinding(
        #DefaultParameterSetName='Parameter Set 1', 
        #SupportsShouldProcess=$true, 
        #HelpUri = 'http://www.microsoft.com/',
        #ConfirmImpact='Medium'
        PositionalBinding=$false
    )]

    Param (
        [Parameter(
            Mandatory=$true,
            Position=0,
            ValueFromPipelineByPropertyName=$true,
            ValueFromPipeline=$true
        )]
        [ValidateLength(1,16)]
        [String[]]$Name,

        #Parameter to allow filtering of domains
        [string[]]$DomainFilter
    ) #Param

    Begin {
        $Domains = @()

        Try {
            Import-Module -Name ActiveDirectory -Cmdlet Get-ADTrust,Get-ADComputer -ErrorAction Stop
        }
        Catch{
            Write-Error -ErrorAction Stop -Message 'Please ensure that the ActiveDirectory module is installed and try again.'
        }
        #If DomainFilter Parameter is not specified
        If(!($DomainFilter)){
            $Domains = Get-ADTrust -Filter * | where {$_.Direction -Match '^(Inbound|BiDirectional)$'} | Select -ExpandProperty Name
            $Domains += Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain
        } #End If
        Else{
            #Domain Filter Specified
            $Domains = $DomainFilter
            #Gathering trusted domains
            $Trusted = Get-ADTrust -Filter * | where {$_.Direction -Match '^(Inbound|BiDirectional)$'} | Select -ExpandProperty Name
            $Trusted += Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain
            #Checking each Domain specified in the filter against the list of trusted domains
            Foreach($Domain in $Domains){
                If($Trusted -notcontains $Domain){
                    #Upon finding one that does not match, stop the script with the specified error.
                    Write-Error -ErrorAction Stop -Message "The specified Domain ($Domain) is not trusted from the local domain"
                }
            }
        } #End Else
    } #Begin

    Process {
        Foreach ($N in $Name){
            Foreach ($Domain in $Domains){
            
                Try {
                    $N = "*$N*"
                    Get-ADComputer -Server $Domain -Filter {Name -like $N} -ErrorAction Stop | Select-Object -ExpandProperty DNSHostName 
                }
                Catch {

                }
            }
        }
    } #Process

    End {

    } #End
}

New-Alias -Name GFQDN -Value Get-ADFullyQualifiedDomainName -Description 'Get-ADFullyQualifiedDomainName' -Option AllScope