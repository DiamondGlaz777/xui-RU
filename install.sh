#!/bin/bash
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
fuls='\033[0;45m'
plain='\033[0m'
echo -e "${red}Создатель: ${green} t.me/DiamondGlaz${plain}"
cur_dir=$(pwd)
# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Ошибка: ${plain} Пожалуйста запустите от имени ROOT.Напишите sudo su " && exit 1
# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Ваша ОС не подходит!!" >&2
    exit 1
fi
echo -e "${green}Ваша ОС: $release ${plain}"
echo -e "${yellow}Начинаем установку 3x-ui.Это займёт ${red}некоторое время. ${plain}"
arch3xui() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    *) echo -e "${green}Процессор не поддерживается! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

os_version=""
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Пожалуйста, используйте CentOS 8 или выше ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 20 ]]; then
        echo -e "${red} Пожалуйста, используйте Ubuntu 20 или выше${plain}\n" && exit 1
    fi

elif [[ "${release}" == "fedora" ]]; then
    if [[ ${os_version} -lt 36 ]]; then
        echo -e "${red} Пожалуйста, используйте Fedora 36 или выше!${plain}\n" && exit 1
    fi

elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 11 ]]; then
        echo -e "${red} Пожалуйста, используйте Debian 11 или выше ${plain}\n" && exit 1
    fi

elif [[ "${release}" == "almalinux" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} Пожалуйста, используйте AlmaLinux 9 или выше ${plain}\n" && exit 1
    fi

elif [[ "${release}" == "rocky" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} Пожалуйста, используйте RockyLinux 9 или выше ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "arch" ]]; then
    echo "Ваша ОС: ArchLinux"
elif [[ "${release}" == "manjaro" ]]; then
    echo "Ваша ОС:  Manjaro"
elif [[ "${release}" == "armbian" ]]; then
    echo "Ваша ОС: Armbian"

else
    echo -e "${red}Ваша ОС не подходит!${plain}" && exit 1
fi
install_iplimit() {
    if ! command -v fail2ban-client &>/dev/null; then
        echo -e "${green}Fail2ban is not installed. Installing now...!${plain}\n"

        # Check the OS and install necessary packages
        case "${release}" in
        ubuntu | debian)
            apt update && apt install fail2ban -y
            ;;
        centos | almalinux | rocky)
            yum update -y && yum install epel-release -y
            yum -y install fail2ban
            ;;
        fedora)
            dnf -y update && dnf -y install fail2ban
            ;;
        *)
            echo -e "${red}Unsupported operating system. Please check the script and install the necessary packages manually.${plain}\n"
            exit 1
            ;;
        esac

        if ! command -v fail2ban-client &>/dev/null; then
            echo -e "${red}Fail2ban installation failed.${plain}\n"
            exit 1
        fi

        echo -e "${green}Fail2ban installed successfully!${plain}\n"
    else
        echo -e "${yellow}Fail2ban is already installed.${plain}\n"
    fi

    iplimit_remove_conflicts

    if ! test -f "${iplimit_banned_log_path}"; then
        touch ${iplimit_banned_log_path}
    fi

    # Check if service log file exists so fail2ban won't return error
    if ! test -f "${iplimit_log_path}"; then
        touch ${iplimit_log_path}
    fi

    # we didn't pass the bantime here to use the default value
    create_iplimit_jails

    if ! systemctl is-active --quiet fail2ban; then
        systemctl start fail2ban
        systemctl enable fail2ban
    else
        systemctl restart fail2ban
    fi
    systemctl enable fail2ban

} &>/dev/null

