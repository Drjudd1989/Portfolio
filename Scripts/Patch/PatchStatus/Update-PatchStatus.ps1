Function Update-PatchStatus {    
<#
.SYNOPSIS
Forces one or more clients to check into WSUS and pull updates.
.DESCRIPTION
Forces one or more clients to check into WSUS and pull updates. This can be done via a list of ComputerNames or via all computers in a specific WSUS Group. Although WSUSGroup does not appear in the help file under Parameters or Syntax, it is still part of the command.
.PARAMETER ComputerName
List one or more Computers to check into WSUS. Must use the Fully Qualified Domain Name. Ex: TESTSERVER001.contoso.dev
.PARAMETER WSUSGroup
List one or more WSUS Groups to check in.
.PARAMETER Server
Specify which WSUS Server will be used.
.PARAMETER ExcludeNotNeeded
Out of all the Computers listed, only Computers with patches needed in WSUS will check in. Be careful with this, Computers that never checked in before will count as not needed any patches.
.PARAMETER Repeat
This specifies the number of time the target Computers will check in.
.PARAMETER Interval
Time, in minutes, that will be waited inbetween repeats.
.EXAMPLE
Update-PatchStatus -Server WSUS001.contoso.dev -Computername TESTSERVER001.contoso.dev

Forces only TESTSERVER001.contoso.dev to check in.
.EXAMPLE
Update-PatchStatus -Server WSUS001.contoso.dev -Computername TESTSERVER001.contoso.dev -Repeat 5

Forces TESTSERVER001.contoso.dev to check in 5 times. The Default Interval of 10 minutes is used.
.EXAMPLE
Update-PatchStatus -Server WSUS001.contoso.dev -WSUSGroup "Unassigned Computers" -Repeat 8 -Interval 5

Forces all Computers in the "Unassigned Computers" WSUS Group to check in every 5 minutes for a total of 8 times.
.EXAMPLE
Update-PatchStatus -Server WSUS001.contoso.dev -WSUSGroup "Unassigned Computers","Even1" -Repeat 8 -Interval 5 -ExcludeNotNeeded

Forces only Computers in the "Unassigned Computers" and "Even1" WSUS Groups that need patches to check in every 5 minutes for a total of 8 times.
.EXAMPLE
Update-PatchStatus -Server WSUS001.contoso.dev -WSUSGroup "Monthly_Group1" -ExcludeNotNeeded

Forces Computers of the Monthly_Group1 group and all subgroups to check into WSUS only if they need patches.
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
        [Switch]$ExcludeFullyPatched,
        [Int32]$Repeat = 1,
        [Int32]$Interval = 10
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
            $WSUSPort = If ($WSUSServer -match '^(PD|CG)wsus001.*$'){80}ElseIf($WSUSServer -match '^wsus.contoso.test$'){8530}Else{8531}
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
        $WSUSPort = If ($WSUSServer -match '^contoso.*$'){80}ElseIf($WSUSServer -match '^wsus.contoso.com$'){8530}Else{8531}
        $WSUSHTTPS = If ($WSUSPort -eq 80 -or $WSUSPort -eq 8530){$False}Else{$True}

        # Load the WSUS library and set the WSUS Server
        [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
        $WSUS = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($WSUSServer,$WSUSHTTPS,$WSUSPort)

        # The way you access a dynamic parameter is a little wonky, so this puts the value from the parameter into an easier-to-deal-with variable
        If ($ParamDictionary.WSUSGroup.Value){
            $WSUSGroup = $ParamDictionary.WSUSGroup.Value.OriginalString
        }

        # Sometimes we need to specify a group by it's SID (It might even be just a GUID, Who knows.)
        Function ConvertTo-WSUSGroupSID {
            Param (
                [String]$GroupName
            )
            $WSUS.GetComputerTargetGroups() | Where {$_.Name -eq $GroupName} | select -Expand ID
        }
        
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
        
        $StartTime = Get-Date

        # Have to convert the integer provided in the $Interval Paramater to actual minutes in a timespan object
        $TimeInterval = New-TimeSpan -Minutes $Interval
        
        # This hash table is created to store a record of which Which computer names belong to which RunspaceID's
        $RunspaceHash = @{}
        # This array stores each runspace in order to keep track of it's status.
        $RunspaceCollection = @()
        # Create a pool of runspaces. By default, min threads is 1 and max threads is 200. This means that only 200 computers can be running at any given time. 
        $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1,200)
        # Make threads reusable
        $RunspacePool.ThreadOptions = "ReuseThread"
        # "Activate" the pool
        $RunspacePool.Open()

        # Because this is multithreaded, the bulk of the work is completed inside of the below script block, which is called later.
        $Command = {
            # This scriptblock looks like a function, because they are pretty much one and the same if you think about it.
            Param (
                $Computer,
                $Group,
                $NeededCount,
                $FailedCount,
                $LastSyncTime,
                $OperatingSystem
            )
                    
            Function CreateProcessReturnCode {
                Param ($ReturnCode)
                Switch ($ReturnCode){
                    2 {"Access Denied while creating a remote process via WMI"}
                    3 {"Insufficient Privilege while creating a remote process via WMI"}
                    8 {"Unknown failure while creating a remote process via WMI"}
                    9 {"Path Not Found while creating a remote process via WMI"}
                    21 {"Invalid Parameter while creating a remote process via WMI"}
                }
            }

            # Have to make sure the Computer is on before we can send any commands to it
            If (!$(Test-Connection -Computername $Computer -Count 1 -Quiet)){
                [pscustomobject]@{
                    ComputerName = $Computer
                    Group = $Group
                    Status = "Error: Could not ping Computer"
                    Needed = $NeededCount
                    Failed = $FailedCount
                    LastSync = $LastSyncTime
                    OperatingSystem = $OperatingSystem
                } 
            }
            ElseIf (!$(Gwmi win32_Operatingsystem -computername $Computer -ErrorAction SilentlyContinue)) {
                [pscustomobject]@{
                    ComputerName = $Computer
                    Group = $Group
                    Status = "Error: Could not connect via WMI"
                    Needed = $NeededCount
                    Failed = $FailedCount
                    LastSync = $LastSyncTime
                    OperatingSystem = $OperatingSystem
                }
            }
            Else {
                $Session = New-CimSession -ComputerName $Computer -SessionOption (New-CimSessionOption -Protocol Dcom) -ErrorAction Stop -OperationTimeoutSec 120 -Name $Computer

                # This is the star of the function, /DetectNow and /ReportNow is ran remotely via WMI 
                $DetectNow = Invoke-CIMMethod -CimSession $Session -ClassName Win32_Process -Name Create -Arguments @{CommandLine='C:\windows\system32\wuauclt.exe /detectnow'} -ErrorAction Stop
                $ReportNow = Invoke-CIMMethod -CimSession $Session -ClassName Win32_Process -Name Create -Arguments @{CommandLine='C:\windows\system32\wuauclt.exe /reportnow'} -ErrorAction Stop

                If ($ReportNow.ReturnValue -ne 0 -or $DetectNow.ReturnValue -ne 0) {
                    [pscustomobject]@{
                        ComputerName = $Computer
                        Group = $Group
                        Status = "Error: $(CreateProcessReturnCode -ReturnCode $(If ($ReportNow.ReturnValue -eq $True){$ReportNow.ReturnValue}ElseIf($DetectNow.ReturnValue -eq $True){$ReportNow.ReturnValue}))"
                        Needed = $NeededCount
                        Failed = $FailedCount
                        LastSync = $LastSyncTime
                        OperatingSystem = $OperatingSystem
                    }
                }
                ElseIf (@(Compare-Object (Get-CIMInstance -CimSession $Session -namespace "root" -class "__Namespace" | Select -Expand Name) "EminentWareSccm2007","EminentWare" -IncludeEqual -ExcludeDifferent).count -ne 2) {
                    [pscustomobject]@{
                        ComputerName = $Computer
                        Group = $Group
                        Status = "Warning: Computer lacks Patch Manager WMI Providers"
                        Needed = $NeededCount
                        Failed = $FailedCount
                        LastSync = $LastSyncTime
                        OperatingSystem = $OperatingSystem
                    }
                }
                ElseIf ((Get-CimInstance -CimSession $Session -Namespace Root\EminentWare -ClassName Win32_WUAConfiguration).SystemInfoInfoRebootRequired -eq $True) {
                    [pscustomobject]@{
                        ComputerName = $Computer
                        Group = $Group
                        Status = "Warning: Computer Pending Reboot"
                        Needed = $NeededCount
                        Failed = $FailedCount
                        LastSync = $LastSyncTime
                        OperatingSystem = $OperatingSystem
                    }
                }
                ElseIf ((Get-CimInstance -CimSession $Session -ClassName Win32_Volume -Filter "DriveLetter = 'C:'" | Where {($_.Freespace / 1GB) -lt 1 })) {
                    [pscustomobject]@{
                        ComputerName = $Computer
                        Group = $Group
                        Status = "Warning: Low Disk Space on C:"
                        Needed = $NeededCount
                        Failed = $FailedCount
                        LastSync = $LastSyncTime
                        OperatingSystem = $OperatingSystem
                    }
                }
                ElseIf (($MemTest = Get-CimInstance -CimSession $Session -ClassName Win32_OperatingSystem | ForEach {($_.freephysicalmemory) / ($_.totalvisiblememorysize) * 100}) -lt 5) {
                    [pscustomobject]@{
                        ComputerName = $Computer
                        Group = $Group
                        Status = "Warning: Low Available System Memory"
                        Needed = $NeededCount
                        Failed = $FailedCount
                        LastSync = $LastSyncTime
                        OperatingSystem = $OperatingSystem
                    }
                }
                Else {
                    [pscustomobject]@{
                        ComputerName = $Computer
                        Group = $Group
                        Status = "Initiated"
                        Needed = $NeededCount
                        Failed = $FailedCount
                        LastSync = $LastSyncTime
                        OperatingSystem = $OperatingSystem
                    }
                }
            } #Else
        } #$Command

        $ComputerHash = @{}
    } #Begin

    Process {
        # Everything is in a big For loop because we want to run this multiple times depending on how many repeats are specified
        For ($i = 0; $i -lt $Repeat; $i++ ){
            # Trying to resolve the specified WSUS Group 
            #Try{
                # If a WSUSGroup was specified and not a Computername, then...
                If ($WSUSGroup) {
                    $ComputerName = @()

                    # We want to get all the sub groups of all specified WSUSGroups, We will need that recursive function here.
                    $WSUSGroup = $WSUSGroup | ForEach {Get-WSUSRecursiveGroups -Group $_ -WSUS $WSUS}
                    
                    # Getting all the computers of the WSUSGroups and throwing them into the $Computername array
                    ForEach($G in $WSUSGroup){
                        If ($ExcludeFullyPatched -eq $True){
                            $ErrorActionPreference = 'Ignore'
                            $WSUS.GetComputerTargetGroup((ConvertTo-WsusGroupSID -GroupName $G)).GetComputerTargets() | ForEach {$ComputerHash.Add($_.ID,$_.FullDomainName)}
                            $ErrorActionPreference = "Continue"
                            $ComputerName += $WSUS.GetComputerTargetGroup((ConvertTo-WsusGroupSID -GroupName $G)).GetTotalSummaryPerComputerTarget() | where {$_.NotInstalledCount -ne 0 -or $_.FailedCount -ne 0} | ForEach {$ComputerHash[$($_.ComputerTargetId)]}
                        }
                        Else {
                            $ComputerName += $WSUS.GetComputerTargetGroup((ConvertTo-WsusGroupSID -GroupName $G)).GetComputerTargets() | Select -Expand FullDomainName
                        }
                    }
                }
                # If ComputerName was specified instead of WSUSGroup...
                ElseIf ($ComputerName) {
                    # We dont do anything, because we already have our list of ComptuerNames.
                }
            #}
            #Catch {
                # If an error were to occur, that means that WSUS was not able to do anything with the group name provided, because it's wrong.
                #Throw "Invalid WSUSGroup(s)"
            #}

            # We want our list of ComputerNames neat, alphabetical, and no duplicates
            $ComputerName = $ComputerName | Sort -Unique

            # We are already using $i for the For Loop, so we are goign to use $ii for the piece below. We want it to be equal to how many compters we have
            $ii = $ComputerName.Count

            # For Every Computer in our list...
            ForEach ($Computer in $ComputerName){
                # We are goign to throw a progress bar up that counts down
                Write-Progress -Activity "Checking Into WSUS" -Status "Getting Patch Status for $ii Computers"
                # And thus, we take one away every time we move onto another computer
                $ii--

                # If WSUS can't find a one of the ComputerNames, we will throw an error.
                Try {
                    $WSUSComp = $WSUS.GetComputerTargetByName($Computer)
                }
                Catch {
                    Throw "Invalid ComputerName(s)"
                }
                
                # We need to know how many updates this computer needs.
                $NeededCount = $WsusComp.GetUpdateInstallationSummary().NotInstalledCount
                $FailedCount = $WSUSComp.GetUpdateInstallationSummary().FailedCount


                # If WSUS was able to find the Computer fine, then we will need to know what groups the Computer is in. We do this via GUID
                $GroupID = $WSUSComp.ComputerTargetGroupIDs.Guid
                
                # We are Converting GUID to Name here
                $Group = $GroupID | Foreach {$WSUS.GetComputerTargetGroup($_)} | Select -ExpandProperty Name
                
                
                # We need to know when this computer last synced. For some reason, the time is 5 hours off. If you get an error while trying to subtract the value from 5 hours, 
                # that means that the value isnt an integer, but rather, something like "Not checked in yet", in which case we will set this value to, "Not Yet Reported"
                Try {
                    $LastSyncTime = ($wsuscomp.LastReportedStatusTime) - (New-TimeSpan -Hours 5)
                }
                Catch {
                    $LastSyncTime = "Not Yet Reported"    
                }
                
                # Grabbing the Operating System of the Computer
                $OperatingSystem = $WsusComp.OSDescription
                
                
                # This is where we run the above scriptblock in a new thread and assign the runspace pool to it
                $Powershell = [Powershell]::Create().AddScript($Command).AddArgument($Computer).AddArgument($($Group | Where {$_ -ne "All Computers"})).AddArgument($NeededCount).AddArgument($FailedCount).AddArgument($LastSyncTime).AddArgument($OperatingSystem)
                $Powershell.RunspacePool = $RunspacePool

                # Because we need to keep track of how many threads are open, we are going to add the below object to an array. The important part of this object is that we start the thread to begin the above scriptblock and we record the runspace ID of the thread.
                [Collections.ArrayList]$RunspaceCollection += New-Object PSObject -Property @{
                    Runspace = $Powershell.BeginInvoke()
                    Powershell = $Powershell
                }
            } #ForEach

            # While there are still objects in the RunspaceCollection array, we are going to do the following over and over again
            While ($RunspaceCollection){

                # Write a progress bar letting the user know that we are still waiting on systems to finish
                Write-Progress -Activity "Checking Into WSUS" -Status "Waiting for $($RunspaceCollection.Count) Computers to check into WSUS"

                # For each thread still going...
                Foreach($Runspace in $RunspaceCollection.ToArray()){
                    
                    # If it has finished it's work...
                    If($Runspace.Runspace.IsCompleted){

                        # End the thread. Once the thread is ended here, it will display any information that it has collected. For us, that is the pscustomobject object that we create in our command.
                        $Runspace.PowerShell.EndInvoke($Runspace.Runspace)
                        # Remove the thread from memory
                        $Runspace.PowerShell.Dispose()
                        # Remove the thread from the $Runspace Collection
                        $RunspaceCollection.Remove($Runspace)
                    }
                }
                # Put a slight time delay in for performance sake
                Start-Sleep -Milliseconds 100
            }

            # Once all the threads have finished, we need to see if a repeat is going to happen
            If ($i -lt ($Repeat - 1)) {

                # If a repeat is going to happen, we are going to specify a time when the repeat interval is going to end
                $EndTime = ([DateTime]::Now) + (New-TimeSpan -Minutes ([Int32]$TimeInterval.TotalMinutes))

                # We will insert a blank object in here to separated the results of different repeats
                [pscustomobject]@{
                    ComputerName = ""
                    Group = ""
                    Status = ""
                    Needed = ""
                    Failed = ""
                    LastSync = ""
                    OperatingSystem = ""
                } 

                # While the endtime has not been reached yet...
                While ([DateTime]::Now -lt $EndTime) {
                    # We are going to update the progress bar to reflect how much time is remaining....
                    Write-Progress -Activity "Checking Into WSUS" -Status "Waiting for $([Int32]($EndTime - ([DateTime]::Now)).TotalSeconds) more seconds until next check-in"
                    # Every half a second.
                    Start-Sleep -Milliseconds 500
                }
            }
        } #For
    }

    End {
        $RunspacePool.Close()
        $RunspacePool.Dispose()
    }
}