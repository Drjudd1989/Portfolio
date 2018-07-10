Function Get-PatchStatus {    
<#
.SYNOPSIS
Gets the update status of all computers in one or more groups.
.DESCRIPTION
Gets the update status of all computers in one or more groups.
.PARAMETER ComputerName
List one or more Computers to check into WSUS. Must use the Fully Qualified Domain Name. Ex: TESTSERVER001.contoso.dev
.PARAMETER WSUSGroup
List one or more WSUS Groups to check in.
.PARAMETER Server
Specify which WSUS Server will be used.
.EXAMPLE
Get-PatchStatus -Server WSUS.contoso.dev -Computername TESTSERVER001.contoso.dev

Gets update status for TESTSERVER001.contoso.dev.
.EXAMPLE
Get-PatchStatus -Server WSUS.contoso.dev -WSUSGroup "Unassigned Computers"

Gets update status for all Computers in the "Unassigned Computers" WSUS Group.
.NOTES
There is a bug in Powershell right now that causes Dynamic Parameters not to display correctly in help files. Because of this, the WSUSGROUP parameter does not display correctly. Here is the description:
    
    -WSUSGroup <String[]>
        List one or more WSUS Groups to check in. Groups that have subgroups will force all subgroups to check in.
        
        Required?                    false
        Position?                    named
        Default value                
        Accept pipeline input?       false
        Accept wildcard characters?  false

It is important to note that Powershell will not automatically pull a list of all available wsus groups unless you have already specified the Server parameter. When running this command, always specify the Server parameter first. It is also important to note that you can not specify both the WSUSGroup parameter and the ComputerName Parameter at the same time.
#> 
    [CmdletBinding()]
    Param (
        [String]$Server,
        [Parameter(ParameterSetName='Computer')]
        [String[]]$ComputerName,
        [Switch]$ExcludeFullyPatched
    )
    
    DynamicParam {
        # This is where the WSUSGroup Dynamic Parameter is specified.
        If (!($ComputerName)){
            Add-Type @"
    public class DynParamQuotedString {
 
        public DynParamQuotedString(string quotedString) : this(quotedString, "\"") {}
        public DynParamQuotedString(string quotedString, string quoteCharacter) {
            OriginalString = quotedString;
            _quoteCharacter = quoteCharacter;
        }
 
        public string OriginalString { get; set; }
        string _quoteCharacter;
 
        public override string ToString() {
            //if (OriginalString.Contains(" ")) {
                return string.Format("{1}{0}{1}", OriginalString, _quoteCharacter);
            //}
            //else {
            //    return OriginalString;
            //}
        }
    }
"@
            If (!($Server)){
                $WSUSServer = Switch -Wildcard ($env:COMPUTERNAME) {
					"DEV*" {"wsus.contoso.dev"}
					"Test*" {"wsus.contoso.Test"}
					"DR*" {"wsus.contoso.DR"}
					"PROD*" {"wsus.contoso.com"}
                }
            }Else{
                $WSUSServer = $Server
            }
            $WSUSPort = If ($WSUSServer -match '^wsus.*$'){80}ElseIf($WSUSServer -match '^wsus.contoso.test$'){8530}Else{8531}
            $WSUSHTTPS = If ($WSUSPort -eq 80 -or $WSUSPort -eq 8530){$False}Else{$True}


            # Grab the WSUSGroups Here and store them in an array
            $WSUSGroupValues = $(([reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null);($WSUS = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($WSUSServer,$WSUSHTTPS,$WSUSPort));($WSUS.GetComputerTargetGroups() | Select -ExpandProperty Name))

            # Set the above array as a ValidateSet object
            $ValidateSet = new-object System.Management.Automation.ValidateSetAttribute(($WSUSGroupValues | ForEach {[DynParamQuotedString[]] $_.ToString()}))

            # Set the '[Parameter()] values here'
            $WSUSGroupAttribute = New-Object System.Management.Automation.ParameterAttribute
            $WSUSGroupAttribute.ParameterSetName = "WSUSGroup"

            # Apply all the above attributes of a Parameter to an attribute collection
            $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $AttributeCollection.Add($WSUSGroupAttribute)
            $AttributeCollection.Add($ValidateSet)

            # Set the Parameter object using the above attribute collection
            $WSUSGroupParameter = New-Object System.Management.Automation.RuntimeDefinedParameter("WSUSGroup", [DynParamQuotedString[]], $AttributeCollection)

            # Add the Parameter to a collection of parameters
            $ParamDictionary = new-object System.Management.Automation.RuntimeDefinedParameterDictionary
            $ParamDictionary.Add("WSUSGroup",$WSUSGroupParameter)

            # Present the Parameter to the system
            Return $ParamDictionary
        }
    }

    Begin {

        If (!($Server)){
            $WSUSServer = Switch -Wildcard ($env:COMPUTERNAME) {
                "DEV*" {"wsus.contoso.dev"}
                "Test*" {"wsus.contoso.Test"}
                "DR*" {"wsus.contoso.DR"}
                "PROD*" {"wsus.contoso.com"}
            }
        }Else{
            $WSUSServer = $Server
        }
        $WSUSPort = If ($WSUSServer -match '^wsus.*$'){80}ElseIf($WSUSServer -match '^wsus.contoso.test$'){8530}Else{8531}
        $WSUSHTTPS = If ($WSUSPort -eq 80 -or $WSUSPort -eq 8530){$False}Else{$True}

        # Load the WSUS library and set the WSUS Server
        [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
        $WSUS = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($WSUSServer,$WSUSHTTPS,$WSUSPort)

        # The way you access a dynamic parameter is a little wonky, so this puts the value from the parameter into an easier-to-deal-with variable
        If ($ParamDictionary.WSUSGroup.Value){
            $WSUSGroup = $ParamDictionary.WSUSGroup.Value.OriginalString
        }

        $GroupIDDatabase = @{}
        $GroupDatabase = @{}
        $WSUS.GetComputerTargetGroups() | ForEach{$GroupIDDatabase.Add($_.Name,$_.ID);$GroupDatabase.Add($_.ID,$_.Name)} 
        
        $NeededDatabase = @{}
        $FailedDatabase = @{}
        $Wsus.GetSummariesPerComputerTarget((New-Object Microsoft.UpdateServices.Administration.UpdateScope),([Microsoft.UpdateServices.Administration.ComputerTargetScope]@{IncludeDownstreamComputerTargets = $True;IncludeSubgroups = $True})) | ForEAch {$NeededDatabase.Add($_.ComputerTargetID,$_.NotInstalledCount);$FailedDatabase.Add($_.ComputerTargetID,$_.FailedCount)}

        $DuplicationCatch = @{}

        $Objects = @()

        # This is the recursive function that lets us specify subgroups of a larger group
        Function Get-WSUSRecursiveGroups {
            Param (
                [String]$Group,
                [Microsoft.UpdateServices.Internal.BaseApi.UpdateServer]$WSUS
            )
            # I found that I had to pull a list of all groups several times. Instead, I ended up just pulling them one time here, and then using this list instead of pounding WSUS with requests.
            $AllGroups = $WSUS.GetComputerTargetGroups()

            # Return the name of the current group
            $Group

            # If this group has subgroups
            If (($AllGroups | Where {$_.Name -eq $Group}).GetChildTargetGroups()){
                # Get the names of all the subgroups
                $Groups = ($AllGroups | Where {$_.Name -eq $Group}).GetChildTargetGroups() | Select -Expand Name
                ForEach ($G in $Groups) {
                    # For every subgroup that was discovered, run the function again on each of those groups. This will run over and over again untill no more subgroups are found in your target.
                    Get-WSUSRecursiveGroups -Group $G -WSUS $WSUS
                }
            }
        }
        
    }

    Process {
        # Trying to resolve the specified WSUS Group 
        Try{
            # If a WSUSGroup was specified and not a Computername, then...
            If ($WSUSGroup) {
                $ComputerName = @()

                # We want to get all the sub groups of all specified WSUSGroups, We will need that recursive function here.
                $WSUSGroup = $WSUSGroup | ForEach {Get-WSUSRecursiveGroups -Group $_ -WSUS $WSUS}
                $WSUSGroup = $WSUSGroup | Where {$_ -ne "All Computers"}
            }
            # If ComputerName was specified instead of WSUSGroup...
            ElseIf ($ComputerName) {
                # We dont do anything, because we already have our list of ComptuerNames.
            }
        }
        Catch {
            # If an error were to occur, that means that WSUS was not able to do anything with the group name provided, because it's wrong.
            Throw "Invalid WSUSGroup(s)"
        }

        If ($WSUSGroup) {
            ForEach ($Group in $WSUSGroup) {
                $Computers = $WSUS.GetComputerTargetGroup(($GroupIDDatabase[$Group])).GetComputerTargets()
                ForEach ($C in $Computers) {
                    Try {
                        $DuplicationCatch.Add($C,$True)
                    }
                    Catch{
                        Continue
                    }

                    $Objects += [pscustomobject]@{
                        ComputerName = $C.FullDomainName
                        Group = $C.ComputerTargetGroupIds | ForEach {$GroupDatabase[$_] | Where {$_ -ne "All Computers"}}
                        Needed = $NeededDatabase[$C.ID]
                        Failed = $FailedDatabase[$C.ID]
                        LastSync = $(Try{($C.LastReportedStatusTime) - (New-TimeSpan -Hours 5)}Catch{"Not Yet Reported"})
                        OperatingSystem = $C.OSDescription
                    }
                }
            }
        }
        Else {
            # For Every Computer in our list...
            ForEach ($Computer in $ComputerName){
                # If WSUS can't find a one of the ComputerNames, we will throw an error.
                Try {
                    $WSUSComp = $WSUS.GetComputerTargetByName($Computer)
                }
                Catch {
                    Throw "$Computer is an invalid ComputerName"
                }
                
                $WSUSComp | ForEach {
                    $Objects += [pscustomobject]@{
                        ComputerName = $_.FullDomainName
                        Group = $_.ComputerTargetGroupIds | ForEach {$GroupDatabase[$_]}
                        Needed = $NeededDatabase[$_.ID]
                        Failed = $FailedDatabase[$_.ID]
                        LastSync = $(Try{($_.LastReportedStatusTime) - (New-TimeSpan -Hours 5)}Catch{"Not Yet Reported"})
                        OperatingSystem = $_.OSDescription
                    }
                }
            } #ForEach
        }
    }

    End {
        If ($ExcludeFullyPatched -eq $True){
            $Objects | where {$_.Needed -ne 0 -or $_.Failed -ne 0} | Sort Group,Computername -Unique
        }
        Else {
            $Objects | Sort Group,Computername -Unique
        }
    }
}