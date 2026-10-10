package com.masterdrinks.masterdrinks

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val USB_CHANNEL = "com.masterdrinks/usb_printer"
    private var usbPrinterHelper: UsbPrinterHelper? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        usbPrinterHelper = UsbPrinterHelper(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USB_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getUsbDevices" -> {
                    try {
                        val devices = usbPrinterHelper?.getUsbDevices() ?: emptyList<Map<String, Any>>()
                        result.success(devices)
                    } catch (e: Exception) {
                        result.error("GET_DEVICES_ERROR", e.message, null)
                    }
                }
                "requestUsbPermission" -> {
                    val deviceId = call.argument<Int>("deviceId")
                    usbPrinterHelper?.requestPermission(deviceId, result)
                        ?: result.error("NO_HELPER", "UsbPrinterHelper no inicializado", null)
                }
                "printBytes" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val deviceId = call.argument<Int>("deviceId")
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("EMPTY_DATA", "No se enviaron datos para imprimir", null)
                        return@setMethodCallHandler
                    }
                    usbPrinterHelper?.printBytes(bytes, deviceId, result)
                        ?: result.error("NO_HELPER", "UsbPrinterHelper no inicializado", null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        usbPrinterHelper?.destroy()
    }
}
