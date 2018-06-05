Function Get-ServerAppliedGPO {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0)]
        [String[]]$Computername = $Env:COMPUTERNAME,
        
        #[Parameter(Mandatory=$true)]
        [validatescript({$_ -in $(Get-ADTrust -Filter * | where {$_.Direction -Match '^(Inbound|BiDirectional)$'} | Select -ExpandProperty Name) -or $_ -eq $(Get-ADDomain | select -expand dnsroot)})]
        [string]$TargetGPODomain = (Get-ADDomain).DNSRoot,

        [Int]$MaxThreads = 16
    )
    
    DynamicParam {
        #This is where the GPO Parameter is defined.
        Try{
            #Necessary workaround to a bug in Powershell relating to Dynaminc Parameters where there are spaces in a value and Powershell does not automatically quote it.
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
        }
        Catch{}

        #Gathering Trusted Domains

        #$Trusted = Get-ADTrust -Filter * | where {$_.Direction -Match '^(Inbound|BiDirectional)$'} | Select -ExpandProperty Name
        #$Trusted += Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain

        #If Domain is Null, input local domain as the value.
        #If($TargetGPODomain -eq $Null){$GPOTargetDomain = Get-ADDomain | select -expand dnsroot}

        #Verifying Selected domain is a Trusted Domain
        #If($TargetGPODomain -in $Trusted){
            #Obtaining [Validateset()] for GPO Dynamic Parameter
            $GPOList = Get-GPO -domain $TargetGPODomain -all | select -expand displayname

            #Defining [Parameter()] for GPO Dynamic Parameter
            $GPOParamAttribute = New-Object System.Management.Automation.ParameterAttribute
            $GPOParamAttribute.Mandatory = $true
            $GPOParamAttribute.ParameterSetName = 'GPO'
        
            #Defining [ValidateSet()] for GPO Parameter
            $GPOValidationList = New-Object System.Management.Automation.ValidateSetAttribute(($GPOList | ForEach {[DynParamQuotedString[]] $_.ToString()}))

            #Defining Attibutes to use for GPO Dynamic Parameter
            $GPOAttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $GPOAttributeCollection.Add($GPOParamAttribute)
            $GPOAttributeCollection.Add($GPOValidationList)

            #Creating a runtimedefinedparameter for GPO Dynamic Parameter
            $GPOGroupParameter = New-Object System.Management.Automation.RuntimeDefinedParameter('GPO',[DynParamQuotedString[]],$GPOAttributeCollection)
        
            #Adding GPO Parameter to the Dictionary
            $GPOParameterDefinition = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
            $GPOParameterDefinition.Add("GPO",$GPOGroupParameter)

            #Present Parameter to System
            Return $GPOParameterDefinition
        #} #End If  
    }#End DynamParam
    
    Begin {
        #Extracting Selected GPO Value
        $GPO = $($PSBoundParameters.GPO | select -ExpandProperty OriginalString)
        $Command = {
            Param (
                $Computer,
                $GPO
            )
            #Testing Remote computer for Response
            If(Test-Connection -computername $Computer -quiet -Count 1){
                    #Defining CIMSession Parameters
                    $CimParams = @{  
                        ErrorAction = 'Stop'
                    }
                    if($Computer -notlike "$Env:ComputerName*"){
                        #If not localhost, then add the computer name to the parameters for the Cimsession
                        $Null = $CimParams.Add('ComputerName',$Computer)
                    }
                    
                #Error checking for Cimsession with the given parameters - WSMAN By Default.
                Try{
                    $CimSession = New-CimSession @CimParams -SessionOption (New-CimSessionOption -Protocol Dcom)
                    
                }
                Catch{
                    Try{
                        #WSMAN by default if WSMAN fails
                        $CimSession = New-CimSession @CimParams
                    }
                    Catch{
                        #If both Cimsession attempts error, this is the error object that will be output.
                        [PSCustomObject]@{
                            ComputerName = $Computer
                            GPO = $GPO
                            Status = "Cannot Connect over WSMAN/DCOM"
                            OperatingSystem = ""
                            LastBootTime = 00000000
                        } 
                        Break
                    }
                }
                #Gathering OS and LastBootTime Information
                $OSInfo = (Get-ciminstance -CimSession $CimSession -class win32_operatingsystem | select caption,lastbootuptime)

                #Checking the registry for the value specified in the GPO Parameter
                $Item = [System.Collections.ArrayList]@()
                $Folders = (Invoke-CimMethod -ClassName stdregprov -CimSession $Cimsession -MethodName Enumkey -Arguments @{hDefKey = [uint32]'0x80000002';sSubKeyName = "Software\Microsoft\Windows\CurrentVersion\Group Policy\History\"}).snames
                foreach($Folder in $Folders){
                    $Doots = (Invoke-CimMethod -ClassName stdregprov -CimSession $Cimsession -MethodName Enumkey -Arguments @{hDefKey = [uint32]'0x80000002';sSubKeyName = "Software\Microsoft\Windows\CurrentVersion\Group Policy\History\$Folder"}).snames
                    foreach($Doot in $Doots){
                        $Null = $Item.Add((Invoke-CimMethod -ClassName stdregprov -CimSession $Cimsession -MethodName getstringvalue -Arguments @{hDefKey = [uint32]'0x80000002';sSubKeyName = "Software\Microsoft\Windows\CurrentVersion\Group Policy\History\$Folder\$Doot";svaluename = "displayname"}).svalue)
                    }
                }

                $Item = $Item | Where-Object {$_ -eq $GPO}
                            
                #If the GPO exists in the registry, then the Item variable will have a value and will show as Applied
                if($Item -ne $Null){
                    $Status = "Applied"
                }
                Else{
                    $Status = "Not Applied"
                }

                [System.WSA.Server.AppliedGPO]@{
                    ComputerName = $Computer
                    GPO = $GPO
                    Status = $Status
                    OperatingSystem = $OSInfo.Caption
                    LastBootTime = $OSInfo.lastbootuptime
                }    
            } #End If Test-Connection
            #If Remote Server does not respond to Ping
            Else{
                [PSCustomObject]@{
                        ComputerName = $Computer
                        GPO = $GPO
                        Status = "Not Responding"
                        OperatingSystem = ""
                        LastBootTime = 00000000
                } 
            }
            Remove-CimSession -CimSession $Cimsession
        } #End Command

        # This is where we specify the amount of threads to use. This is put into the parameter of the function so the user can set the thread count at runtime.
        $RunspacePool = [runspacefactory]::CreateRunspacePool(1,$MaxThreads)
        $RunspacePool.Open()

        # This array will hold all of our threads
        $Jobs = @()
        
    }

    Process {
        ForEach ($Computer in $Computername){
            # You will want to change the progress bar to reflect what your function is doing.
            Write-Progress -Activity 'Checking Group Policy Object' -Status "Loading Computers ($($Jobs.Count)/$($Computername.Count))" -PercentComplete ($($Jobs.Count)/$($Computername.Count)*100)

            # This is where you will create each thread. If you have additional arguments that you need passed into the thread, add additional ".AddArgument($ArgumentHere)" statements to the end of the line (no spaces)
            $PowershellThread = [Powershell]::Create().AddScript($Command).AddArgument($Computer).AddArgument($GPO)

            #This is where you assign your new thread to the runspace pool and execute it
            $PowershellThread.RunspacePool = $RunspacePool
            $Handle = $PowershellThread.BeginInvoke()

            # Now that your thread is running, this is storing information about it.
            $Jobs += [pscustomobject]@{
                Handle = $Handle
                Thread = $PowershellThread
                Computername = $Computer
            }
        }
    }

    End {
        # This while statement will keep running until all of your job results are returned
        While (@($Jobs | Where {$_.Handle -ne $Null}).Count -gt 0){
            # You will want to change the progress bar to reflect what your function is doing.
            $JobsInProgress = @($Jobs | Where {$_.Handle -ne $Null}).Count
            Write-Progress -Activity 'Checking Group Policy Object' -Status "Checking Computers $JobsInProgress for the policy" -PercentComplete ((($Computername.Count - $JobsInProgress) / $Computername.Count) * 100)
            ForEach ($Job in $($Jobs | Where-Object {$_.Handle.IsCompleted -eq $True})){
                # This statement actually is what stops your job AND returns the data of your job to the host
                $Job.Thread.EndInvoke($Job.Handle)
                $Job.Thread.Dispose()
                $Job.Thread = $Null
                $Job.Handle = $Null
            }
        }

        # These 2 statements are necessary, because if you dont close your runspace pool when you are finished, Powershell will still run in the background within this runspace pool, even after you close powershell.
        $RunspacePool.Close()
        $RunspacePool.Dispose()
    }
}