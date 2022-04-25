# AutoSyncSharePoint
Automatic Sync the Local Folder to SharePoint Online
powershell -ExecutionPolicy ByPass -File "AutoSyncSharePoint.ps1" -SiteUrl "https://xxxxxx.sharepoint.com/teams/DTInfra.OPS" -MirrorSourceFolder "D:\Temp\testsync" -MirrorTargetFolder "/Shared Documents/General/Test4Sync"
