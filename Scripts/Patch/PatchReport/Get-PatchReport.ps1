<#
.SYNOPSIS
Gets a report of WSUS.
.DESCRIPTION
Gets a report of WSUS. Depending on which view is selected, the report changes.
.PARAMETER Server
Specify the WSUS server that you are pulling the report from.
.PARAMETER ComputerName
Specify one or more computers to get the report for. By default, all computers in WSUS are included.
.PARAMETER WSUSGroup
Specify one or more WSUS groups to get the report for. Computers in the wsus groups are targeted. By default, the root group is selected, which includes all computers in the targeted WSUS server.
.PARAMETER View
Changes the report type depending on which view is selected.

Summary:
    This is the default view. For each of the severity categories of updates, It lists how many computers have at least 1 update in that severity category. This report view is requested by the CISO monthly for all WSUS servers.

PerComputer:
    This report lists all the KB Articles that are missing from at least 1 server. It specifies how many computers are missing it.

PerUpdate:
    This report lists all computers and how many updates they are missing from each update severity category.

.EXAMPLE
Get-PatchReport

Gets a report using the default Summary view for the WSUS server of the environment that you are in.
.EXAMPLE
Get-PatchReport -Server wsus.contoso.dev -View PerComputer

Gets a report using the PerComputer view for the contoso.dev WSUS Server.
.EXAMPLE
Get-PatchReport -View PerUpdate -Computername script201.contoso.dev,script202.contoso.dev,script203.contoso.dev,script204.contoso.dev

Gets a report using the PerUpdate view for the WSUS server of the environment that you are in. This report only includes information for script201.contoso.dev, script202.contoso.dev, script203.contoso.dev, and script204.contoso.dev.
.EXAMPLE
Get-PatchReport -View PerUpdate -Computername (Get-ADComputer -Filter {SamAccountName -like '*sql*'} | Select -ExpandProperty DNSHostName)

Gets a report using the PerUpdate view for the WSUS server of the environment that you are in. This report only includes computers that have 'SQL' in the name.
.INPUTS
.OUTPUTS
pscustomobject
pscustomobject
pscustomobject
.NOTES
Because the WSUSGroup is a dynamic parameter, it doesnt show up in the help file correctly, so here is the entry for it.

Get-PatchReport [-Server <String>] [-WSUSGroup <String[]>] [-View <String>] [<CommonParameters>]

-WSUSGroup <String[]>
        
    Required?                    false
    Position?                    named
    Default value                'All Computers'
    Accept pipeline input?       false
    Accept wildcard characters?  false