create_iplimit_jails() {
    # Use default bantime if not passed => 15 minutes
    local bantime="${1:-15}"

    # Uncomment 'allowipv6 = auto' in fail2ban.conf
    sed -i 's/#allowipv6 = auto/allowipv6 = auto/g' /etc/fail2ban/fail2ban.conf

    cat << EOF > /etc/fail2ban/jail.d/3x-ipl.conf
[3x-ipl]
enabled=true
filter=3x-ipl
action=3x-ipl
logpath=${iplimit_log_path}
maxretry=2
findtime=32
bantime=${bantime}m
EOF

    cat << EOF > /etc/fail2ban/filter.d/3x-ipl.conf
[Definition]
datepattern = ^%%Y/%%m/%%d %%H:%%M:%%S
failregex   = \[LIMIT_IP\]\s*Email\s*=\s*<F-USER>.+</F-USER>\s*\|\|\s*SRC\s*=\s*<ADDR>
ignoreregex =
EOF

    cat << EOF > /etc/fail2ban/action.d/3x-ipl.conf
[INCLUDES]
before = iptables-allports.conf

[Definition]
actionstart = <iptables> -N f2b-<name>
              <iptables> -A f2b-<name> -j <returntype>
              <iptables> -I <chain> -p <protocol> -j f2b-<name>

actionstop = <iptables> -D <chain> -p <protocol> -j f2b-<name>
             <actionflush>
             <iptables> -X f2b-<name>

actioncheck = <iptables> -n -L <chain> | grep -q 'f2b-<name>[ \t]'

actionban = <iptables> -I f2b-<name> 1 -s <ip> -j <blocktype>
            echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   BAN   [Email] = <F-USER> [IP] = <ip> banned for <bantime> seconds." >> ${iplimit_banned_log_path}

actionunban = <iptables> -D f2b-<name> -s <ip> -j <blocktype>
              echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   UNBAN   [Email] = <F-USER> [IP] = <ip> unbanned." >> ${iplimit_banned_log_path}

[Init]
EOF

    echo -e "${green}Ip Limit jail files created with a bantime of ${bantime} minutes.${plain}"
} &>/dev/null

install_base() {
    case "${release}" in
    centos | almalinux | rocky)
        yum -y update && yum install -y -q wget curl tar
        ;;
    fedora)
        dnf -y update && dnf install -y -q wget curl tar
        dnf install translate-shell
        ;;
    arch | manjaro)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar
        pacman -S translate-shell
        ;;
    debian)
        apt update && apt upgrade && apt install translate-shell && apt install -y -q wget curl tar
        
        ;;
    *)
        apt-get update && apt install -y -q wget curl tar
        apt install translate-shell
        ;;
    esac
    cd /usr/local/
    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/DiamondGlaz777/xui-RU/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            exit 1
        fi
        echo -e "${green}Получил последнюю версию x-ui: ${last_version}, начинаю установку...${plain}"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-$(arch3xui).tar.gz https://github.com/DiamondGlaz777/xui-RU/releases/download/${last_version}/x-ui-linux-$(arch3xui).tar.gz
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/DiamondGlaz777/xui-RU/releases/download/${last_version}/x-ui-linux-$(arch3xui).tar.gz"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-$(arch3xui).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-$(arch3xui).tar.gz
    rm x-ui-linux-$(arch3xui).tar.gz -f
    cd x-ui
    chmod +x x-ui

    # Check the system's architecture and rename the file accordingly
    if [[ $(arch3xui) == "armv5" || $(arch3xui) == "armv6" || $(arch3xui) == "armv7" ]]; then
        mv bin/xray-linux-$(arch3xui) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi

    chmod +x x-ui bin/xray-linux-$(arch3xui)
    cp -f x-ui.service /etc/systemd/system/
    chmod +x /usr/bin/x-ui
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    /usr/local/x-ui/x-ui setting -username freenet -password freenet
    /usr/local/x-ui/x-ui setting -port 2024
    /usr/local/x-ui/x-ui migrate
    sudo mkdir -p /etc/ssl/v2ray/
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -nodes -subj "/C=XX/ST=StateName/L=CityName/O=CompanyName/OU=CompanySectionName/CN=CommonNameOrHostname" -keyout /etc/ssl/v2ray/priv.key -out /etc/ssl/v2ray/cert.pub
    apt install speedtest-cli
    testspeed=$(speedtest-cli --simple | awk '/Download/{print $2,$3}')
    sudo iptables -I INPUT -p tcp --dport 1:65535 -j ACCEPT
    sudo iptables -I OUTPUT -p tcp --dport 1:65535 -j ACCEPT
    sudo iptables -I INPUT -p udp --dport 1:65535 -j ACCEPT
    sudo iptables -I OUTPUT -p udp --dport 1:65535 -j ACCEPT
    sudo /sbin/iptables-save
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
    echo "10" > /proc/sys/kernel/panic
}  &> /dev/null

