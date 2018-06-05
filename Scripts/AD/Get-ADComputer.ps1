<#
.SYNOPSIS
Gets a list of all Active Directory Computers within a specified domain.
.DESCRIPTION
Gets a list of all Active Directory Computers within a specified domain. Results are filtered by objects that are Windows Servers, Enabled, Within the "Server Administration" OU, and not in the "Non-Windows" OU. If no domain is specified, it will run on the local domain of the computer you are running the command from. 
.PARAMETER Domain
Specify the domain to grab the computer list from. If no domain is specified, it will default to the domain of the local computer.
.PARAMETER Environment
If PROD, this will filter out results and only display the computers from the Environment selected.
.EXAMPLE
Get-ADComputer

Outputs a list of all of the Windows Computer objects in the domain of the local computer. 
.EXAMPLE
Get-ADComputer -domain contoso.com

Outputs a list of all of the Windows Computer objects in contoso.com.
.EXAMPLE
Get-ADComputer -domain contoso.com -environment US

Outputs a list of all of the Windows Computer objects with US in the name in contoso.com
.EXAMPLE
Get-ADComputer | out-file c:\temp\Computers.txt

Gets a list of all of the Windows Computer objects in the domain of the local computer out outputs it to a Text file located in C:\Temp (C:\Temp\Computers.txt) on the local machine.
.INPUTS
None. This Cmdlet does not accept any pipeline input.
.OUTPUTS
System.String
#>

function Get-ADComputer {
    Param (
        $Domain = (Get-ADDomain).DNSRoot,
        
        [ValidateSet('US','CA','All')]
        $Environment = 'All'
    )
    
    Process {
        $ServerAdministrationOU = Get-ADOrganizationalUnit -Filter {Name -eq "Server Administration"} -Server $Domain | Select -ExpandProperty DistinguishedName
        $Servers = Get-ADComputer -Filter {(OperatingSystem -like '*Windows Server*') -and (Enabled -eq $True)} -SearchBase $ServerAdministrationOU -SearchScope Subtree -Server $Domain | Where-Object {$_.DistinguishedName -notlike '*Non-Windows*'} | Select -ExpandProperty DNSHostName

        Switch ($Environment) {
            US {$Servers | Where {$_ -like 'US*'} | Sort-Object}
            CA {$Servers | Where {$_ -notlike 'CA*'} | Sort-Object}
            All {$Servers | Sort-Object}
        }
    }
}