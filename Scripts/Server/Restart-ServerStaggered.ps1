<#
.SYNOPSIS
Performs Staggered reboots for a list of computers.
.DESCRIPTION
Performs Staggered reboots for a list of computers seperated by a user defined interval.

DYNAMIC PARAMETERS
-HealthCheckPath
If HealthCheck is specified, this parameter will allow that health check to be output to a CSV file at a location specified by the user.
.PARAMETER ComputerName
Input multiple computer names to be rebooted.
.PARAMETER  StaggerCount
The number of computers to be rebooted between each interval
.PARAMETER Interval
The amount of time/Interval between each phase of reboot. Time specified is in Seconds.
.PARAMETER ErrorLogPath
Outputs Errors to a specified file path. Must be a text file.
.PARAMETER HealthCheck
If specified, will perform a health check on all participating computers after the interval time has passed after the last reboot phase.
.EXAMPLE
Restart-ServerStaggered -computername (get-content c:\temp\servers.txt) -staggercount 50 -interval 120 -errorlogpath c:\temp\errors.txt -healthcheck

Reboots a user specified list of computers 50 at a time every 120 seconds and will perform a health check on all servers 120 seconds after the last set of servers start their reboot. It will also output an error log to c:\temp\errors.txt to report on any servers that could not be rebooted.
.EXAMPLE
$Servers = Import-csv c:\temp\servers.csv
Restart-ServerStaggered -computername $Servers -staggercount 36 -interval 132 -healthcheck -healthcheckpath c:\temp\healthcheck.csv

Reboots a user specified list of computers 36 at a time every 132 seconds and will perform a health check on all servers 132 seconds after the last set of servers start their reboot and then will export that health check to the specified health check path as a CSV.
.INPUTS
None
.OUTPUTS
System.String
PSCustomObject
#>

function Restart-ServerStaggered{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $true)]
        [int]$StaggerCount,

        [Parameter(Mandatory = $true)]
        [validaterange(1,99999)]
        [int]$Interval,

        [validatepattern("^.*\.txt$")]
        [string]$ErrorLogPath,

        [switch]$HealthCheck
    )
    
    DynamicParam{
        If($HealthCheck -eq $True){

            #Defining [Parameter()] for HealthCheckPath Dynamic Parameter
            $HealthParamAttribute = New-Object System.Management.Automation.ParameterAttribute
            $HealthParamAttribute.Mandatory = $False

            #Defining [ValidateSet()] for HealthCheckPath Parameter
            $HealthValidationList = New-Object System.Management.Automation.ValidatePatternAttribute("^.*\.csv$")

            #Defining Attibutes to use for HealthCheckPath Dynamic Parameter
            $HealthAttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $HealthAttributeCollection.Add($HealthParamAttribute)
            $HealthAttributeCollection.Add($HealthValidationList)

            #Creating a runtimedefinedparameter for HealthCheckPath Dynamic Parameter
            $HealthGroupParameter = New-Object System.Management.Automation.RuntimeDefinedParameter('HealthCheckPath',[String],$HealthAttributeCollection)
        
            #Adding HealthCheckPath Parameter to the Dictionary
            $HealthParameterDefinition = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
            $HealthParameterDefinition.Add("HealthCheckPath",$HealthGroupParameter)

            #Present Parameter to System
            Return $HealthParameterDefinition


        }
    }

    Begin{
        If($ComputerName.Count -lt $StaggerCount){
            Throw "Number of Computers is less than the Stagger Count specified"
        }
        If($StaggerCount -le 0){
            Throw "StaggerCount cannot be 0. Please enter a number 1 or greater"
        }

        $ComputerCount = $ComputerName.count
        $StaggerInitial = $StaggerCount
        $TotalStaggerPhases = [math]::Ceiling($ComputerCount/$StaggerCount)
        $StaggerCount = $StaggerCount - 1
        #Counter for Progress Bar 0
        $StaggerPhase = 1
        $HealthCheckPath = $HealthParameterDefinition.HealthcheckPath.Value
        
         
        If($ErrorLogPath){
            If($(Test-Path -Path $ErrorLogPath) -eq $False){
                New-Item $ErrorLogPath
            }
        }
    }#End Begin
    
    Process{   
        While($StaggerCount -le $ComputerCount){

            #Progress Bar 0 for displaying current overall stagger phase
            Write-Progress -id 0 -Activity "Staggering Reboots" -Status "Rebooting Servers $(($StaggerCount+1)-($StaggerInitial-1)) to $($StaggerCount+1)" -PercentComplete (($StaggerPhase/$TotalStaggerPhases)*100) -ErrorAction SilentlyContinue
            
            #Getting index range of computers
            $Computers = $ComputerName[$($StaggerCount-($StaggerInitial-1))..$StaggerCount]
            
            #Counter for Progress Bar 1 - "Rebooting Servers"
            $i = 1
            foreach($Computer in $Computers){
                #Progress to show computers rebooting
                Write-Progress -id 1 -activity "Rebooting Servers" -Status "Rebooting $Computer" -PercentComplete (($i/$Computers.Count)*100)
                "Rebooting $Computer"

                 #Restarting Computers - If error, will display error message and output to log if user specifies.
                 Try{
                     Restart-Computer -ComputerName $Computer -ErrorVariable ErrorLog -ErrorAction stop -Force
                 }
                 Catch{
                    $ErrorMessage = "$(Get-Date -Format s) - Error: $Computer Could not be restarted"
                    Write-Error $ErrorMessage
                    $ErrorLog = $ErrorMessage
                    If($ErrorLogPath){
                        Add-Content $ErrorLogPath $ErrorLog
                    }
                 }#End Catch
                $i++     
            }#End ForEach
            
            
           
            
            #Delay between each reboot cycle
            If($StaggerCount -le $($ComputerCount-$StaggerInitial)){
                #Counter for Progress Bar 1
                $c = 0
                $Seconds = $Interval
                While ($Seconds -ne 0){
                    #Countdown of time between each reboot cycle
                    Write-Progress -id 1 -activity "Waiting" -Status "Rebooting Next Set of Servers In:" -SecondsRemaining $Seconds -PercentComplete (($c/$Interval)*100)
                    Start-sleep -Seconds 1
                    $Seconds--
                    $c++
                }
            }

            #Counter add for Progress Bar 0
            $StaggerPhase++
            #Count to determine range of the next set of servers
            $StaggerCount = ($StaggerCount+$StaggerInitial)
        }#End While
            #End Progress Bars
            Write-Progress -id 0 -Activity "Staggering Reboots" -Completed
            Write-Progress -id 1 -Activity "Waiting" -Completed
    } #End Process

    End{
        #If specified, perform health check after reboots. Will perform check after interval timer has finished counting down.
        if($HealthCheck){
            $c = 1
            $Seconds = $Interval
            While ($Seconds -ne 0){
                #Countdown of time between each reboot cycle
                Write-Progress -id 1 -activity "Waiting" -Status "Time Remaining to Perform Health Check" -SecondsRemaining $Seconds -PercentComplete (($c/$Interval)*100)
                Start-sleep -Seconds 1
                $Seconds--
                $c++
            }
            Write-Progress -id 1 -Activity "Waiting" -Completed
            #If specified, output healthcheck to a CSV
            If($HealthCheckPath){
                Get-ServerHealth -Computername $ComputerName | Export-Csv $HealthCheckPath
            }
            Else{
                Get-ServerHealth -Computername $ComputerName
            }
        }   
    } #End End
}#End Function