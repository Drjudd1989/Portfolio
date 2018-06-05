If ($PSISE -ne $null) {
    $Code = @'
Function Start-noun{
    Add-Type -Assemblyname System.Windows.Forms,System.Drawing


    #region Supporting Functions

    #endregion


    #region Form Building
    #Main Form
    $Main = [Windows.Forms.Form]@{
        Size = "400,400"
    }

    $ExitButton = [Windows.Forms.Button]@{
        Location = "$($Main.ClientRectangle.Right - 85),$($Main.ClientRectangle.Bottom - 30)"
        Text = "Exit"
        Size = "75,25"
        Anchor = "Right,Bottom"
    }
    #endregion

    #region Methods
    
    #endregion


    #region Events
    $ExitButton.Add_Click({
        $Main.Close()
    })
    #endregion


    $Main.Controls.Addrange($ExitButton)
    [Windows.Forms.Application]::Run($Main)
    #$main.ShowDialog()
}
#https://msdn.microsoft.com/en-us/library/system.windows.forms.form(v=vs.110).aspx - MSDN Article for more information about Windows.System.Forms
'@

    New-IseSnippet -Title 'Form' -Description 'This is a template for a Powershell Form' -Text $Code -Force -ErrorAction SilentlyContinue
}