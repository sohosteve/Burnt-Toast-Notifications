Import-Module $env:SyncroModule
# Added check for Nuget
Function CheckforNuget{
    $results = get-packageprovider
    foreach($i in $results){
        
        if($i.name -eq "NuGet"){
            return $true
        }
    }
}
If(checkforNuget){
    write-host "Nuget is installed, proceeding "
} else {
    # This installs the required Nuget Package Manager
    write-host "Nuget is installing...."
    Install-PackageProvider -Name NuGet -RequiredVersion 2.8.5.208 -Force
}

function Test-RebootRequired 
{
    $result = @{
        CBSRebootPending =$false
        WindowsUpdateRebootRequired = $false
        FileRenamePending = $false
        SCCMRebootPending = $false
    }

    #Check CBS Registry
    $key = Get-ChildItem "HKLM:Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction Ignore
    if ($key -ne $null) 
    {
        $result.CBSRebootPending = $true
    }
   
    #Check Windows Update
    $key = Get-Item "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction Ignore
    if($key -ne $null) 
    {
        $result.WindowsUpdateRebootRequired = $true
    }

    #Check PendingFileRenameOperations
    $prop = Get-ItemProperty "HKLM:SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction Ignore
    if($prop -ne $null) 
    {
        #PendingFileRenameOperations is not *must* to reboot?
        #$result.FileRenamePending = $true
    }
    
    #Check SCCM Client <http://gallery.technet.microsoft.com/scriptcenter/Get-PendingReboot-Query-bdb79542/view/Discussions#content>
    try 
    { 
        $util = [wmiclass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
        $status = $util.DetermineIfRebootPending()
        if(($status -ne $null) -and $status.RebootPending){
            $result.SCCMRebootPending = $true
        }
    }catch{}

    #Return Reboot required
    return $result.ContainsValue($true)
}
Test-RebootRequired


if(Test-RebootRequired)
{

Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

#Checking if ToastReboot:// protocol handler is present
New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -erroraction silentlycontinue | out-null
$ProtocolHandler = get-item 'HKCR:\ToastReboot' -erroraction 'silentlycontinue'
if (!$ProtocolHandler) {
    #create handler for reboot
    New-item 'HKCR:\ToastReboot' -force
    set-itemproperty 'HKCR:\ToastReboot' -name '(DEFAULT)' -value 'url:ToastReboot' -force
    set-itemproperty 'HKCR:\ToastReboot' -name 'URL Protocol' -value '' -force
    new-itemproperty -path 'HKCR:\ToastReboot' -propertytype dword -name 'EditFlags' -value 2162688
    New-item 'HKCR:\ToastReboot\Shell\Open\command' -force
    set-itemproperty 'HKCR:\ToastReboot\Shell\Open\command' -name '(DEFAULT)' -value 'C:\Windows\System32\shutdown.exe -r -t 00' -force
}

#Install-PackageProvider -Name NuGet -RequiredVersion 2.8.5.208 -Force
Install-Module -Name BurntToast
Install-module -Name RunAsUser
invoke-ascurrentuser -scriptblock {
 
    $heroimage = New-BTImage -Source 'https://itmedia.azureedge.net/media/soho-000019.gif' -HeroImage
    $Text1 = New-BTText -Content  "Message from the SoHo Help Desk"
    $Text2 = New-BTText -Content "SoHo Integration has installed updates on your computer at $(get-date). Please select if you'd like to reboot now, or snooze this message. It is important to reboot when possible for the security and performance of your system."
    $Button = New-BTButton -Content "Snooze" -snooze -id 'SnoozeTime'
    $Button2 = New-BTButton -Content "Reboot now" -Arguments "ToastReboot:" -ActivationType Protocol
    $5Min = New-BTSelectionBoxItem -Id 5 -Content '5 minutes'
    $10Min = New-BTSelectionBoxItem -Id 10 -Content '10 minutes'
    $1Hour = New-BTSelectionBoxItem -Id 60 -Content '1 hour'
    $4Hour = New-BTSelectionBoxItem -Id 240 -Content '4 hours'
    $1Day = New-BTSelectionBoxItem -Id 1440 -Content '1 day'
    $Items = $5Min, $10Min, $1Hour, $4Hour, $1Day
    $SelectionBox = New-BTInput -Id 'SnoozeTime' -DefaultSelectionBoxItemId 10 -Items $Items
    $action = New-BTAction -Buttons $Button, $Button2 -inputs $SelectionBox
    $Binding = New-BTBinding -Children $text1, $text2 -HeroImage $heroimage
    $Visual = New-BTVisual -BindingGeneric $Binding
    $Content = New-BTContent -Visual $Visual -Actions $action
    Submit-BTNotification -Content $Content
}

Log-Activity -Message "User was notified of pending updates and to reboot" -EventName "Notify User"




} else{
    write-output "Reboot was not required"
}