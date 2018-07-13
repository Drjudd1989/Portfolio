<#
.SYNOPSIS
Starts the GUI to get a list of all memberships that an User Account belongs too across all trusted domains.
.DESCRIPTION
Starts a GUI that performs a recursive lookup to obtain all memberships of an User Account across all trusted domains, including memberships of those memberships, and so on.
.EXAMPLE
Start-ADGroupMembership

Start's the ADGroupMembership GUI.
.INPUTS
None. This Cmdlet does not accept any pipeline input.
.OUTPUTS
GUI
#>

Function Open-ADGroupMembershipGUI {
    Import-Module ActiveDirectory
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing

#region Supporting Functions
################################################# Supporting Functions ###################################################
        
        #Supporting Account Testing Function to grey out Button if text field is blank
    Function TestAccount{
    #AccountName Text Box Validation
        If($AccountNameTextField.Text -eq ""){
            $GetADGroupMembership.Enabled = $False
        }
        Else{
            $GetADGroupMembership.Enabled = $True
        }    
    }
#endregion
  
#region Form Building
################################################# Form Building ##########################################################

    #Main Form
    $Main = [Windows.Forms.Form]@{
        Size = "555,450"
        Text = "Group Membership Lookup"
        #MinimumSize = "800,600"   
    }

    #Exit Button
    $ExitButton = [Windows.Forms.Button]@{
        Location = "$($Main.ClientRectangle.Right - 85),$($Main.ClientRectangle.Bottom - 30)"
        Text = "Exit"
        Size = "75,25"
        Anchor = "Right,Bottom"
    }
    $ExportButton = [Windows.Forms.Button]@{
        Location = "$($Main.ClientRectangle.Right - 170),$($Main.ClientRectangle.Bottom - 30)"
        Text = "Export CSV"
        Size = "75,25"
        Anchor = "Right,Bottom"
    }

    #"Computer Name" Label
    $AccountNameLabel = [Windows.Forms.Label]@{
        Text = "Account:"
        Size = "50,25"
        Location = "10,12"
        Anchor = "Left,top" 
    }

    #User input for Computer Name - Will resolve to local machine if left blank
    $AccountNameTextField = [Windows.Forms.Textbox]@{
        Size = "200,50"
        Location = "$($AccountNameLabel.right),10"
        Forecolor = "Black"
        Anchor = "Left,top"
    }

    #Drop down box that lists available domains
    $DomainListBox = [Windows.Forms.Combobox]@{
        Size = "125,25"
        Location = "$($AccountNameTextField.right + 10),$(10)"
        DropDownHeight = "200"
        DropDownStyle = "DropDownList"
        Anchor = "Left,top"
        }

        #Get Folder Button
    $GetADGroupMembership = [Windows.Forms.Button]@{  
        Location = "$($DomainListBox.right + 10),8"
        Size = "125,25"
        Text = "Get Memberships"
        Anchor = "Left,top" 
    }

    $ProgressLabel = [Windows.Forms.Label]@{
        Size = "$($Main.ClientSize.Width - $ExportButton.Size.Width - 30),15"
        Text = ""
        Anchor = "Top,Left,Right,Bottom"
        Location = "10,$($Main.ClientRectangle.Bottom - 30)"  
    }
 
    $ConfirmationMessageBox = [Windows.Forms.Messagebox]
    $SelectDomainMessageBox = [Windows.Forms.Messagebox]

    #Defuault button if the Return/Enter key is pressed
    $Main.AcceptButton = $GetADGroupMembership

    #Grid to output information
    $GroupFolderGrid = [Windows.Forms.DataGridview]@{
        Location = "10,$($AccountNameTextField.bottom + 10)"
        Size = "$($Main.ClientRectangle.Width - 20),$($ExitButton.Top - $AccountNameLabel.bottom - 10)"
        AutoSizeColumnsMode = "Fill"
        ColumnCount = 4
        #RowHeadersWidthSizeMode = "AutoSizeToAllHeaders"
        Anchor = "Top,Left,Right,Bottom"
        ReadOnly = $True
        RowHeadersVisible = $False
        AllowUserToAddRows = $False
        SelectionMode = "FullRowSelect"
    }#End GroupFolderGrid

    $SaveFileDialog = [windows.forms.savefiledialog]@{
        Title = 'Location to Save CSV'
        Filter = "csv files (*.csv)|*.csv"
        InitialDirectory = "c:\\"
    }
    
    #$SaveFileDialog.

#endregion

#region Methods
################################################ Methods #######################################################
        
    #Column Names
    $GroupFolderGrid.Columns[0].Name = "MemberOf"
    $GroupFolderGrid.Columns[1].Name = "Domain"
    $GroupFolderGrid.Columns[2].Name = "GroupScope"
    $GroupFolderGrid.Columns[3].Name = "ChildItem"
    
    #Populating the Domain List Box
    $DomainListBox.Items.Add("Select Domain") | out-null
    $DomainList = @(Get-ADDomain | select -ExpandProperty dnsroot)
    $DomainList += (get-adtrust -Server (Get-ADDomain).DNSRoot -Filter {Direction -ne "Outbound"} | select -ExpandProperty name)
    foreach($Domain in $Domainlist){
        $DomainListBox.Items.Add($Domain) | out-null
    }
    #Default Selected Item
    $DomainListBox.SelectedItem = "Select Domain"
#endregion
    
#region Events
###################################################### EVENTS ################################################################
    
    #Grey out Button if text field is blank
    If($AccountNameTextField.Text -eq ""){
        $GetADGroupMembership.Enabled = $False
    }  

    #Grey out Button if text field is blank when a key is pressed
    $AccountNameTextField.Add_Keyup({
        TestAccount
    })

    #Grey out Button if text field is blank when the mouse
    $DomainListBox.Add_MouseDown({
        TestAccount
    })

        #Get Folder Button Click action
        $GetADGroupMembership.Add_Click({
            If($DomainListBox.SelectedItem -eq "Select Domain"){
                $SelectDomainMessageBox::Show("Please Select the Domain","Select Domain") 
            } #End If DomainListBox Selected Item
            Else{
                #$Domain = $DomainListBox.SelectedItem 
                If(Get-aduser -Filter {SamaccountName -eq $AccountNameTextField.Text} -SearchBase "OU=Administrative Objects,OU=Server Administration,DC=$($DomainListBox.SelectedItem -replace "\.",",DC=")"  -Server $DomainListBox.SelectedItem){
                    $ProgressLabel.Text = 'Starting. . .'
                    $GroupFolderGrid.rows.Clear()
                    $Job = Start-Job -Name 'ServiceMembershipLookup' -ScriptBlock {Param($Name,$Server) Get-ADGroupMembership -Name $Name -Server $Server} -ArgumentList @($AccountNameTextField.Text,$DomainListBox.SelectedItem)
                    $Started = $True
                } #End If Get-ADUser
                Else{
                    $ConfirmationMessageBox::Show("Account does not exist","Account Error")
                    $Started = $False
                } #End Else

                If ($Started){
                    While ($Job.State -ne "Completed") {
                        $Progress = @($Job.ChildJobs.Progress)[-1]
                        If ($Progress.Activity -ne $null) {
                            $ProgressLabel.Text = $Progress.StatusDescription
                            $ProgressLabel.Refresh()
                        } #End Progress Activity
                    } #End While Loop
                    $Progresslabel.Text = ''         
                    $script:Results = Receive-Job $Job
                    Remove-Job $Job
                    $script:Results | foreach {$GroupFolderGrid.rows.add($_.MemberOf,$_.Domain,$_.GroupScope,$_.ChildItem)}
                    $GroupFolderGrid.AutoResizeColumns()
                } #End If Started
            } #End Else
        }) #End Add_Click
    #$Exportbutton.Enabled = $False
    $ExportButton.Add_Click({
        if($GroupFolderGrid.RowCount -ne 0){
            $SaveFileDialog.ShowDialog()
                Try{
                $script:Results | select memberof,domain,childitem,groupscope | Export-Csv $SaveFileDialog.Filename -NoTypeInformation -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                }
                Catch{}
               
        }
    else{
       $SelectDomainMessageBox::Show("There is no data to export","No Data to Export") 
    }  
    })

    $ExitButton.Add_Click({
        $Main.Close()
        $Main.Dispose()
    })
#endregion

    $Main.Controls.AddRange(@($AccountNameLabel,$AccountNameTextField,$DomainListBox,$GetADGroupMembership,$ExportButton,$ExitButton,$GroupFolderGrid, $ProgressLabel))

    [Windows.Forms.Application]::Run($Main)
    #$Main.ShowDialog()
}
