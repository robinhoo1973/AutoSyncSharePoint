[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)][string]$SiteUrl,
    [Parameter(Mandatory=$true)][string]$MirrorSourceFolder,
    [Parameter(Mandatory=$true)][string]$MirrorTargetFolder
)

function ConnectSharePoint
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$SiteUrl,
        [Parameter(Mandatory=$true)][PSCredential]$Credential
    )
    Logging "Processing ${SiteUrl}"
    try {
        $global:SharePoint = New-Object Microsoft.SharePoint.Client.ClientContext($SiteURL)
        $global:SharePoint.Credentials = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($Credential.UserName,$Credential.Password)
    
        Logging "Load SharePoint Credential ..."
        #Retrieve list
        $global:CloudDrive = $global:SharePoint.Web
        Logging "Load SharePoint CloudDrive ..."
        $global:SharePoint.Load($global:CloudDrive)
        Logging "Load SharePoint Retrieve CloudDrive ..."
    
    }
    Catch [System.Management.Automation.MethodInvocationException] {       
        Logging "Error in Authentication the SharePoint [${SiteURL}]..."
        exit
    }
}

function Get-Interval
{
    $Breaker="======================================================="
    if($null -eq $(Select-String -Path $global:LogFile -Pattern $Breaker|Select-Object Line -Last 1).Line){
        return (Get-Date).AddHours(-24)
    }
    return Get-Date($(Select-String -Path $global:LogFile -Pattern $Breaker|Select-Object Line -Last 1).Line.replace("=","").replace("Z",""))
}
function Logging
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$Message
    )    
    Write-Output "$(Get-Date -Format u) $Message" >> $global:LogFile
    Write-Host "$(Get-Date -Format u) $Message"
}

function Check_SharePoint_Folder
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$WebTargetFolder
    )
    $WebTargetFolder=$WebTargetFolder.Trim("/")
    $private:Created=$WebTargetFolder
    While ($private:Created -ne ""){
        try{
            $global:CloudDrive.GetFolderByServerRelativeUrl($private:Created)|Out-Null
            $global:SharePoint.ExecuteQuery()
            return $private:Created
        }
        catch {
            $private:Created=Split-Path -Path $private:Created -Parent
        }
    }
    return $private:Created

}
function Provision_SharePoint_Folder
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$WebTargetFolder
    )
    $WebTargetFolder=$WebTargetFolder.Trim("/")
    $private:Created=Check_SharePoint_Folder $WebTargetFolder
    $private:Creating=$WebTargetFolder
    While($private:Created -ne $WebTargetFolder){
        while($(Split-Path -Path $private:Creating -Parent) -ne $private:Created){
            $private:Creating=Split-Path -Path $private:Creating -Parent
        }
        try{
            $global:CloudDrive.Folders.Add($Creating)|Out-Null
            $global:SharePoint.ExecuteQuery()
            if($private:Created -eq $(Split-Path $WebTargetFolder -Parent)){
                Logging "Create SharePoint Folder[${private:Creating}] in CloudDrive ..."
            }
        }
        catch {
            if($private:Created -eq $(Split-Path $WebTargetFolder -Parent)){
                Logging "Error in Creating SharePoint Folder[${private:Creating}] in CloudDrive ..."
            } 
        }
        $private:Created=$private:Creating
        $private:Creating=$WebTargetFolder
    }
 
}