swapp() {
if [[ "${memor}" > 500000 ]]; then
        echo -e " ${yellow}Swap на 1Гб создан!${plain}"
        echo -e " ${fuls}Буст включается при свободной ОЗУ<500MB!${plain}"
        sudo fallocate -l 1G /swapfile &> /dev/null
        sudo mkswap /swapfile &> /dev/null
        sudo swapon /swapfile &> /dev/null
        echo '/swapfile none swap defaults,pri=10 0 0' | sudo tee -a /etc/fstab &> /dev/null
        echo 'vm.min_free_kbytes=500000' | sudo tee -a /etc/sysctl.conf &> /dev/null
        echo 'vm.vfs_cache_pressure=1000' | sudo tee -a /etc/sysctl.conf &> /dev/null
        echo 'vm.overcommit_memory=1' | sudo tee -a /etc/sysctl.conf &> /dev/null
        sudo sysctl -p &> /dev/null
elif [[ "$memor" > 200000 ]]; then
        echo -e " ${yellow}Swap на 1Гб создан!${plain}"
        echo -e " ${fuls}Буст включается при свободной ОЗУ<200MB!${plain}"
        sudo fallocate -l 1G /swapfile &> /dev/null
        sudo mkswap /swapfile &> /dev/null
        sudo swapon /swapfile &> /dev/null
        echo '/swapfile none swap defaults,pri=10 0 0' | sudo tee -a /etc/fstab &> /dev/null
        echo 'vm.min_free_kbytes=200000' | sudo tee -a /etc/sysctl.conf &> /dev/null
        echo 'vm.vfs_cache_pressure=1000' | sudo tee -a /etc/sysctl.conf &> /dev/null
        echo 'vm.overcommit_memory=1' | sudo tee -a /etc/sysctl.conf &> /dev/null
        sudo sysctl -p &> /dev/null
elif [[ "$memor" > 700000 ]]; then
        echo -e " ${yellow}Swap на 1Гб создан!${plain}"
        echo -e " ${fuls}Буст включается при свободной ОЗУ<400MB!${plain}"
        sudo fallocate -l 1G /swapfile &> /dev/null
        sudo mkswap /swapfile &> /dev/null
        sudo swapon /swapfile &> /dev/null
        echo '/swapfile none swap defaults,pri=10 0 0' | sudo tee -a /etc/fstab &> /dev/null
        echo 'vm.min_free_kbytes=400000' | sudo tee -a /etc/sysctl.conf &> /dev/null
        echo 'vm.vfs_cache_pressure=1000' | sudo tee -a /etc/sysctl.conf &> /dev/null
        echo 'vm.overcommit_memory=1' | sudo tee -a /etc/sysctl.conf &> /dev/null
        sudo sysctl -p &> /dev/null

elif [[ "${memor}" > 1000000 ]]; then
        echo -e " ${yellow}Swap на 2Гб создан!${plain}"
        echo -e " ${fuls}Буст включается при свободной ОЗУ<1ГБ!${plain}"
        sudo fallocate -l 1G /swapfile &> /dev/null
        sudo mkswap /swapfile &> /dev/null
        sudo swapon /swapfile &> /dev/null
        echo '/swapfile none swap defaults,pri=10 0 0' | sudo tee -a /etc/fstab &> /dev/null
        echo 'vm.min_free_kbytes=2000000' | sudo tee -a /etc/sysctl.conf &> /dev/null
        echo 'vm.vfs_cache_pressure=1000' | sudo tee -a /etc/sysctl.conf &> /dev/null
        echo 'vm.overcommit_memory=1' | sudo tee -a /etc/sysctl.conf &> /dev/null
        sudo sysctl -p &> /dev/null
elif [[ "${memor}" > 2000000 ]]; then
        echo -e "${red}Вам не требуется файл подкачки!${plain}"
else
    exit
fi
}


