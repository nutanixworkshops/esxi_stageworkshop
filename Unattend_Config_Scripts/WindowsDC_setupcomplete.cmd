@echo off
set LOCALAPPDATA=%USERPROFILE%\AppData\Local
set PSExecutionPolicyPreference=Unrestricted
powershell "C:\Config_Scripts\WindowsDC_Configure.ps1”
