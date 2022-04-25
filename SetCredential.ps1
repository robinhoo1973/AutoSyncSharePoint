$PSDefaultParameterValues['*:Encoding'] = 'utf8'

$AESKey=get-content "${PSScriptRoot}\Library\password_aes.key"
$Credential="${PSScriptRoot}\Credentials\credential.xml"
$Credential = Import-CliXml -Path $Credential
$Cred=Get-Credential
$Credential.UserName=$Cred.UserName
$Credential.Password=$Cred.Password | ConvertFrom-SecureString -Key $AESKey
Export-Clixml -Path "${PSScriptRoot}\Credentials\credential.xml" -InputObject $Credential -Encoding UTF8
