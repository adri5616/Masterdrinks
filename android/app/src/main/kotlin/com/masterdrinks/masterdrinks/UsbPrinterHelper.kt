package com.masterdrinks.masterdrinks

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class UsbPrinterHelper(private val context: Context) {

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        const val ACTION_USB_PERMISSION = "com.masterdrinks.USB_PERMISSION"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPrintBytes: ByteArray? = null
    private var pendingDevice: UsbDevice? = null

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val action = intent.action
            if (ACTION_USB_PERMISSION == action) {
                synchronized(this) {
                    val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    }

                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    val result = pendingPermissionResult
                    val bytesToPrint = pendingPrintBytes
                    val targetDev = pendingDevice

                    pendingPermissionResult = null
                    pendingPrintBytes = null
                    pendingDevice = null

                    if (granted && device != null) {
                        if (bytesToPrint != null && (targetDev == null || targetDev.deviceId == device.deviceId)) {
                            // Ejecutar la impresión pendiente en segundo plano
                            executor.execute {
                                doPrint(device, bytesToPrint, result)
                            }
                        } else {
                            result?.success(true)
                        }
                    } else {
                        result?.error(
                            "PERMISSION_DENIED",
                            "Permiso USB denegado por el usuario",
                            null
                        )
                    }
                }
            }
        }
    }

    init {
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(usbReceiver, filter)
        }
    }

    fun destroy() {
        try {
            context.unregisterReceiver(usbReceiver)
        } catch (_: Exception) {}
    }

    fun getUsbDevices(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        for (device in usbManager.deviceList.values) {
            val isPrinter = isPrinterDevice(device)
            val hasPerm = usbManager.hasPermission(device)
            val item = mutableMapOf<String, Any>(
                "deviceId" to device.deviceId,
                "deviceName" to device.deviceName,
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "manufacturerName" to (device.manufacturerName ?: "Desconocido"),
                "productName" to (device.productName ?: "Impresora / Dispositivo USB"),
                "isPrinter" to isPrinter,
                "hasPermission" to hasPerm
            )
            list.add(item)
        }
        return list
    }

    fun requestPermission(deviceId: Int?, result: MethodChannel.Result) {
        val device = findTargetDevice(deviceId)
        if (device == null) {
            result.error("NO_DEVICE", "No se encontró el dispositivo USB solicitado", null)
            return
        }

        if (usbManager.hasPermission(device)) {
            result.success(true)
            return
        }

        pendingPermissionResult = result
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val permissionIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(ACTION_USB_PERMISSION),
            flags
        )
        usbManager.requestPermission(device, permissionIntent)
    }

    fun printBytes(bytes: ByteArray, deviceId: Int?, result: MethodChannel.Result) {
        val device = findTargetDevice(deviceId)
        if (device == null) {
            result.error(
                "NO_PRINTER",
                "No se detectó ninguna impresora USB conectada por cable OTG.",
                null
            )
            return
        }

        if (!usbManager.hasPermission(device)) {
            // Guardamos el trabajo y pedimos permiso
            pendingPermissionResult = result
            pendingPrintBytes = bytes
            pendingDevice = device

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val permissionIntent = PendingIntent.getBroadcast(
                context,
                0,
                Intent(ACTION_USB_PERMISSION),
                flags
            )
            usbManager.requestPermission(device, permissionIntent)
            return
        }

        executor.execute {
            doPrint(device, bytes, result)
        }
    }

    private fun doPrint(device: UsbDevice, bytes: ByteArray, result: MethodChannel.Result?) {
        var connection: UsbDeviceConnection? = null
        var targetInterface: UsbInterface? = null
        try {
            val endpointInfo = findBulkOutEndpoint(device)
            if (endpointInfo == null) {
                mainHandler.post {
                    result?.error(
                        "NO_BULK_ENDPOINT",
                        "El dispositivo USB no tiene un canal de salida Bulk de impresión.",
                        null
                    )
                }
                return
            }

            targetInterface = endpointInfo.first
            val endpoint = endpointInfo.second

            connection = usbManager.openDevice(device)
            if (connection == null) {
                mainHandler.post {
                    result?.error(
                        "CANNOT_OPEN",
                        "No se pudo abrir la conexión con la impresora USB.",
                        null
                    )
                }
                return
            }

            if (!connection.claimInterface(targetInterface, true)) {
                mainHandler.post {
                    result?.error(
                        "CLAIM_FAILED",
                        "No se pudo reclamar la interfaz USB de la impresora.",
                        null
                    )
                }
                return
            }

            // Transferir en bloques de hasta 4096 bytes
            val chunkSize = 4096
            var totalSent = 0
            while (totalSent < bytes.size) {
                val len = minOf(chunkSize, bytes.size - totalSent)
                val buffer = bytes.copyOfRange(totalSent, totalSent + len)
                val sent = connection.bulkTransfer(endpoint, buffer, buffer.size, 5000)
                if (sent <= 0) {
                    throw Exception("Fallo en transferencia USB (código $sent en byte $totalSent)")
                }
                totalSent += sent
            }

            mainHandler.post {
                result?.success(mapOf("success" to true, "bytesWritten" to totalSent))
            }

        } catch (e: Exception) {
            mainHandler.post {
                result?.error("PRINT_ERROR", e.message ?: "Error desconocido al imprimir", null)
            }
        } finally {
            try {
                if (connection != null && targetInterface != null) {
                    connection.releaseInterface(targetInterface)
                }
            } catch (_: Exception) {}
            try {
                connection?.close()
            } catch (_: Exception) {}
        }
    }

    private fun findTargetDevice(deviceId: Int?): UsbDevice? {
        val devices = usbManager.deviceList.values
        if (devices.isEmpty()) return null

        if (deviceId != null) {
            val specific = devices.find { it.deviceId == deviceId }
            if (specific != null) return specific
        }

        // Prioridad 1: Dispositivo con clase de impresora estándar (Clase 7)
        for (device in devices) {
            if (device.deviceClass == UsbConstants.USB_CLASS_PRINTER) return device
            for (i in 0 until device.interfaceCount) {
                if (device.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_PRINTER) {
                    return device
                }
            }
        }

        // Prioridad 2: Cualquier dispositivo que tenga un Bulk OUT endpoint y no sea teclado/mouse/almacenamiento
        for (device in devices) {
            if (device.deviceClass == UsbConstants.USB_CLASS_HID ||
                device.deviceClass == UsbConstants.USB_CLASS_MASS_STORAGE) {
                continue
            }
            if (findBulkOutEndpoint(device) != null) {
                return device
            }
        }

        return null
    }

    private fun isPrinterDevice(device: UsbDevice): Boolean {
        if (device.deviceClass == UsbConstants.USB_CLASS_PRINTER) return true
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == UsbConstants.USB_CLASS_PRINTER) return true
        }
        return findBulkOutEndpoint(device) != null
    }

    private fun findBulkOutEndpoint(device: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        // Primero buscar interfaz de impresora
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == UsbConstants.USB_CLASS_PRINTER) {
                for (j in 0 until intf.endpointCount) {
                    val ep = intf.getEndpoint(j)
                    if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT) {
                        return Pair(intf, ep)
                    }
                }
            }
        }

        // Si no está marcada como clase 7, buscar cualquier interfaz con Bulk OUT (excluyendo HID y Storage)
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == UsbConstants.USB_CLASS_HID ||
                intf.interfaceClass == UsbConstants.USB_CLASS_MASS_STORAGE) {
                continue
            }
            for (j in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(j)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT) {
                    return Pair(intf, ep)
                }
            }
        }

        return null
    }
}
