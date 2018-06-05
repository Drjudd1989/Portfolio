#Requires AlphaFS
Function Get-FolderSize {
    Param (
        [String[]]$Folder,
        [Int]$MaxThreads = 5
    )

    Begin {
        #Determine Environment to load AlphaFS Module from the appropriate DFS.
        Unblock-File -Path "$Path\AlphaFS.dll"
        Try {
            Import-Module "$Path\AlphaFS.dll"
        }
        Catch{Throw "Cannot Load AlphaFS Module"}

        $Command = {
            Param (
                $Fold
            )
            # Most of your script is here
        #Defining integer variables for storing Size and Count.
            [uint64]$Size = 0
            [uint32]$i = 0

        #Enumerating all filed in the folder. Continue on Exception, Recursive, BasicSearch 
            $Files = [Alphaleonis.Win32.Filesystem.Directory]::Enumeratefiles($Fold,[Alphaleonis.Win32.Filesystem.DirectoryEnumerationOptions](16,32,64))
            foreach($File in $Files){
                $i++
                #String Path,FormatOptions = 2 for LongPath (Best Performance)
                $Size += [Alphaleonis.Win32.Filesystem.file]::GetSize($File,2)
            }
            [PSCustomObject]@{
                Folder = ($Fold -split "\\")[-1]
                Size = "$([math]::Ceiling($Size / 1mb))MB"
                NumberOfFiles = $i
            }
        } #End $Command

            # This is where we specify the amount of threads to use. This is put into the parameter of the function so the user can set the thread count at runtime.
            $RunspacePool = [runspacefactory]::CreateRunspacePool(1,$MaxThreads)
            $RunspacePool.Open()

            # This array will hold all of our threads
            $Jobs = @()   
    } #End Begin

    Process {
        ForEach ($Fold in $Folder){
            # You will want to change the progress bar to reflect what your function is doing.
            Write-Progress -Activity 'Loading Folders' -Status "Checking Folders ($($Jobs.Count)/$($Folder.Count))"

            # This is where you will create each thread. If you have additional arguments that you need passed into the thread, add additional ".AddArgument($ArgumentHere)" statements to the end of the line (no spaces)
            $PowershellThread = [Powershell]::Create().AddScript($Command).AddArgument($Fold)

            #This is where you assign your new thread to the runspace pool and execute it
            $PowershellThread.RunspacePool = $RunspacePool
            $Handle = $PowershellThread.BeginInvoke()

            # Now that your thread is running, this is storing information about it.
            $Jobs += [PSCustomObject]@{
                Handle = $Handle
                Thread = $PowershellThread
                Computername = $Fold
            }
        }
    }

    End {
        # This while statement will keep running until all of your job results are returned
        While (@($Jobs | Where {$_.Handle -ne $Null}).Count -gt 0){
            # You will want to change the progress bar to reflect what your function is doing.
            Write-Progress -Activity 'Getting Folder Sizes' -Status "Waiting for $(@($Jobs | Where {$_.Handle -ne $Null}).Count) folders to finish"
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