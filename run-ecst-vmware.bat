@echo off
REM ECST VMware Automation Tool Launcher
REM ------------------------------------
REM This batch file launches the Python-based VMware automation tool.

echo.
echo ============================================
echo   ECST VMware Automation Tool
echo ============================================
echo.

REM Check if Python is installed
where python >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Python is not installed or not in PATH.
    echo Please install Python 3.8+ from https://www.python.org/
    pause
    exit /b 1
)

REM Check Python version
python --version

REM Change to script directory
cd /d "%~dp0"

REM Run the Python script
python ecst-vmware.py

REM Keep window open if there was an error
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Script exited with error code %ERRORLEVEL%
    pause
)
