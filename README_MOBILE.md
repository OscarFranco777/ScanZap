# Inventario ERPNext - App Móvil

Aplicación móvil para inventario con escáner de cámara para códigos de barras.

## Características

- **Escáner de cámara**: Usa la cámara del dispositivo para escanear códigos de barras
- **Entrada manual**: Alternativa para ingresar códigos manualmente
- **Conexión directa a ERPNext**: Sin necesidad de servidor proxy
- **Carga de costos**: Importa archivos Excel con costos unitarios
- **Reportes**: Genera reportes de inventario y envía a ERPNext

## Requisitos

- Flutter SDK 3.41.7 o superior
- Android SDK 21+ (Android 5.0+)
- Acceso a cámara del dispositivo

## Instalación

```bash
# Clonar el repositorio
cd /ruta/al/proyecto

# Instalar dependencias
flutter pub get

# Ejecutar en dispositivo
flutter run
```

## Construcción

### Android APK

```bash
flutter build apk --release
```

El APK se generará en: `build/app/outputs/flutter-apk/app-release.apk`

### Android App Bundle (para Google Play)

```bash
flutter build appbundle --release
```

## Permisos

La app solicita permisos de cámara al iniciar el escáner. En Android 6.0+, el usuario debe otorgar el permiso manualmente.

## Uso

1. **Configurar conexión**: Ingresa la URL, API Key y API Secret de tu instancia ERPNext
2. **Cargar costos**: Sube el archivo Excel con los costos unitarios de los productos
3. **Escanear inventario**: Usa la cámara para escanear códigos de barras o ingresa manualmente
4. **Ver reporte**: Revisa el inventario completo y exporta a Excel o envía a ERPNext

## Notas técnicas

- La app hace llamadas directas a la API de ERPNext (sin proxy)
- Usa `mobile_scanner` para el escaneo de cámara
- Compatible con códigos de barras EAN-13, UPC-A, Code 128, QR, etc.
- Los datos de configuración se guardan localmente con SharedPreferences
