<#
.SYNOPSIS
Searches for one or more file types on a computer
.DESCRIPTION
Searches for one or more file types on a computer
.PARAMETER Path
Specify a search path
.PARAMETER FileExtension
Specify a File Extension to search for (Default is *)
.PARAMETER Recurse
Searches all subfolders until there isnt anymore subfolders to search
.EXAMPLE
Get-File -Path c:\ -FileExtension *

Searches the c:\ folder for all files and folders
.EXAMPLE
Get-File -Path c:\ -FileExtension * -Recurse

Searches the C:\ folder and all subfolders for all files
.EXAMPLE
Get-File -Path c:\ -FileExtension *.ps1 -Recurse

Searches the c:\ folder for any files with the .ps1 file extension
.INPUTS
None. This Cmdlet does not accept any pipeline input.
.OUTPUTS
System.IO.Directory
#>
function Get-File {
    Param (
        [Parameter(Mandatory = $True)]
        [String]$Path,

        [String[]]$FileExtension = '*',

        [Switch]$Recurse
    )
    
    Begin {
        function GetDirectories {
            Param (
                [String]$Path,
                [String[]]$FileExtension
            )

            Trap [System.Management.Automation.MethodInvocationException] {continue}

            $Directories = [System.IO.Directory]::EnumerateDirectories($Path)

            ForEach ($D in $Directories) {
                Write-Progress -Activity 'Searching for Files' -Status "Curently Searching $D"
                ForEach ($Extension in $FileExtension) {
                    [System.IO.Directory]::EnumerateFiles($D,$Extension)
                }
                GetDirectories -Path $D -FileExtension $FileExtension
            }
        }
    }

    Process {
        Trap [System.Management.Automation.MethodInvocationException] {continue}
        $Directories = [System.IO.Directory]::EnumerateDirectories($Path)
        ForEach ($Extension in $FileExtension) {
            [System.IO.Directory]::EnumerateFiles($Path,$Extension)
        }

        If ($Recurse){
            ForEach ($D in $Directories) {
                Write-Progress -Activity 'Searching for Files' -Status "Curently Searching $D"
                ForEach ($Extension in $FileExtension) {
                    [System.IO.Directory]::EnumerateFiles($D,$Extension)
                }
                GetDirectories -Path $D -FileExtension $FileExtension
            }
        }
    }

    End {

    }
}