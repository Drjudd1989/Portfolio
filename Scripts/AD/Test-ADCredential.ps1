function Test-PDADCredential {
    <#
    .Synopsis
       Tests an Active Directory credential.
    .DESCRIPTION
       Tests an Active Directory credential..
    .PARAMETER Credential
        A Credential object from Get-Credential.
    .EXAMPLE
        Test-PDADCredential -credential (Get-Credential)

        Prompts for a credential object and will test if that credential object is valid or not.
    #>

    [CmdletBinding()]
    [OutputType('System.Boolean')]
    Param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [pscredential]$Credential
    )
    BEGIN {
            
        Add-Type -AssemblyName 'System.DirectoryServices.Protocols' -ErrorAction 'SilentlyContinue'
        $messageHeader      = '[{0}]' -f $MyInvocation.MyCommand
        $noDomainRegex      = '^(?<UserName>\w+)$'
        $netBiosDomainRegex = '^(?<Domain>\w+)\\(?<UserName>\w+)$'
        $preDomainRegex     = '^(?<Domain>(?:\w+\.)+\w+)\\(?<UserName>\w+)$'
        $sufDomainRegex     = '^(?<UserName>\w+)@(?<Domain>(?:\w+\.)+\w+)$'
        function ConvertTo-DistinguishedName {
            Param ([string]$Domain)
            $domainArray = $Domain.Split('.')
            $domainDN    = ($domainArray | ForEach-Object { 'DC={0}' -f $_ }) -Join ','
            Write-Output -InputObject $domainDN
        }
        #region domainlist
        $DomainList = 'contoso.com','ad.contoso.com','contoso1.dev'
        #endregion end domainlist
        function ConvertFrom-NetBiosDomainName {
                
            Param ([String]$Domain)
            switch ($Domain) {
                'CON'        {'contoso.com'}
                'ADC'        {'ad.contoso.com'}
                'CONDEV'     {'contoso1.dev'}

                default      {throw "$Domain is not implemented."}
            }
        }
    }
    PROCESS {
        if ([string]::IsNullOrEmpty($Credential.GetNetworkCredential().Password)) {
            
            Write-Output -InputObject $false
            throw "$messageHeader The password for $($Credential.UserName) is blank. Please ensure that your password is present and valid."
        }
        switch -Regex ($Credential.UserName) {
            $noDomainRegex { 
                # No domain was specified in the username, so the current domain is used.
                $userName = $Matches.UserName
                $domain   = $env:USERDNSDOMAIN
            }
                    
            $netBiosDomainRegex { 
                $userName = $Matches.UserName
                $domain   = ConvertFrom-NetBiosDomainName -Domain $Matches.Domain
            }
            $preDomainRegex { 
                $userName = $Matches.UserName
                $domain   = $Matches.Domain
            }
            $sufDomainRegex {
                $userName = $Matches.UserName
                $domain   = $Matches.Domain
            }
            default {
                Write-Output -InputObject $false
                throw 'Invalid Username format'
            }
        }
        if ($Domain -in $DomainList){
            $reformattedCredential = [pscredential]::new("$userName@$domain",$Credential.Password)
            $connection            = New-Object System.DirectoryServices.Protocols.LDAPConnection($domain)
            $connection.AuthType   = 'Basic'
            $connection.Credential = $reformattedCredential
            try{
                $connection.Bind();
                Write-Output -InputObject $true
            }
            catch{
                Write-Output -InputObject $false
                Write-Error -Message "$messageHeader $_"
            }
            $connection.Dispose()
        }
        Else{Throw "$Domain is not implemented"}  
    }
}