#>
Function Get-PatchReport{
    [CmdletBinding(DefaultParameterSetName='WSUSGroup')]
    Param
    (
        [ValidateSet("pdwsus001.contoso.com","cgwsus001.contoso.com","wsus.contoso.dev","wsus.contoso.qalab","wsus.contoso.qf")]
        [String]$Server,

        [Parameter(ParameterSetName='Computer')]
        [String[]]$ComputerName,

        [ValidateSet("PerComputer","PerUpdate","Summary")]
        [String]$View = "Summary"
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
            $WSUSGroupParameter.Value = [DynParamQuotedString[]] 'All Computers'

            # Add the Parameter to a collection of parameters
            $ParamDictionary = new-object System.Management.Automation.RuntimeDefinedParameterDictionary
            $ParamDictionary.Add("WSUSGroup",$WSUSGroupParameter)

            # Present the Parameter to the system
            Return $ParamDictionary
        }
    } #DynamicParam

    Begin
    {

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

        [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
        $WSUS = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($WSUSServer,$WSUSHTTPS,$WSUSPort)

        $Environment = Switch ($WSUSServer) {
			"DEV*" {"wsus.contoso.dev"}
			"Test*" {"wsus.contoso.Test"}
			"DR*" {"wsus.contoso.DR"}
			"PROD*" {"wsus.contoso.com"}
        }

        If ($ParamDictionary.WSUSGroup.Value){
            $WSUSGroup = $ParamDictionary.WSUSGroup.Value.OriginalString
        }


        If ($WSUSGroup) {
            $ComputerName = @()
            $ComputerName = Get-PatchStatus -WSUSGroup $WSUSGroup -Server $WSUSServer -ExcludeFullyPatched | Select -Expand Computername
        }
        # If ComputerName was specified instead of WSUSGroup...
        ElseIf ($ComputerName) {
            # We dont do anything, because we already have our list of ComptuerNames.
        }

        $Computername = $ComputerName | select -Unique | Sort
    } #Begin

    Process
    {

        $WsusComputers = $Computername  | Foreach {$Wsus.GetComputerTargetByName($_)}

        If ($View -eq "PerComputer") {
            $Results = @()

            ForEach ($Computer in $WsusComputers){
                $UpdateGUIDs = $Computer.GetUpdateInstallationInfoPerUpdate() | where {$_.UpdateInstallationState -eq 'NotInstalled'} | Select -Expand UpdateID
                $Updates = $UpdateGUIDs | Foreach {$WSUS.GetUpdate($_)}
               
                $Result = [pscustomobject]@{
                    Computername = $Computer.FullDomainName
                    Critical = ($Updates | select -expand MsrcSeverity | where {$_ -eq 'Critical'}).Count
                    Important = ($Updates | select -expand MsrcSeverity | where {$_ -eq 'Important'}).Count
                    Moderate = ($Updates | select -expand MsrcSeverity | where {$_ -eq 'Moderate'}).Count
                    Low = ($Updates | select -expand MsrcSeverity | where {$_ -eq 'Low'}).Count
                    Unspecified = ($Updates | select -expand MsrcSeverity | where {$_ -eq 'Unspecified'}).Count
                }  

                $Results += $Result
            }


        }
        ElseIf($View -eq "PerUpdate"){
            $UpdateGUIDs = $WsusComputers | Foreach {$_.GetUpdateInstallationInfoPerUpdate() | where {$_.UpdateInstallationState -eq 'NotInstalled'}} | Select -Expand UpdateID -Unique
            $Updates = $UpdateGUIDs | Foreach {$WSUS.GetUpdate($_)}
            $Results = @()

            ForEach ($Update in $Updates) {


                $Result = [pscustomobject]@{
                    Update = ($Update.KnowledgebaseArticles | ForEach {"KB" + $_}) -Join ', '
                    Severity = $Update.MsrcSeverity
                    Classification = $Update.UpdateClassificationTitle
                    ComputersNeeded = $Update.GetSummaryPerComputerTargetGroup() | Select -Expand NotInstalledCount | Measure -Sum | Select -Expand Sum
                }

                $Results += $Result
            }

            $Results = $Results | Sort Severity | Sort ComputersNeeded -Descending
        }
        ElseIf($View -eq "Summary") {
            $Critical = 0
            $Important = 0
            $Moderate = 0
            $Low = 0
            $Unspecified = 0
            
            ForEach ($Computer in $WSUSComputers) {
                $UpdateGUIDs = $Computer | Foreach {$_.GetUpdateInstallationInfoPerUpdate() | where {$_.UpdateInstallationState -eq 'NotInstalled'}} | Select -Expand UpdateID -Unique
                $Updates = $UpdateGUIDs | Foreach {$WSUS.GetUpdate($_)}

                Switch -Regex (($Updates | Select -Expand MsrcSeverity -Unique)) {
                    'Critical' {$Critical++}
                    'Important' {$Important++}
                    'Moderate' {$Moderate++}
                    'Low' {$Low++}
                    'Unspecified' {$Unspecified++}
                }

            }

            $Results = [pscustomobject]@{
                Environment = $Environment
                Critical = $Critical
                Important = $Important
                Moderate = $Moderate
                Low = $Low
                Unspecified = $Unspecified
                TotalVulnerableComputers = $WsusComputers.Count
                TotalComputers = (Get-WSAPatchStatus -WSUSGroup $WSUSGroup -Server $WSUSServer).count
            }
        }

    } #Process

    End
    {
        $Results
    } #End
}