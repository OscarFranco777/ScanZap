#!/bin/bash
echo "========================================"
echo "  Inventario ERPNext - Iniciando..."
echo "========================================"

cd "$(dirname "$0")/server"

if [ ! -d "node_modules" ]; then
    echo "[1/3] Instalando dependencias..."
    npm install
    echo
fi

echo "[2/3] Iniciando servidor..."
node server.js &
sleep 2

echo "[3/3] Abriendo navegador..."
xdg-open http://localhost:3000 2>/dev/null || open http://localhost:3000 2>/dev/null || echo "Abrí http://localhost:3000 en tu navegador"

echo
echo "App corriendo en http://localhost:3000"
echo "Para cerrar, presiona Ctrl+C"
wait