function Upload_SharePoint_File
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$UploadFile,
        [Parameter(Mandatory=$true)][string]$WebTargetUrl
    )
    $WebTargetUrl=$WebTargetUrl.Trim("/")
    $WebTargetFile= "$WebTargetUrl/$(Split-Path $UploadFile -Leaf)"
    $WebFolder=$global:CloudDrive.GetFolderByServerRelativeUrl($WebTargetUrl)
    Logging "Load SharePoint File [${WebTargetUrl}] RelativeUrl in CloudDrive ..."
    $FileStream = ([System.IO.FileInfo] (Get-Item $UploadFile)).OpenRead()
    $FileCreationInfo = New-Object Microsoft.SharePoint.Client.FileCreationInformation
    $FileCreationInfo.Overwrite = $true
    $FileCreationInfo.ContentStream = $FileStream
    $FileCreationInfo.URL = $WebTargetFile
    try{
        Logging "Load SharePoint FileCreationInfo [${WebTargetFile}] RelativeUrl for CloudDrive ..."
        $WebFolder.Files.Add($FileCreationInfo)|Out-Null;
        Logging "Upload SharePoint FileCreationInfo [${WebTargetFile}] RelativeUrl for CloudDrive ..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
        $global:SharePoint.ExecuteQuery()
        Logging "Commit SharePoint FileCreationInfo [${WebTargetFile}] RelativeUrl for CloudDrive ..."
        
        Logging "Uploading ${UploadFile} to $WebTargetUrl"
        $private:Uploaded++
    }
    catch {
        Logging "Error in Uploading SharePoint [${WebTargetFile}] RelativeUrl for CloudDrive ..."
    }
    finally 
    {
        $FileStream.Close()
    }
}
function Enum_SharePoint
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$MirrorTargetFolder
    )  
    $ServerUrls=@($global:ServerRelativeUrl)
    Logging "Waiting for SharePoint Scanning ... "
    $DeletedFile=0
    $DeletedFolder=0
    Provision_SharePoint_Folder $MirrorTargetFolder
    while ($ServerUrls.length -ne 0){
        $Urls=$ServerUrls
        $ServerUrls=@()
        foreach($Url in $Urls){
            $Files = $global:CloudDrive.GetFolderByServerRelativeUrl($Url).Files
            $global:SharePoint.Load($Files)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

            $global:SharePoint.ExecuteQuery()
             
            #Iterate through Each SubFolder
            ForEach($private:File in $Files)
            {
                #Get the Folder's Server Relative URL
                $RelPath=$null
                If ($($private:File.ServerRelativeUrl).SubString(0,$global:ServerRelativeUrl.length) -eq $global:ServerRelativeUrl){
                    $RelPath=$($private:File.ServerRelativeUrl).SubString($global:ServerRelativeUrl.length)
                }
                if($null -ne $RelPath){
                    if($RelPath -in $global:FileList){
                        $global:FileUrlList+=$RelPath
                    }
                    else{
                        $private:File=$global:CloudDrive.GetFileByServerRelativeUrl($private:File.ServerRelativeUrl)
                        $global:SharePoint.Load($private:File)
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
                        $global:SharePoint.ExecuteQuery()
                                 
                        #Delete the file
                        $private:File.DeleteObject()
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

                        $global:SharePoint.ExecuteQuery() 
                        $DeletedFile++                       
                    }
                } 
                
            }
        
            
            $Folders = $global:CloudDrive.GetFolderByServerRelativeUrl($Url).Folders
            $global:SharePoint.Load($Folders)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

            $global:SharePoint.ExecuteQuery()
             
            #Iterate through Each SubFolder
            ForEach($Folder in $Folders)
            {
                $RelPath=$null
                if ($($Folder.ServerRelativeUrl).SubString(0,$global:ServerRelativeUrl.length) -eq $global:ServerRelativeUrl){
                    $RelPath=$($Folder.ServerRelativeUrl).SubString($global:ServerRelativeUrl.length)
                }
                if($null -ne $RelPath){
                    if($RelPath -in $global:FoldList){
                        $global:FoldUrlList+=$RelPath
                        $ServerUrls+=$Folder.ServerRelativeUrl
                    }
                    else{
                        $Folder=$global:CloudDrive.GetFolderByServerRelativeUrl($Folder.ServerRelativeUrl)
                        $global:SharePoint.Load($Folder)
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

                        $global:SharePoint.ExecuteQuery()
                                 
                        #Delete the file
                        $Folder.DeleteObject()
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
                        $global:SharePoint.ExecuteQuery()       
                        $DeletedFolder++                        
                    }                   
                }
            }
    
        }
    }
    Logging "SharePoint Scanning Completed"
    Logging "SharePoint Found $($global:FileUrlList.length) File(s) ... "
    Logging "SharePoint Found $($global:FoldUrlList.Length) Folder(s) ... "
    if($DeletedFile -ne 0){
        Logging "SharePoint Deleted ${DeletedFile} File(s) ... "
    }
    
    if($DeletedFolder -ne 0){
        Logging "SharePoint Deleted ${DeletedFolder} Folder(s) ... "
    }
}

