@echo off
title Inventario ERPNext
echo ========================================
echo   Inventario ERPNext - Iniciando...
echo ========================================
echo.

cd /d "%~dp0server"

if not exist "node_modules" (
    echo [1/3] Instalando dependencias...
    call npm install
    echo.
)

echo [2/3] Iniciando servidor...
start "" cmd /c "node server.js"

timeout /t 2 /nobreak >nul

echo [3/3] Abriendo navegador...
start http://localhost:3000

echo.
echo ========================================
echo   App corriendo en http://localhost:3000
echo   Para cerrar, presiona Ctrl+C
echo ========================================
pause
