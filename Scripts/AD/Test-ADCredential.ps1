<#
.SYNOPSIS
Test Active Directory User or Service Account
.DESCRIPTION
Test Active Directory User or Service Account
.PARAMETER Credential
Enter a Credential object to test
.PARAMETER Quiet
Output only a true or false value
.EXAMPLE
Test-ADCredential -credential (get-credential)

Pops up a box to allow credentials to be specified for testing.
.EXAMPLE
Test-ADCredential -credential (get-credential) -quiet

Pops up a box to allow credentials to be specified for testing then outputs a true or false value depending on if the credentials are valid or not.
.INPUTS
None. This Cmdlet does not accept any pipeline input.
.OUTPUTS
System.Management.Automation.PSCustomObject
#>

function Test-ADCredential {
    Param (
        [PSCredential]$Credential,
        [Switch]$Quiet

    )

    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    Switch -Regex ($Credential.UserName) {
        '^(netbios\w+)\\(.*)$' {
            $Domain = Get-ADDomain -Identity $Matches[1] | Select -ExpandProperty DNSRoot
            $UserName = $Matches[2]

            $DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain',$Domain)
            $Result = $DS.ValidateCredentials($UserName, $Credential.GetNetworkCredential().Password)
            
            If ($Quiet) {
                $Result
            }
            Else {
                [PSCustomObject]@{
                    Username = $UserName.ToLower()
                    Domain = $Domain.ToLower()
                    Result = $Result
                }
            }
        }

        '^(netbios\w+\.\w+)\\(.*)$' {
            $Domain = $Matches[1]
            $UserName = $Matches[2]

            $DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain',$Domain)
            $Result = $DS.ValidateCredentials($UserName, $Credential.GetNetworkCredential().Password)

            If ($Quiet) {
                $Result
            }
            Else {
                [PSCustomObject]@{
                    Username = $UserName.ToLower()
                    Domain = $Domain.ToLower()
                    Result = $Result
                }
            }
        }

        '^(.*?)@(netbios\w+\.\w+)$' {
            $Domain = $Matches[2]
            $UserName = $Matches[1]

            $DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain',$Domain)
            $Result = $DS.ValidateCredentials($UserName, $Credential.GetNetworkCredential().Password)


            If ($Quiet) {
                $Result
            }
            Else {
                [PSCustomObject]@{
                    Username = $UserName.ToLower()
                    Domain = $Domain.ToLower()
                    Result = $Result
                }
            }
        }

        '^([^\\\.@]*)$' {
            $Domain = $env:USERDNSDOMAIN
            $UserName = $Matches[1]

            $DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain',$Domain)
            $Result = $DS.ValidateCredentials($UserName, $Credential.GetNetworkCredential().Password)


            If ($Quiet) {
                $Result
            }
            Else {
                [PSCustomObject]@{
                    Username = $UserName.ToLower()
                    Domain = $Domain.ToLower()
                    Result = $Result
                }
            }
        }
    }
}