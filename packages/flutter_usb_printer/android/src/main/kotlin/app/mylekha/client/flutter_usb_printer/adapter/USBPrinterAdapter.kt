package app.mylekha.client.flutter_usb_printer.adapter

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.os.Build
import android.util.Base64
import android.util.Log
import android.widget.Toast
import java.nio.charset.Charset
import java.util.*


class USBPrinterAdapter {

    private var mInstance: USBPrinterAdapter? = null

    private val LOG_TAG = "Flutter USB Printer"
    private var mContext: Context? = null
    private var mUSBManager: UsbManager? = null
    private var mPermissionIndent: PendingIntent? = null
    private var mUsbDevice: UsbDevice? = null
    private var mUsbDeviceConnection: UsbDeviceConnection? = null
    private var mUsbInterface: UsbInterface? = null
    private var mEndPoint: UsbEndpoint? = null
    private var mReceiverRegistered = false  // guard against double-registration

    private val ACTION_USB_PERMISSION = "app.mylekha.client.flutter_usb_printer.USB_PERMISSION"

    fun getInstance(): USBPrinterAdapter? {
        if (mInstance == null) {
            mInstance = this
        }
        return mInstance
    }

    private val mUsbDeviceReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action
            if (ACTION_USB_PERMISSION == action) {
                synchronized(this) {
                    @Suppress("DEPRECATION")
                    val usbDevice: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                        if (usbDevice != null) {
                            Log.i(LOG_TAG, "Permission granted for device ${usbDevice.deviceId}, " +
                                    "vendor_id: ${usbDevice.vendorId} product_id: ${usbDevice.productId}")
                            mUsbDevice = usbDevice
                        } else {
                            Log.e(LOG_TAG, "Permission granted but device extra is null")
                        }
                    } else {
                        Log.w(LOG_TAG, "USB permission denied for device: ${usbDevice?.deviceName}")
                        Toast.makeText(context, "USB permission denied", Toast.LENGTH_LONG).show()
                    }
                }
            } else if (UsbManager.ACTION_USB_DEVICE_DETACHED == action) {
                if (mUsbDevice != null) {
                    Toast.makeText(context, "USB device disconnected", Toast.LENGTH_LONG).show()
                    closeConnectionIfExists()
                    mUsbDevice = null
                }
            }
        }
    }

    fun init(reactContext: Context?) {
        mContext = reactContext
        mUSBManager = mContext!!.getSystemService(Context.USB_SERVICE) as UsbManager

        // FLAG_MUTABLE is required on Android 12+ so the system can attach
        // EXTRA_DEVICE and EXTRA_PERMISSION_GRANTED when firing the intent.
        // FLAG_IMMUTABLE would silently strip those extras, causing a crash in onReceive.
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_MUTABLE else 0
        mPermissionIndent = PendingIntent.getBroadcast(
            mContext, 0, Intent(ACTION_USB_PERMISSION), piFlags
        )

        // Avoid double-registration when the activity is re-attached
        // (e.g. when the USB permission dialog temporarily pauses the app).
        if (!mReceiverRegistered) {
            val filter = IntentFilter(ACTION_USB_PERMISSION)
            filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            mContext!!.registerReceiver(mUsbDeviceReceiver, filter)
            mReceiverRegistered = true
        }

        Log.v(LOG_TAG, "USB Printer initialized")
    }

    fun closeConnectionIfExists() {
        if (mUsbDeviceConnection != null) {
            mUsbDeviceConnection!!.releaseInterface(mUsbInterface)
            mUsbDeviceConnection!!.close()
            mUsbInterface = null
            mEndPoint = null
            mUsbDeviceConnection = null
        }
    }

    fun getDeviceList(): List<UsbDevice> {
        if (mUSBManager == null) {
            Log.e(LOG_TAG, "USB Manager is not initialized")
            return emptyList()
        }
        return ArrayList(mUSBManager!!.deviceList.values)
    }

    fun selectDevice(vendorId: Int, productId: Int): Boolean {
        if (mUsbDevice == null || mUsbDevice!!.vendorId != vendorId || mUsbDevice!!.productId != productId) {
            closeConnectionIfExists()
            val usbDevices = getDeviceList()
            for (usbDevice in usbDevices) {
                if (usbDevice.vendorId == vendorId && usbDevice.productId == productId) {
                    Log.v(LOG_TAG, "Requesting permission for vendor_id: ${usbDevice.vendorId}, product_id: ${usbDevice.productId}")
                    closeConnectionIfExists()
                    mUSBManager!!.requestPermission(usbDevice, mPermissionIndent)
                    return true
                }
            }
            return false
        }
        return true
    }

    private fun openConnection(): Boolean {
        if (mUsbDevice == null) {
            Log.e(LOG_TAG, "USB device is not initialized — grant permission first")
            return false
        }
        if (mUSBManager == null) {
            Log.e(LOG_TAG, "USB Manager is not initialized")
            return false
        }
        if (mUsbDeviceConnection != null) {
            Log.i(LOG_TAG, "USB Connection already open")
            return true
        }
        // Search every interface for a bulk-OUT endpoint rather than assuming
        // interface 0. Some printer boards (e.g. STM32 CDC-ACM/Virtual COM
        // Port chips) expose interface 0 as a control-only interface with no
        // bulk endpoint — the real data interface is a later index.
        for (ifaceIndex in 0 until mUsbDevice!!.interfaceCount) {
            val usbInterface = mUsbDevice!!.getInterface(ifaceIndex)
            for (i in 0 until usbInterface.endpointCount) {
                val ep = usbInterface.getEndpoint(i)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT) {
                    val usbDeviceConnection = mUSBManager!!.openDevice(mUsbDevice)
                    if (usbDeviceConnection == null) {
                        Log.e(LOG_TAG, "Failed to open USB connection")
                        return false
                    }
                    return if (usbDeviceConnection.claimInterface(usbInterface, true)) {
                        mEndPoint = ep
                        mUsbInterface = usbInterface
                        mUsbDeviceConnection = usbDeviceConnection
                        Log.i(LOG_TAG, "USB connection opened on interface $ifaceIndex")
                        true
                    } else {
                        usbDeviceConnection.close()
                        Log.e(LOG_TAG, "Failed to claim USB interface $ifaceIndex")
                        false
                    }
                }
            }
        }
        Log.e(LOG_TAG, "No bulk-OUT endpoint found on any interface")
        return false
    }

    fun printText(text: String): Boolean {
        val isConnected = openConnection()
        return if (isConnected) {
            Thread {
                val bytes = text.toByteArray(Charset.forName("UTF-8"))
                val b = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, bytes, bytes.size, 100000)
                Log.i(LOG_TAG, "printText status: $b")
            }.start()
            true
        } else {
            Log.v(LOG_TAG, "printText: not connected")
            false
        }
    }

    fun printRawText(data: String): Boolean {
        val isConnected = openConnection()
        return if (isConnected) {
            Thread {
                val bytes = Base64.decode(data, Base64.DEFAULT)
                val b = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, bytes, bytes.size, 100000)
                Log.i(LOG_TAG, "printRawText status: $b")
            }.start()
            true
        } else {
            Log.v(LOG_TAG, "printRawText: not connected")
            false
        }
    }

    fun write(bytes: ByteArray): Boolean {
        val isConnected = openConnection()
        return if (isConnected) {
            Thread {
                val b = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, bytes, bytes.size, 100000)
                Log.i(LOG_TAG, "write status: $b")
            }.start()
            true
        } else {
            Log.v(LOG_TAG, "write: not connected")
            false
        }
    }
}
