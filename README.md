# My_trivia
 For my own use


**[Enable bbr + Swap 2Gb:](https://github.com/Ground-Zerro/My_trivia/blob/main/bbr%2Bsawap.sh)**

```
curl -s https://raw.githubusercontent.com/Ground-Zerro/My_trivia/main/bbr%2Bsawap.sh | sudo bash
```


**[YouROK TorrServer](https://github.com/YouROK/TorrServer)**
```
curl -s https://raw.githubusercontent.com/YouROK/TorrServer/master/installTorrServerLinux.sh | sudo bash
```


**[PyCharm trial reset](https://github.com/Ground-Zerro/My_trivia/blob/main/reset-trial-jetbrains-windows.bat)**
- Командная строка Windows:
```
powershell -Command "irm https://raw.githubusercontent.com/Ground-Zerro/My_trivia/main/reset-trial-jetbrains-windows.bat -OutFile $env:TEMP\reset-trial-jetbrains-windows.bat" && cmd /c "%TEMP%\reset-trial-jetbrains-windows.bat"
```


**[Clear Windows 10/11 Update Cache](https://github.com/Ground-Zerro/My_trivia/raw/refs/heads/main/ClearWindowsUpdateCache.bat)**
- Командная строка Windows:
```
powershell -Command "irm https://github.com/Ground-Zerro/My_trivia/raw/refs/heads/main/ClearWindowsUpdateCache.bat -OutFile $env:TEMP\ClearWindowsUpdateCache.bat" && cmd /c "%TEMP%\ClearWindowsUpdateCache.bat"
```


**[VPS Bench](https://github.com/Ground-Zerro/My_trivia/blob/main/bench.sh)**
```
wget -qO- https://raw.githubusercontent.com/Ground-Zerro/My_trivia/refs/heads/main/bench.sh | bash
```

**OPEN WRT - обновить все пакеты с перезаписью конфликтных файлов**
```
opkg update && opkg list-upgradable | cut -f 1 -d ' ' | while read package; do opkg upgrade --force-overwrite "$package"; done
```
