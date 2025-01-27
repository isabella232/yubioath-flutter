/*
 * Copyright (C) 2022 Yubico.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.yubico.authenticator.yubikit

import android.os.Build
import com.yubico.authenticator.SdkVersion
import com.yubico.authenticator.device.Info
import com.yubico.authenticator.management.model
import com.yubico.yubikit.android.transport.usb.UsbYubiKeyDevice
import com.yubico.yubikit.core.Transport
import com.yubico.yubikit.core.UsbPid
import com.yubico.yubikit.core.Version
import com.yubico.yubikit.core.YubiKeyDevice
import com.yubico.yubikit.management.DeviceConfig
import com.yubico.yubikit.management.DeviceInfo
import com.yubico.yubikit.management.FormFactor
import java.util.regex.Pattern

class SkyHelper {
    companion object {
        private val VERSION_0 = Version(0, 0, 0)
        private val VERSION_3 = Version(3, 0, 0)
        private val VERSION_4 = Version(4, 0, 0)

        private val USB_VERSION_STRING_PATTERN: Pattern =
            Pattern.compile("\\b(\\d{1,3})\\.(\\d)(\\d+)\\b")

        /**
         * Retrieves a [DeviceInfo] from USB Security YubiKey (SKY).
         *
         * Should be only used as last resort when all other DeviceInfo queries failed because
         * the returned information might not be accurate.
         *
         * @param device YubiKeyDevice to get DeviceInfo for. Should be USB and SKY device
         * @return [DeviceInfo] instance initialized with information from USB descriptors.
         * @throws IllegalArgumentException if [device] is not instance of [UsbYubiKeyDevice] or
         * if the USB device has wrong PID
         */
        fun getDeviceInfo(device: YubiKeyDevice): Info {
            require(device is UsbYubiKeyDevice)

            val pid = device.pid

            require(pid in listOf(UsbPid.YK4_FIDO, UsbPid.SKY_FIDO, UsbPid.NEO_FIDO))

            val usbVersion = validateVersionForPid(getVersionFromUsbDescriptor(device), pid)

            // build DeviceInfo containing only USB product name and USB version
            // we assume this is a Security Key based on the USB PID
            return DeviceInfo(
                DeviceConfig.Builder().enabledCapabilities(Transport.USB, 0).build(),
                null,
                usbVersion,
                FormFactor.UNKNOWN,
                mapOf(Transport.USB to 0),
                false,
                false,
                true
            ).model(device.usbDevice.productName ?: "YubiKey Security Key", false, pid.value)
        }

        // try to convert USB version to YubiKey version
        private fun getVersionFromUsbDescriptor(device: UsbYubiKeyDevice): Version {
            if (SdkVersion.ge(Build.VERSION_CODES.M)) {
                val version = device.usbDevice.version
                val match = USB_VERSION_STRING_PATTERN.matcher(version)

                if (match.find()) {
                    val major = match.group(1)?.toByte() ?: 0
                    val minor = match.group(2)?.toByte() ?: 0
                    val patch = match.group(3)?.toByte() ?: 0
                    return Version(major, minor, patch)
                }
            }

            return VERSION_0
        }

        /**
         * Check whether usbVersion is in expected range defined by UsbPid
         *
         * @return original version or [Version(0,0,0)] indicating invalid/unknown version
         */
        private fun validateVersionForPid(usbVersion: Version, pid: UsbPid): Version {
            if ((pid == UsbPid.NEO_FIDO && usbVersion.inRange(VERSION_3, VERSION_4)) ||
                (pid == UsbPid.SKY_FIDO && usbVersion.isAtLeast(VERSION_3)) ||
                (pid == UsbPid.YK4_FIDO && usbVersion.isAtLeast(VERSION_4))
            ) {
                return usbVersion
            }
            return VERSION_0
        }

        /** Check if this version is at least v1 and less than v2
         * @return true if this is in range [v1,v2)
         */
        private fun Version.inRange(v1: Version, v2: Version): Boolean {
            return this >= v1 && this < v2
        }

        /** Check if this version is at least v
         * @return true if this >= v
         */
        private fun Version.isAtLeast(v: Version): Boolean {
            return this >= v
        }
    }
}