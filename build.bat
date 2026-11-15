@echo off
REM Build MediaXMax.exe. Put mpv.exe (and its DLLs) inside the mpv folder first.
pip install -r requirements.txt pyinstaller
pyinstaller --noconfirm --onefile --windowed --name MediaXMax --collect-all webview --add-data "ui;ui" --add-data "mpv;mpv" main.py
echo.
echo Done. The app is in dist\MediaXMax.exe
pause
