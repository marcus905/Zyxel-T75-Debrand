<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Obtaining a root shell on Odido firmware

The converter requires a real Linux root shell on the running Odido firmware. On the tested Odido T75, a serial login by itself does **not** provide the shell required by the converter, so the working path is:

1. attach UART;
2. log in to the Odido web UI as `supervisor`;
3. obtain the current Linux root password from the serial log while creating a configuration backup;
4. expose the hidden stock Zyxel SSH controls;
5. connect over SSH as `root`.

This procedure assumes physical ownership/control of the router and local LAN access.

## 1. Open the router and attach UART

Use a **3.3 V TTL** serial adapter configured for `115200 8N1`, with no flow control.

Observed T75 header:

```text
1 . . . 5

1  GND
2  unused/key
3  RXD
4  TXD
5  NC
```

Connect router GND -> adapter GND, router RXD -> adapter TX, and router TXD -> adapter RX. Do **not** connect adapter VCC.

Keep the serial terminal logging while using the web UI.

## 2. Log in to the Odido web UI as supervisor

Default management address:

```text
http://192.168.1.1/
```

Use:

```text
username: supervisor
password: :Uo1=8mR~`f.t?;MVsfk&e;u!L|;'4
```

If it does not work on the older firmware family covered here, factory-reset the router with the RESET pin and retry before connecting WAN.

The fixed `supervisor` credential is the privileged **web UI** credential. It is not the per-device Linux root password used later for SSH.

> Newer Odido firmware revisions may no longer expose the same supervisor credential.

## 3. Recover the current Linux root password

With UART logging active:

1. Open **Maintenance -> Backup/Restore**.
2. Create/download a configuration backup.
3. Watch the serial log while the backup is generated.

The firmware prints a command similar to:

```text
sysCmd = openssl enc -e -des3 -md md5 -pass pass:ROOT_PASSWORD -in /tmp/zcfg_config.json -out /tmp/zcfg_config.encrypt, zcmdEncryptConfig 531
```

The value after `-pass pass:` and before the following space is the current Linux **root password**.

Record it exactly. It is used later with:

```sh
ssh root@192.168.1.1
```

## 4. Enable the stock management services

This follows the stock-firmware method documented for the closely related Odido T-56 / Zyxel EX5601-T1 in OpenWrt forum post #815:

https://forum.openwrt.org/t/adding-openwrt-support-for-zyxel-ex5601-t0/155914/815

### SP Domain

Open **Maintenance -> SP Domain**.

On the first tab, enable/check all applicable management services and apply.

On the second tab, set the trusted source network to:

```text
192.168.1.0/24
```

Apply/save. Keep the trust range limited to the local LAN.

### Remote Management

Open **Maintenance -> Remote Management**.

The Odido customization hides protocols such as SSH from this page in JavaScript rather than removing the backend service.

Open browser developer tools and locate:

```text
top
  -> 192.168.1.1
    -> static
      -> js
        -> app.maintenance.js
```

In Chromium-based browsers:

1. open **Sources**;
2. locate `app.maintenance.js`;
3. right-click it and choose **Override content** / enable Local Overrides;
4. search for `findAndRemove`.

You will find logic which conditionally removes protocol entries, including calls similar to:

```javascript
n.findAndRemove(t.Object, "Name", "HTTP")
n.findAndRemove(t.Object, "Name", "FTP")
n.findAndRemove(t.Object, "Name", "TELNET")
n.findAndRemove(t.Object, "Name", "SSH")
n.findAndRemove(t.Object, "Name", "SNMP")
```

For the relevant filtering block, replace the protocol-name strings with empty strings so the matching entries are no longer removed, for example:

```javascript
n.findAndRemove(t.Object, "Name", "")
```

Do this for the protocol-removal calls in that block, save the override, then refresh the router page.

After refresh, the hidden management services should appear. Enable the required services for LAN and Trust Domain. WLAN may also be enabled if desired.

Then open the **Trust Domain** tab and add:

```text
192.168.1.0/24
```

Apply/save.

## 5. Connect as root over SSH

From a machine on the router LAN:

```sh
ssh root@192.168.1.1
```

Use the **root password recovered from the Backup/Restore serial log**, not the fixed supervisor web password.

Older stock SSH implementations may require a legacy host-key or cipher algorithm. If OpenSSH refuses the connection, enable only the specific legacy algorithm named in the client error for this host rather than weakening SSH globally.

## 6. Verify that the shell is suitable for the converter

Run:

```sh
id
cat /proc/cmdline
cat /proc/mtd
ubinfo -a
```

Expected:

- `id` reports UID 0/root;
- `/proc/mtd` is readable;
- the UBI layout is visible through `ubinfo`.

Then continue with [HOWTO.md](HOWTO.md).

## Why ATCK is not the primary T75 procedure here

Some related Zyxel firmware exposes credentials through ZySH commands such as `sys atck`. OpenWrt forum post #815 uses that path on the EX5601/T-56.

For the T75 firmware tested by this project, the dependable procedure was instead to obtain the current Linux root password from the serial log generated during **Backup/Restore**, then enable SSH through the stock management controls.

That distinction matters: a bootloader or ZySH credential dump is not, by itself, the same as having a usable Linux root shell.

## Provenance

The hidden-service technique is derived from the OpenWrt community work on the Odido T-56 / Zyxel EX5601-T1, especially post #815 in the EX5601 support thread. The T75-specific UART pinout, Backup/Restore root-password recovery path, and final `root` SSH workflow were validated during this project's hardware conversion.
