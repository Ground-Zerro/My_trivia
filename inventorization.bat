@echo off
setlocal enabledelayedexpansion
chcp 65001 > nul

REM Getting current date and time
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set "dt=%%I"
set "YYYY=%dt:~0,4%"
set "MM=%dt:~4,2%"
set "DD=%dt:~6,2%"
set "HH=%dt:~8,2%"
set "Min=%dt:~10,2%"
set "SS=%dt:~12,2%"

set "OUTPUT_FILE=%COMPUTERNAME%_%YYYY%-%MM%-%DD%_%HH%-%Min%-%SS%.txt"

echo Executed as user: %USERNAME%> %OUTPUT_FILE%

systeminfo>> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo CPU:>> %OUTPUT_FILE%
wmic cpu get name | findstr /v /r "^$">> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo Videoapter:>> %OUTPUT_FILE%
wmic path win32_videocontroller get caption, name | findstr /v /r "^$">> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo Storage devices:>> %OUTPUT_FILE%
wmic diskdrive get model, size, interfacetype, serialnumber | findstr /v /r "^$">> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo CD/DVD:>> %OUTPUT_FILE%
wmic cdrom get caption, name | findstr /v /r "^$">> %OUTPUT_FILE%
if %ERRORLEVEL% neq 0 (echo undetected)>> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo PC users:>> %OUTPUT_FILE%
set "user_path=C:\Users\"
for /d %%i in ("%user_path%*") do @(if exist "%%i\AppData" (echo %%~nxi>> %OUTPUT_FILE%))

echo.>> %OUTPUT_FILE%
echo Printers:>> %OUTPUT_FILE%
wmic printer get name, deviceID, PortName, Network, local | findstr /v /r "^$">> %OUTPUT_FILE%
if %ERRORLEVEL% neq 0 (echo undetected)>> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo Scanners:>> %OUTPUT_FILE%
wmic scanner get name, deviceid | findstr /v /r "^$">> %OUTPUT_FILE%
if %ERRORLEVEL% neq 0 (echo undetected)>> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo Installed DRAM:>> %OUTPUT_FILE%
powershell -command "$TotalMemorySlots = (Get-WmiObject -Class Win32_PhysicalMemoryArray).MemoryDevices; $UsedMemorySlots = (Get-WmiObject -Class Win32_PhysicalMemory).Count; $FreeMemorySlots = $TotalMemorySlots - $UsedMemorySlots; Write-Host 'busy slots' $UsedMemorySlots; Write-Host 'Free slots' $FreeMemorySlots;">> %OUTPUT_FILE%
wmic memorychip get capacity, speed, manufacturer, partnumber | findstr /v /r "^$">> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo Monitor:>> %OUTPUT_FILE%
powershell -command "$ErrorActionPreference = 'SilentlyContinue'; function Decode { If ($args[0] -is [System.Array]) { [System.Text.Encoding]::ASCII.GetString($args[0]).TrimEnd() } Else { 'Not Found' } } $Results = @(); ForEach ($Monitor in Get-WmiObject WmiMonitorID -Namespace root\wmi) { $Manufacturer = Decode $Monitor.ManufacturerName -notmatch 0; $Name = Decode $Monitor.UserFriendlyName -notmatch 0; $Serial = Decode $Monitor.SerialNumberID -notmatch 0; $Results += ('Manufacturer: ' + $Manufacturer.TrimEnd()); $Results += ('Name: ' + $Name.TrimEnd()); $Results += ('Serial Number: ' + $Serial.TrimEnd()); } $Results | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes($_)) }" | findstr /v /r "^$">> %OUTPUT_FILE%