function Enum_Local
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$MirrorSourceFolder
    )     
    
    Logging "Waiting for Local Scanning ... "
    Get-ChildItem $MirrorSourceFolder -File -Recurse|Sort-Object LastWriteTime -Descending|ForEach-Object{
        $global:FileList+=$_.FullName.substring($MirrorSourceFolder.Length).replace("\","/")
        if($_.LastWriteTime -ge $global:ModifiedTime){
            $global:UploadList+=$_.FullName
        }
    }    
    Get-ChildItem $MirrorSourceFolder -Directory -Recurse|Sort-Object LastWriteTime -Descending|ForEach-Object{
        $global:FoldList+=$_.FullName.substring($MirrorSourceFolder.Length).replace("\","/")
    }
    Logging "Local Scanning Completed"
    Logging "Local Found $($global:FileList.length) File(s) ... "
    Logging "Local Found $($global:FoldList.Length) Folder(s) ... "
}

function Enum_Missed
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$MirrorSourceFolder
    )
    Logging "Waiting for Generating Uploading List ... "
    foreach($private:File in $global:FileList){
        if(-not ($private:File -in $global:FileUrlList)){
            $private:FullPath=$MirrorSourceFolder.replace("\","/").trimend("/")
            $private:FullPath="${private:FullPath}/$($private:File.Trim("/"))".replace("/","\")
            if(-not($private:FullPath -in $global:UploadList)){
                $global:UploadList+=$private:FullPath
            }
        }
    }
    Logging "Total $($global:UploadList.Length) File(s) waiting for uploading ... "
}
$PSDefaultParameterValues['*:Encoding'] = 'utf8'


$global:LogFile="${PSScriptRoot}\Log\AutoSyncSharePoint.log"

$global:ModifiedTime=Get-Interval

    

$global:FileList=@()
$global:FoldList=@()
$global:FileUrlList=@()
$global:FoldUrlList=@()
$global:UploadList=@()
$global:ServerRootUrl=(([System.Uri]$SiteUrl).AbsolutePath).Trim("/")
$global:ServerRootUrl
$global:ServerRelativeUrl="/${global:ServerRootUrl}/$($MirrorTargetFolder.Trim("/"))"
Logging "======================================================="
Logging "|Starting Job $($MyInvocation.MyCommand.Name) ..."
Logging "======================================================="
Logging "Parameter: Site URL [${SiteUrl}]"
Logging "Parameter: Check Modified Since [${global:ModifiedTime}]"
Logging "Parameter: Mirror Source Folder [${MirrorSourceFolder}]"
Logging "Parameter: Mirror Target Folder [${MirrorTargetFolder}]"
Logging "Parameter: Server Relative URL [${global:ServerRelativeUrl}]"


Logging "Loading Libraries ..."
#Add references to SharePoint client assemblies and authenticate to Office 365 site – required for CSOM
Add-Type -Path "${PSScriptRoot}\Library\Microsoft.SharePoint.Client.dll"
Add-Type -Path "${PSScriptRoot}\Library\Microsoft.SharePoint.Client.Runtime.dll"
Logging "Libraries Loaded"
$AESKey="${PSScriptRoot}\Library\password_aes.key"
$AESKey=get-content "$AESKey"
$Credential="${PSScriptRoot}\Credentials\credential.xml"
$Credential = Import-CliXml -Path $Credential
$Credential.Password=$Credential.Password|ConvertTo-SecureString -Key $AESKey
$Credential =New-Object System.Management.Automation.PSCredential ($Credential.Username, $Credential.Password)
ConnectSharePoint $SiteURL $Credential
Enum_Local $MirrorSourceFolder
Enum_SharePoint $MirrorTargetFolder
Enum_Missed $MirrorSourceFolder
$private:Uploaded=0
Foreach ($private:File in $global:UploadList){
    $RelPath=(Split-Path $private:File -Parent).SubString($MirrorSourceFolder.Length).Replace("\","/").Trim("/")
    $WebTargetFolder="$MirrorTargetFolder/$RelPath".Trim("/")
    Provision_SharePoint_Folder $WebTargetFolder
    Upload_SharePoint_File $File $WebTargetFolder
}


Logging "Completed Job $($MyInvocation.MyCommand.Name)!"