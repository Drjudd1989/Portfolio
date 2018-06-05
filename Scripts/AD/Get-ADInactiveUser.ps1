asdasdasdFunction Get-ADInactiveUser {
    [CmdletBinding(
        PositionalBinding=$false
    )]

    Param (
        [string]$Server = (Get-ADDomain).DNSRoot,

        [int]$DaysInactive = 30,

        [PSCredential]$Credential
    )

    Begin {
        # Ensuring that specified credentials are valid or the function is stopped
        If ($Credential -ne $Null) {
            If ((Test-ADCredential -Credential $Credential -Quiet) -eq $false) {
                Write-Error -Message "$($Credential.UserName) is not valid. Please ensure that you username and/or password is correct." -ErrorAction Stop
            }
        }

        # Retrieving the SearchBase for the specified server/domain
        $DNParam = @{
            Server = $Server
        }
        If ($Credential -ne $Null) {$DNParam.Add('Credential',$Credential)}
        $SearchBase = 'OU=Accounts - Elevated Users,OU=Administrative Objects,OU=Server Administration,' + (Get-ADDomain @DNParam).DistinguishedName

        # Based on the number of days inactive specified, I am saving the specific resulting date for filtering off of
        $CutoffDate = (Get-Date).AddDays(-$DaysInactive)
    }

    Process {
        Write-Progress -Activity "Getting Inactive Elevated Users" -Status "Performing Lookup"
        # Getting users that are expired as per the replicated value
        $UserParam = @{
            Server = $Server
            SearchBase = $SearchBase
            SearchScope = 'Subtree'
            Properties = 'LastLogonDate'
            Filter = "(LastLogonDate -lt `"$($CutoffDate.ToString())`") -or (-not(LastLogonDate -like `"*`"))"
        }
        If ($Credential -ne $Null) {$UserParam.Add('Credential',$Credential)}
        $Users = Get-ADUser @UserParam | Sort SamAccountName

        # Processing Each User
        $i = 0
        Foreach ($User in $Users) {
            Write-Progress -Activity "Getting Inactive Elevated Users" -Status "Checking $i of $($Users.Count) `($($User.SAMAccountName)`)" -PercentComplete $(($i/$Users.Count)*100)
            
            # Finding correct LastLogon date for each user
            $LastLogonParam = @{
                Identity = $User.SamAccountName
                Server = $Server
            }
            If ($Credential -ne $Null) {$LastLogonParam.Add('Credential',$Credential)}
            $UserLastLogon = Get-ADUserLastLogon @LastLogonParam

            # Ensuring each user's LastLogon date is filtered per the DaysInactiveParameter and returning results
            If ($UserLastLogon.DaysSinceLastLogon -ge $DaysInactive) {
                [PSCustomObject]@{
                    SamAccountName = $User.SamAccountName
                    Name = $User.Name
                    LastLogonDate = If(($User.LastLogonDate)){$User.LastLogonDate}Else{get-date -Date 1900-01-01}
                    LastLogon = $UserLastLogon.LastLogon
                    DaysSinceLastLogon = $UserLastLogon.DaysSinceLastLogon
                    Disabled = !($User.Enabled)
                }
            }
            $i++
        }
        Write-Progress -Activity "Getting Inactive Elevated Users" -Completed
    }
}