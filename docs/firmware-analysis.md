# Аналіз прошивки GL.iNet GL-E750 V2 (Mudi V2) — `4.8.5_beta1`

## 1. Базова інформація про прошивку
- **Файл:** `e750-4.8.5_beta1-1005-0521-1779357101...` (OpenWrt sysupgrade tar)
- **Платформа:** `glinet_gl-e750` (`ath79/nand`, архітектура `mips_24kc`)
- **OpenWrt:** `22.03.4` (`r20123-38ccc47687`)
- **Ядро Linux:** `5.10.176` (`MIPS32_R2 32BIT`)
- **GL.iNet SDK:** `4.8.5`

## 2. Наявні ядерні модулі (USB / Modem)
У `/lib/modules/5.10.176/` присутні:
- `option.ko` — USB serial драйвер (AT / DM / NMEA порти)
- `qmi_wwan.ko` — QMI/RmNet мережевий драйвер (`/dev/cdc-wdm0` + `wwan0`)
- `cdc-wdm.ko`, `cdc-acm.ko`, `cdc_ether.ko`, `cdc_ncm.ko`, `huawei_cdc_ncm.ko`, `rndis_host.ko`
- **Відсутній:** `cdc_mbim.ko` (MBIM не підтримується в ядрі)

### Перевірка таблиць `usb_device_id` (`VID 0x2c7c` — Quectel)
- `option.ko` **вже містить** PID `0x030b` (спільний для `EM060K-GL` та `EM120K-GL`) і `0x030e`.
- `qmi_wwan.ko` **вже містить** PID `0x030b` і `0x030e`.

## 3. Userspace-компоненти GL.iNet
- `/etc/hotplug.d/usb/30_modem.sh`: `idProduct_arr` вже містить `030b` і `030e`, `idVendor_arr` містить `2c7c`.
- `/usr/bin/gl_modem` та `/usr/lib/oui-httpd/rpc/modem.so`: вже містять згадки `EM120K` та `EM060K & EM120K` (включно з діапазонами LTE).
- `/lib/netifd/proto/`: є `qmi.sh`, `qcm.sh`, `ncm.sh`, `3g.sh`, `wwan.sh` — **немає** `mbim.sh`.
- **Важливо:** жоден скрипт і жоден бінарник прошивки не перемикає `AT+QCFG="usbnet",0` автоматично (команда `AT+QCFG="usbnet"` у `gl_modem` викликається лише на читання).
- **Знайдена прогалина в антені:** `/usr/bin/tuning_switch_control` перевіряє `Revision:` на `*EM060KGL*` та `*EM05*`, але **не включає** `*EM120KGL*` для перемикання `set_tuning_switch $band`.

## 4. Основні гіпотези відсутності інтернету на EM120K
Оскільки модем вмикається і бачить SIM-карту (тобто `option.ko` прив'язався і AT-порт працює), найімовірніші причини:
1. **Режим USBNet = MBIM (`2`) замість QMI/RmNet (`0`)** — типова заводська/ноутбучна конфігурація EM120K-GL; без `cdc_mbim.ko` не створюються `/dev/cdc-wdm0` та `wwan0`.
2. **FCC Lock / режим зниженого живлення (`AT+CFUN=0` або `4`)** — часто трапляється на OEM-модемах EM120K-GL (Lenovo/Dell/HP), коли SIM видно, але радіомодуль заблоковано до FCC-авторизації.
3. **Несумісний USB VID:PID або конфігурація інтерфейсів** (наприклад, OEM VID/PID або інший номер інтерфейсу для QMI).
4. **Проблема на рівні QMI / `uqmi` / `raw_ip` / APN / `gl_modem`** під час підняття з'єднання.
