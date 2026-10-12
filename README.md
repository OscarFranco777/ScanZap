# ScanZap — Inventario ERPNext (App Móvil)

Aplicación móvil Flutter para gestión de inventario con escáner de códigos de barras, conectada directamente a ERPNext.

> 📱 Documentación técnica detallada de instalación y construcción: ver [README_MOBILE.md](README_MOBILE.md)

## ¿Qué?

App móvil (Flutter, Android/iOS) para inventario y recepciones de compra en ERPNext:

- **Escáner de cámara** de códigos de barras (`mobile_scanner`): EAN-13, UPC-A, Code 128, QR, etc.
- **Entrada manual** alternativa de códigos.
- **Conexión directa a ERPNext** por API (API Key / Secret), sin servidor proxy obligatorio.
- **Recepciones de compra**: creación de Purchase Receipt desde Purchase Order, con precios editables por ítem (`price_list_rate`, `net_amount`), serie de nombrado configurable y moneda dinámica desde la compañía.
- **Carga de costos**: importación de archivos Excel con costos unitarios (`excel`).
- **Reportes**: generación y exportación de reportes de inventario a Excel o envío directo a ERPNext.
- **Pantallas**: Home dashboard, listas y detalles de Órdenes de Compra / Recepciones, escáner, configuración y carga de Excel.

Estructura del código:

```
lib/
├── models/       # InventoryRow, Item, MaterialReceipt, PurchaseOrder
├── providers/    # Estado (provider): inventario, recepciones, PO
├── services/     # erpnext_service (API ERPNext), excel_service
├── views/        # Pantallas: home, escáner, PO, recepciones, config, reporte
└── main.dart
server/           # Proxy Node.js opcional (express) para PWA
```

## ¿Cómo?

- **Stack**: Flutter (Dart SDK ^3.11.5), `dio` para HTTP, `provider` para estado, `mobile_scanner` para escaneo, `shared_preferences` para config local, `excel` + `file_picker` + `share_plus` para import/export.
- **Configuración inicial**: en la pantalla de Config se ingresa URL de la instancia ERPNext, API Key y API Secret; se guardan localmente.
- **Flujo de recepción**: se selecciona (o pre-llena desde) una Purchase Order → se escanean los códigos de barra → se ajustan cantidades/precios → se envía el Purchase Receipt a ERPNext.
- **Construcción**:
  ```bash
  flutter pub get
  flutter run                 # desarrollo
  flutter build apk --release # APK: build/app/outputs/flutter-apk/app-release.apk
  flutter build appbundle     # para Google Play
  ```
  También hay scripts auxiliares: `build_apk.sh`, `iniciar.sh`/`iniciar.bat`, `start.sh`/`start.bat`.
- **Permisos**: solicita acceso a cámara al iniciar el escáner (Android 6.0+ requiere otorgarlo manualmente).

## ¿Por qué?

- **Trazabilidad en campo**: el inventario y las recepciones se capturan en el almacén con el escáner del teléfono, eliminando captura manual y errores de tecleo de códigos de barra.
- **Integración sin intermediarios**: llama directo a la API de ERPNext — un solo punto de verdad, sin servidores intermedios que mantener (el proxy Node en `server/` queda como opción para PWA).
- **Cierre del ciclo de compras**: cubre desde la Purchase Order hasta el Purchase Receipt con precios y moneda correctos, complementando los flujos de ERPNext del cliente.
- **Portabilidad**: Flutter permite una sola base de código para Android e iOS.
