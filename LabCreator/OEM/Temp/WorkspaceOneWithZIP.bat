@ECHO OFF
Set CurrentDir=%~dp0
Set WSOLogScript=C:\Windows\WorkspaceONE_Install.log
Set InstallWSO=%CurrentDir%AirWatchAgent.msi
Set WSOServerName=ds112.airwatchportals.com
Set WSOLGName=WKSWSO
Set WSOUserName=staging@wkswso.com
Set WSOPassword=E+9kxu


REM Check if device is already registered with Workspace ONE, if not then proceed with installing Workspace ONE Intelligent Hub
for /f "delims=" %%i in ('reg query HKLM\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts /s') do set status=%%i
if not defined status goto INSTALL
:INSTALL
REM Run the Workspace ONE Intelligent Hub Installer to Register Device with Staging Account
REM msiexec /i "<PATH>\AirwatchAgent.msi" /quiet ENROLL=Y SERVER=<DS URL> LGName=<GROUP ID> USERNAME=<STAGING USERNAME> PASSWORD=<STAGING PASSWORD> ASSIGNTOLOGGEDINUSER=Y DOWNLOADWSBUNDLE=True /log <PATH TO LOG>

md "%ProgramFiles(x86)%\Airwatch\Agentui\Resources\Bundle"
copy "%CurrentDir%AirWatchLLC.VMwareWorkspaceONE.zip" "%ProgramFiles(x86)%\Airwatch\Agentui\Resources\Bundle\AirWatchLLC.VMwareWorkspaceONE.zip"


msiexec /i "%InstallWSO%" /q ENROLL=Y SERVER=%WSOServerName% LGName=%WSOLGName% USERNAME=%WSOUserName% PASSWORD=%WSOPassword% DOWNLOADWSBUNDLE=TRUE /L*v "%WSOLogScript%"