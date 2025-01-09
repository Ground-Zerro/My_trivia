@echo Off
NET SESSION >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    net stop bits
    net stop wuauserv
    net stop appidsvc
    net stop cryptsvc
    del %systemroot%\SoftwareDistribution /f /s /q
    del %systemroot%\system32\catroot2 /f /s /q
    del %systemroot%\servicing\LCU /f /s /q
    net start bits
    net start wuauserv
    net start appidsvc
    net start cryptsvc
    echo.
    echo === Готово ===
    pause
) ELSE (
    echo.
    echo Запустите от имени администратора!
    echo.
    pause
)
