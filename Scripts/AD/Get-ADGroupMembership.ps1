<#
.SYNOPSIS
Gets a list of all memberships that an User Account belongs too across all trusted domains.
.DESCRIPTION
Performs a recursive lookup to obtain all memberships of an User Account across all trusted domains, including memberships of those memberships, and so on.
.PARAMETER Name
SAMAccountName to gather memberships for. For Managed Service Accounts, be sure to include the $ at the end.
.PARAMETER Server
Specify domain in which the User Account is in.
.EXAMPLE
Get-ADGroupMembership -name testuser -Server contoso.qalab

Outputs a listing of all of the memberships that the user "testuser" belongs to.
.EXAMPLE
Get-ADGroupMembership -name testuser -Server contoso.qalab | export-csv c:\temp\Memberships.csv

Outputs a listing of all of the memberships that the user "testuser", which lives in contoso.qalab, belongs to to a CSV file located in C:\Temp (C:\temp\Memberships.csv) on the local machine
.EXAMPLE
Get-ADGroupMembership -name GMSA$ -Server contoso.dev

Outputs a listing of all of the memberships that the Group Managed Service Account "GMSA$" in contoso.dev belongs too.
.INPUTS
None. This Cmdlet does not accept any pipeline input.
.OUTPUTS
pscustomobject
#>

Function Get-ADGroupMembership {
    Param(
        [Parameter(Mandatory = $True)]
        [string]$Name,
        #[Parameter(Mandatory = $True)]
        [string]$Server = $((Get-ADDomain).Forest)
    ) #Param

    Begin {
    } #Begin

    Process {
        
        #Function to get Member ofs for the same domain. Recursive Lookup that pulls all member ofs 
        Function Get-ADPrincipalGroupMembership{
            Param(
                $Server,
                $Identity
            ) #Param

                $Status = "Checking $Identity in $Server"
                Write-Progress -Activity "Retrieving Memberships" -Status $Status
                
                $ADGroups = Get-ADPrincipalGroupMembership -Server $Server -Identity $Identity -ErrorAction SilentlyContinue | select samaccountname,sid,GroupScope | Where-Object {$_.SamAccountName -notlike '*Domain*Users*' -and $_.SamAccountName -notlike'RBA_DenyLogon_SVC' -and $_.SamAccountName -notlike 'FGPP*'} 
                If($ADGroups -ne $Null){
                    foreach($ADGroup in $ADGroups){
                        [.AD.GroupMembership]@{
                            MemberOf = $ADGroup.samaccountname
                            Domain = $Server
                            SID = $ADGroup.SID
                            GroupScope = $ADGroup.Groupscope
                            ChildItem = $Identity 
                        } #End System Object
                        Get-ADPrincipalGroupMembership -Server $Server -Identity $ADGroup.samaccountname
                    } #End Foreach ADGroup
                } #End If ADGroups 
            } # ADPrincipalGroupMembership Function

        #Recursive lookup for initial set of groups pulled
        Function RecursiveLookup{
            Param(
                $Server,
                $Name,
                $SID
            ) #Param

            $SIDs = @($SID)
            #Begin Cross Domain lookup
            Foreach($SID in $SIDS){

                #Pull list of inbound and biderictional trusts to use for group checking
                $Domains = Get-ADTrust -Filter {Direction -ne "Outbound"} -Server $Server | select -ExpandProperty name
                Foreach($Domain in $Domains){
                    #Progress Display
                    $Status = "Checking $Identity in $Server"
                    Write-Progress -Activity "Retrieving Memberships" -Status $Status
                    #Check the group on the specified domain for a group that has it's SID as a member filtering for only our OU (Search Base can be removed for full domain search)
                    $Groups3 = Get-ADGroup -SearchBase "OU=Server Administration,DC=$($Domain -replace "\.",",DC=")" -filter * -Properties Members,GroupScope -Server $Domain | Where-Object {$_.Members -like "*$($SID)*"} | select samaccountname,Sid,GroupScope #| select SamAccountName #{[PSCustomObject]@{Name = $_.Name; SAMAccountName = $_.SAMAccountName; DistinguishedName = $_.DistinguishedName; SID = $_.SID; PSTypeName = 'System..AD.ADObject'}}    
                    Foreach($Group3 in $Groups3){
                        [.AD.GroupMembership]@{
                                MemberOf = $Group3.samaccountname
                                Domain = $Domain
                                SID = $Group3.Sid
                                GroupScope = $Group3.Groupscope 
                                ChildItem = $Name
                        } #End System Object
                            Try{
                                #Recursively check each Group for any Group Memberships
                                $LocalDomains = Get-ADPrincipalGroupMembership -Server $Domain -Identity $Group3.SamaccountName
                                If($LocalDomains -ne $Null){
                                    foreach($LocalDomain in $LocalDomains){
                                        [.AD.GroupMembership]@{
                                            MemberOf = $LocalDomain.MemberOf
                                            Domain = $Domain
                                            SID = $LocalDomain.SID
                                            GroupScope = $LocalDomain.Groupscope 
                                            ChildItem = $Group3.samaccountName
                                        }
                                        #Go back to the top for any global groups that are found
                                        If ($LocalDomain.GroupScope -eq "Global"){
                                            RecursiveLookup -Name $LocalDomain.MemberOf -Server $Domain -SID $LocalDomain.sid
                                        } #End If lookup
                                    } # End Foreach LocalDomain
                                } #End If LocalDomains not Null
                            } #End Try
                            Catch{
                                Continue
                            }
                            
                        #Go back to the top for any global groups that are found
                        If ($Group3.GroupScope -eq "Global"){
                            RecursiveLookup -Name $Group3.samaccountname -Server $Domain -SID $Group3.sid.Value 
                        }
                            
                    } #Foreach($Group3 in $Groups3)
                } #Foreach($Domain in $Domains)
            } #Foreach($SID in $SIDS)   
        } #Recursivelookup Function

            #Start of the script - Will recursively grab the memberships for the user in the same domain
            $Groups = Get-ADPrincipalGroupMembership -Server $Server -Identity $name
            #Output of initial Domain Local groups found
            $Groups
            Foreach($Group in $Groups){ 
                #Begins Recursive Lookup for each group that the user belongs to
                If($Group.GroupScope -eq "Global"){
                    RecursiveLookup -Server $Server -Name $Group.MemberOf -SID $Group.Sid
                } #End If Groupscope equal Global
            } #End Foreach Group
        Write-Progress -Activity "Retrieving Memberships" -Completed

    } #Process

    End {
    } #End
       
} #Function




