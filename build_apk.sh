#!/bin/bash
# Script para construir la app móvil de Inventario

echo "🔧 Construyendo APK de Inventario..."

# Asegurar que flutter esté en el PATH
export PATH="$HOME/snap/flutter/common/flutter/bin:$PATH"

# Ir al directorio del proyecto
cd "$(dirname "$0")"

# Instalar dependencias
echo "📦 Instalando dependencias..."
flutter pub get

# Analizar el código
echo "🔍 Analizando código..."
flutter analyze

# Construir APK
echo "📱 Construyendo APK..."
flutter build apk --release

echo "✅ ¡Listo!"
echo "📱 APK generado en: build/app/outputs/flutter-apk/app-release.apk"
