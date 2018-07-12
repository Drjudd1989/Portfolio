
# install-admsa -account xxxxxx -identity xxxxx -server xxxxx.xxxxx -description "xxxxxxxxxxxxx" -group xxxxxx

#$MSAList = Import-Csv [Path]

function install-admsa
{ 

    
    Param
    (
    [parameter(Mandatory=$true,Valuefrompipeline=$true,Valuefrompipelinebypropertyname=$true)]
        [string[]]$Account,

    [parameter(Mandatory=$true,Valuefrompipeline=$true,Valuefrompipelinebypropertyname=$true)]
        [string[]]$identity,

    [parameter(Mandatory=$true,Valuefrompipeline=$true,Valuefrompipelinebypropertyname=$true)]
    [string[]]$Server,

    [parameter(Mandatory=$true,Valuefrompipeline=$true,Valuefrompipelinebypropertyname=$true)]
        [string[]]$Description,

    [parameter(Mandatory=$true,Valuefrompipeline=$true,Valuefrompipelinebypropertyname=$true)]
        [string[]]$group

    )
     
    Begin
    {     

        #Obtain MSA and Server counts
        $Count1 = $account.count
        $count2 = $identity.count

        #Check to ensure the number of MSAs and Servers match - Throws script if they do not match
        If($count1 -eq $count2){} else {throw "Number of accounts and servers do not match"}
    
        #Obtain the numbers for the MSA and Server and compare them line by line to ensure they match
        $servcount = 0
        foreach($act in $account){

            $acttest = $act -replace '[a-z|_]', ''
            $servtest = $identity[$servcount] -replace '[a-z]', ''

            #If any do not match, throw with error message that shows non-matching MSA/Server
            if($acttest -eq $servtest){} else {throw "Account $Act numbers not in line with server $identity[$ServCount] numbers"}
            $servcount ++
        } #End ForEach

        $AccountCheck = @()
        $AccountCount = 0
        
        #Checks each account to see if it exists. If it does, add the account to the array and continue checking.
        foreach($act in $account){
            $act = "$act$"
            $AccountCheck += Get-ADServiceAccount -Filter {samaccountname -eq $act} -server $Server[$AccountCount] -Properties SamAccountName -ErrorAction SilentlyContinue | Select -ExpandProperty SamaccountName
            $AccountCount++
        } #End ForEach

        #If any accounts found to exist, will throw the script and display accounts that already exist.
        if($AccountCheck -ne $Null){
            $AccountCheck;
            Throw "The above accounts already exist"
            } #end If
   
    } #end begin

    Process
    {    
        #Counter creation which allows for this to be done as an array.  
        $counter = 0
        Foreach($act in $Account){
            #Splitting Server to be used in DN
            $servbreak = $Server[$Counter].Split(".")
            $dc1 = $servbreak[0]
            $dc2 = $servbreak[1]
        #Creation of the ADServiceAccount
        New-adserviceaccount -name $Act -Server $Server[$Counter] -enable $true -path "OU=Accounts - Managed,OU=Administrative Objects,OU=Server Administration,DC=$dc1,DC=$dc2" -Description $Description[$Counter] -RestrictToSingleComputer 
        
        #Wait 1 second while the ad service account doesn't exist.
        do {
            start-sleep 1
        }
        while ((get-adserviceaccount -Filter "Name -eq `"$act`"" -server $server[$Counter] -ErrorAction Stop) -eq $null)

        #Adds the Computer to the HostComputers of the MSA
        Add-ADComputerServiceAccount -Identity $identity[$counter] -Server $server[$Counter] -ServiceAccount $act
        #Adds the MSA to the specified Global Group
        add-adgroupmember -Identity $Group[$Counter] -Server $Server[$Counter] -members $($act + "$")
        #Increases counter by 1
        $counter++
        }
    }        
    
    End
    {
    }
    
}
    



