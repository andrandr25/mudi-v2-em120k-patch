# GL.iNet GL-E750 V2 (Mudi V2) — патч підтримки модему Quectel EM120K-GL

Легкий системний SSH-патч / плагін для роутера **GL.iNet GL-E750 V2 (Mudi V2)** (OpenWrt `22.03.4`, Linux `5.10.176`, GL.iNet SDK `4.8.x`), який автоматично запускає інтернет після заміни штатного модему **Quectel EM060K-GL** на **Quectel EM120K-GL** (LTE-A Cat 12) без перезбірки прошивки.

## Чому на EM120K-GL бачить SIM-карту, але немає інтернету?

Детальний бінарний розбір прошивки `e750-4.8.5_beta1` ([docs/firmware-analysis.md](docs/firmware-analysis.md)) показав:

1. **Відсутній драйвер `cdc_mbim.ko` у ядрі Mudi V2:**
   - Модеми `EM060K-GL` та `EM120K-GL` мають однаковий USB VID:PID (`2c7c:030b`).
   - У `option.ko` та `qmi_wwan.ko` цей VID:PID вже прописаний, але `qmi_wwan.ko` прив'язується **тільки** до класу `ff/ff/ff` (режим **RmNet/QMI**, `AT+QCFG="usbnet",0`).
   - Більшість куплених `EM120K-GL` постачаються в режимі **MBIM** (`AT+QCFG="usbnet",2`). Через це `option.ko` створює `/dev/ttyUSB*` (роутер бачить модем і SIM-карту), але `/dev/cdc-wdm0` і `wwan0` **не створюються**, і `qcm.sh` / `qmi.sh` не можуть підняти з'єднання.
2. **Можливий FCC Lock / `CFUN` ≠ 1 (на OEM-модулях):**
   - Частина модулів `EM120K-GL` (Lenovo/Dell/HP OEM) стартує в режимі зниженого живлення (`CFUN=0/4/7`) до виконання QMI DMS FCC Auth (`uqmi --fcc-auth`).
3. **Антенний тюнер `/usr/bin/tuning_switch_control`:**
   - Штатний скрипт перевіряє лише `*EM060KGL*` та `*EM05*`, ігноруючи `*EM120KGL*`, тому антенний перемикач Mudi V2 не підлаштовується під активний LTE-бенд.
4. **Старі параметри UCI після EM060K:**
   - Секція `network.modem_*` може містити застарілий `device`/`node` або `disabled='1'` після хотплаг-відновлення.

## Що робить патч

- Перевіряє `AT+QCFG="usbnet"` і за потреби автоматично перемикає модем у **RmNet/QMI (`0`)** з коректним перезавантаженням (`AT+CFUN=1,1`) та очікуванням `/dev/cdc-wdm0` і `wwan0`.
- Перевіряє прив'язку `qmi_wwan` (включно з динамічним `new_id` для нестандартних OEM VID:PID) і вмикає `raw_ip=Y`.
- Якщо радіомодуль заблокований (`CFUN` ≠ 1) — автоматично виконує `uqmi --fcc-auth`, `--set-device-operating-mode online` та `AT+CFUN=1`, а також вмикає `AT+QMBNCFG="AutoSel",1`.
- Патчить `/usr/bin/tuning_switch_control` (із резервною копією) для підтримки `*EM120KGL*`.
- Оновлює UCI-конфігурацію `network.modem_*` та запускає підключення (`ifup` / `gl_modem connect-auto`).
- Додає автозапуск (`/etc/init.d/em120k-fix`), USB-хотплаг (`/etc/hotplug.d/usb/25_em120k_fix.sh`) і збереження після `sysupgrade` (`/lib/upgrade/keep.d/em120k-fix`).

## Встановлення по SSH

### Варіант 1: Копіювання на роутер через `scp` (працює навіть без інтернету на роутері)
На комп'ютері, підключеному до Mudi V2 по Ethernet:
```sh
scp -O -r mudi-em120k-patch root@192.168.8.1:/tmp/
ssh root@192.168.8.1 "sh /tmp/mudi-em120k-patch/install.sh"
```

### Варіант 2: Встановлення однією командою з GitHub (якщо на роутері є тимчасовий Wi-Fi/WAN)
```sh
ssh root@192.168.8.1 "wget -qO- https://github.com/<USER>/<REPO>/archive/refs/heads/main.tar.gz | tar -xz -C /tmp && sh /tmp/<REPO>-main/install.sh"
```

## Команди після встановлення

```sh
# Застосувати фікс і підняти інтернет
em120k-fix apply

# Показати поточний стан модему, USBNet, CFUN, SIM, сигналу та IP
em120k-fix status

# Зібрати знеособлений діагностичний звіт у /tmp/em120k-diag.log (без IMEI/ICCID)
em120k-fix diag
```

## Видалення (відкат до стокової прошивки)

```sh
sh /tmp/mudi-em120k-patch/uninstall.sh
```

## Тестування

У репозиторії є автоматизований набір тестів (`tests/test_em120k_fix.sh`), який перевіряє синтаксис POSIX `sh`, встановлення/видалення на реальному зрізі прошивки `4.8.5_beta1`, перемикання MBIM→QMI, розблокування FCC/CFUN, `raw_ip`, відновлення UCI та знеособлення діагностики:

```sh
sh tests/test_em120k_fix.sh
```
