@echo off
rem ============================================================
rem  Windows 激活修复工具 - 启动器
rem  会自动请求管理员权限（fix-activation.ps1 内部处理）
rem ============================================================
cd /d "%~dp0"

if not exist "%~dp0fix-activation.ps1" (
    echo [错误] 找不到 fix-activation.ps1
    echo 请确认本文件与 fix-activation.ps1 在同一个目录下。
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-activation.ps1"

if errorlevel 1 (
    echo.
    echo 启动失败。请右键本文件 - 以管理员身份运行。
    pause
)