bust() {
echo -e "${green}Доп меню:${plain}"
echo -e "${yellow}1 -Swap без автоперезагрузки${plain}"
echo -e "${yellow}2 -Swap с автоперезагрузкой в полночь${plain}"
echo -e "${yellow}3 -Сменить время бана клиентов по IP ${plain}"
echo -e "${yellow}4 -Удалить команду x-ui${plain}"
echo -e "${yellow}5 -Посмотреть ip-адреса сервера${plain}"
echo -e "${yellow}6 -Создать нового рут пользователя${plain}"
echo -e "${red}Любое другое ,чтобы скипнуть меню.${plain}"
read -p "": conq1
if [[ "${conq1}" == "1" ]]; then
        swapp $1
elif [[ "${conq1}" == "2" ]]; then
        echo -e " ${green}Автоперезагрузка ровно в полночь по системному времени vps!${plain}"
        echo '0 0 * * * root /sbin/shutdown -r' | sudo tee -a /etc/cron.d/reboot &> /dev/null
        echo '1 0 * * * root sudo swapoff -a' | sudo tee -a /etc/cron.d/reboot &> /dev/null
        echo '2 0 * * * root sudo swapon -a ' | sudo tee -a /etc/cron.d/reboot &> /dev/null
        swapp $1
elif [[ "${conq1}" == "3" ]]; then      
        read -rp "Укажите время бана [По умолчанию: 30 минут]: " NUM
        if [[ $NUM =~ ^[0-9]+$ ]]; then
            create_iplimit_jails ${NUM}
            systemctl restart fail2ban
        else
            echo -e "${red}${NUM} это не число! Пожалуйста, повторите.${plain}"
        fi
elif [[ "${conq1}" == "4" ]]; then
        cd /usr/bin/
        sudo rm -R x-ui
elif [[ "${conq1}" == "5" ]]; then
        ip -a
elif [[ "${conq1}" == "6" ]]; then
        sudo adduser test
        sudo adduser test sudo
        echo -e " ${green}Пользователь test создан с пользовательским паролем!${plain}"
    else
        echo -e "${blue}P.s:Не благодарите.Ваш DiamondGlaz${plain}"
         fi
}

finvps() {
        echo -e "${green}Генерация сертификата SSL и Открытие всех портов ....${plain}"
        echo -e "${yellow}Установка завершена! В целях безопасности рекомендуется изменить настройки панели через команду x-ui .Либо через web panel. ${plain}"
        echo -e "${green}Очистка консоли через 3 секунды..."
        sleep 3
        clear
        echo -e "${green}Скрипт создал DiamondGlaz"
        echo -e "${plain}----------------------------------------------"
        echo -e "${yellow}Логин/Пароль: ${green} freenet ${plain}"
        echo -e "${yellow}Порт панели: ${green} 2024 ${plain}"
        ip_address=$(wget -qO- eth0.me | awk '{print $1}')
        echo -e "${yellow}Ваш IP :${green} $ip_address"
        ipmx=$(curl -s ipinfo.io/$ip_address | awk '/country/{print $2}')
        ipmax=$(echo $ipmx | cut -c 2-|rev|cut -c3- |rev)
        ipcn=$(curl -s https://api.ip.sb/geoip/$ip_address -A Mozilla | awk -F "[,]+" '/country/{print $(NF-4)}')
        ipcn2=$(echo $ipcn | cut -c 12-|rev|cut -c2- |rev)
        echo -e "${yellow}Ваша страна :${green} $ipmax"
        case "${release}" in
    debian)
        echo -e "${yellow}Реальная страна(ip) :${green} $ipcn2"
        ;;
    *)  
        ipcn=$(curl -s https://api.ip.sb/geoip/$ip_address -A Mozilla | awk -F "[,]+" '/country/{print $(NF-4)}')
        ipcn2=$(echo $ipcn | cut -c 12-|rev|cut -c2- |rev)
        ipcon1=$(trans -b :ru $ipcn2 | tr a-z A-Z)
        echo -e "${yellow}Реальная страна(ip) :${green} $ipcon1"
        ;;
    esac
        memor=$(cat /proc/meminfo | head -n 1| awk '{print $2}')
        memp=$(echo $memor | awk '{print (scale=$1/1024/1024)}')
        ozy=$(printf "%.1f\n" "$memp")
        echo -e "${yellow}ОЗУ = ${green} $ozy ${green}ГБ"
        echo -e "${yellow}Ваша пропускная способность ≈ ${green} $testspeed"
        echo -e "${plain}----------------------------------------------"
        echo -e "${yellow}Путь к сертификатам и прочие настройки:${green} "
        echo -e "${yellow}Публичный:${green} /etc/ssl/v2ray/cert.pub "
        echo -e "${yellow}Приватный:${green} /etc/ssl/v2ray/priv.key "
        echo -e "${yellow}Listen IP(На ru: Порт IP):${green} 0.0.0.0 "
        echo -e "${plain}----------------------------------------------"
        bust $1
}
install_iplimit
install_base
finvps $1
