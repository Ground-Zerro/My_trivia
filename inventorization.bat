@echo on
setlocal enabledelayedexpansion
chcp 65001 > nul
set OUTPUT_FILE=%COMPUTERNAME%.txt
del /q /f %OUTPUT_FILE%
systeminfo | findstr /v /c:"OS Manufacturer" /c:"OS Configuration" /c:"OS Build Type" /c:"Registered Owner" /c:"Product ID" /c:"System Directory" /c:"Boot Device" /c:"System Locale" /c:"Input Locale" /c:"Available Physical Memory" /c:"Virtual Memory: Max Size" /c:"Virtual Memory: Available" /c:"Virtual Memory: In Use" /c:"Page File Location(s)" /c:"Hyper-V Requirements:" /c:"Virtualization Enabled In Firmware" /c:"Second Level Address Translation" /c:"Data Execution Prevention Available"> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo Процессор:>> %OUTPUT_FILE%
wmic cpu get name | findstr /v /r "^$">> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo ОЗУ:>> %OUTPUT_FILE%
powershell -command "$TotalMemorySlots = (Get-WmiObject -Class Win32_PhysicalMemoryArray).MemoryDevices; $UsedMemorySlots = (Get-WmiObject -Class Win32_PhysicalMemory).Count; $FreeMemorySlots = $TotalMemorySlots - $UsedMemorySlots; Write-Host 'Занято слотов -' $UsedMemorySlots; Write-Host 'Свободно слотов -' $FreeMemorySlots;" >> %OUTPUT_FILE%
wmic memorychip get capacity, speed, manufacturer, partnumber | findstr /v /r "^$" >> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo Видеоадаптер:>> %OUTPUT_FILE%
wmic path win32_videocontroller get caption, name | findstr /v /r "^$">> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo Накопители:>> %OUTPUT_FILE%
wmic diskdrive get model, size, interfacetype, serialnumber | findstr /v /r "^$">> %OUTPUT_FILE%

echo.>> %OUTPUT_FILE%
echo CD/DVD приводы:>> %OUTPUT_FILE%
wmic cdrom get caption, name | findstr /v /r "^$">> %OUTPUT_FILE%
if %ERRORLEVEL% neq 0 (
    echo отсутствуют>> %OUTPUT_FILE%
)

echo.>> %OUTPUT_FILE%
echo Монитор:>> %OUTPUT_FILE%
powershell -command "$OUTPUT_FILE='%OUTPUT_FILE%'; function Decode { If ($args[0] -is [System.Array]) { [System.Text.Encoding]::ASCII.GetString($args[0]) } Else { 'Not Found' } } ForEach ($Monitor in Get-WmiObject WmiMonitorID -Namespace root\wmi) { $Manufacturer = Decode $Monitor.ManufacturerName -notmatch 0; $Name = Decode $Monitor.UserFriendlyName -notmatch 0; $Serial = Decode $Monitor.SerialNumberID -notmatch 0; Add-Content -Path $OUTPUT_FILE -Value ('Manufacturer: ' + $Manufacturer + ' Name: ' + $Name + ' Serial Number: ' + $Serial); }"


echo.>> %OUTPUT_FILE%
echo Пользователи:>> %OUTPUT_FILE%
set "user_path=C:\Users\"
for /d %%i in ("%user_path%*") do @(if exist "%%i\AppData" (echo %%~nxi>> %OUTPUT_FILE%))
