# Аналіз прошивки GL.iNet GL-E750 V2 (Mudi V2) — `4.8.5_beta1`

## 1. Базова інформація про прошивку
- **Файл:** `e750-4.8.5_beta1-1005-0521-1779357101...` (OpenWrt sysupgrade tar)
- **Платформа:** `glinet_gl-e750` (`ath79/nand`, архітектура `mips_24kc`)
- **OpenWrt:** `22.03.4` (`r20123-38ccc47687`)
- **Ядро Linux:** `5.10.176` (`MIPS32_R2 32BIT`, big-endian)
- **GL.iNet SDK:** `4.8.5`

## 2. Аналіз ядерних модулів (`/lib/modules/5.10.176/`)
Наявні USB/модемні драйвери:
- `option.ko` — USB serial драйвер (AT / DM / NMEA порти)
- `qmi_wwan.ko` — QMI/RmNet мережевий драйвер (`/dev/cdc-wdm0` + `wwan0`)
- `cdc-wdm.ko`, `cdc-acm.ko`, `cdc_ether.ko`, `cdc_ncm.ko`, `huawei_cdc_ncm.ko`, `rndis_host.ko`
- **Критично відсутній:** `cdc_mbim.ko` (MBIM у ядрі не зібраний)

### Точний розбір таблиць `struct usb_device_id` для `0x2c7c:0x030b` (EM060K-GL / EM120K-GL)
Бінарний розбір `option.ko` та `qmi_wwan.ko` показав:
```text
option.ko:
  mf=0x383 vid=0x2c7c pid=0x030b intClass=0xff/0x00/0x40  (AT / Modem)
  mf=0x383 vid=0x2c7c pid=0x030b intClass=0xff/0xff/0x30  (DM / DIAG)
  mf=0x383 vid=0x2c7c pid=0x030b intClass=0xff/0xff/0x40  (NMEA / AT)

qmi_wwan.ko:
  mf=0x383 vid=0x2c7c pid=0x030b intClass=0xff/0xff/0xff  (RmNet / QMI)
```

**Висновок на рівні ядра:**
- `qmi_wwan.ko` прив'язується до `2c7c:030b` **виключно** тоді, коли мережевий інтерфейс (interface 4) має клас `ff/ff/ff`, тобто модем працює в режимі **RmNet/QMI (`AT+QCFG="usbnet",0`)**.
- Коли `EM120K-GL` працює в заводському/ноутбучному режимі **MBIM (`AT+QCFG="usbnet",2`)**, інтерфейс 4 має клас `02/0e/00` (CDC-MBIM):
  - `option.ko` все одно прив'язується до `ff/00/40`, `ff/ff/30`, `ff/ff/40` → створюються `/dev/ttyUSB0..3` → GL.iNet бачить модем і SIM-карту через AT-команди;
  - `qmi_wwan.ko` **не прив'язується**, а `cdc_mbim.ko` **відсутній** → `/dev/cdc-wdm0` і `wwan0` не створюються → з'єднання не піднімається.
- Аналогічно в режимах **ECM (`1`)** або **RNDIS (`3`)** не створюється `/dev/cdc-wdm0`, і скрипти `qcm.sh` / `qmi.sh` завершуються з помилкою `NO_DEVICE`.

## 3. Userspace-компоненти GL.iNet
- **Основний dialer:** `/usr/bin/qcm` (`Quectel QConnectManager`) + `/lib/netifd/proto/qcm.sh`, резервний — `/sbin/uqmi` + `/lib/netifd/proto/qmi.sh`. Протоколу `mbim.sh` у `/lib/netifd/proto/` **немає**.
- **`/sbin/uqmi`:** має вбудовану підтримку `--fcc-auth` та `--set-device-operating-mode online` (корисно для OEM-модулів EM120K-GL із FCC Lock / `CFUN` ≠ 1).
- **`/etc/hotplug.d/usb/30_modem.sh`:** вже містить `030b` і `030e` у `idProduct_arr`, `2c7c` у `idVendor_arr`.
- **`/usr/bin/gl_modem` та `/usr/lib/oui-httpd/rpc/modem.so`:** вже містять профілі `EM120K` та `EM060K & EM120K`, але **ніде не перемикають** `AT+QCFG="usbnet",0` автоматично (`AT+QCFG="usbnet"` викликається лише на читання).
- **`/usr/bin/tuning_switch_control` (виявлений баг):**
  ```sh
  case $version in
      *EM060KGL*|\
      *EM05*)
  ```
  Відсутній `*EM120KGL*`, через що не викликається `set_tuning_switch $band` для налаштування антенного перемикача Mudi V2 під активний LTE-бенд.

## 4. Архітектура рішення (SSH-патч / плагін)
Замість перезбірки всієї прошивки, оптимальне рішення для OpenWrt/GL.iNet — легкий системний патч (`em120k-fix`), який встановлюється по SSH, зберігається після перезавантажень і `sysupgrade`, та автоматично виконує:
1. Перевірку й перемикання `AT+QCFG="usbnet",0` (RmNet/QMI) із перезавантаженням модему (`AT+CFUN=1,1`) та очікуванням появи `/dev/cdc-wdm0` і `wwan0`.
2. Динамічну прив'язку `qmi_wwan` (якщо модем має нестандартний OEM VID:PID) і перевірку `raw_ip`.
3. Зняття FCC Lock / вихід із Low Power (`uqmi --fcc-auth`, `--set-device-operating-mode online`, `AT+CFUN=1`) та увімкнення `AT+QMBNCFG="AutoSel",1`.
4. Патч `/usr/bin/tuning_switch_control` для підтримки `*EM120KGL*`.
5. Очищення/актуалізацію UCI-конфігурації `network.modem_*` (`device`, `node`, `disabled=0`) і запуск `gl_modem connect-auto` / `ifup`.
