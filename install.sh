#!/bin/bash

# check if the OS is supported
if [ ! -f /etc/os-release ]
then
    echo "Uncompatible OS. This script only supports RHEL and PPC64le architecture."
    exit 1
    else
        os=$(/usr/bin/cat /etc/os-release | /usr/bin/grep -oP 'ID="rhel"$' | /usr/bin/cut -d '"' -f 2)
        if [ "$os" != "rhel" ]
        then
            echo "Uncompatible OS. This script only supports RHEL and PPC64le architecture."
            exit 1
        fi
        arch=$(/usr/bin/uname -i)
        if [ "$arch" != "ppc64le" ]
        then
            echo "Uncompatible OS. This script only supports RHEL and PPC64le architecture."
            exit 1
        fi
fi

# check if the script is being run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

arch="linux-ppc64le"
bin_dir="/usr/local/bin"
temp_dir=$(/usr/bin/mktemp -d)

# bash colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
  echo
  echo "Usage: $0 [-r region] [-t token] [-p prometheus_version] [-n node_exporter_version]" 1>&2;
  echo
  echo -e "\t -r: Cloud Monitor endpoint region. Required. Check the full list here: https://cloud.ibm.com/docs/monitoring?topic=monitoring-endpoints#endpoints_monitoring"
  echo -e "\t -t: Cloud Monitor API Key token. Required."
  echo -e "\t -s: SAP instance IP and port(optional). I.E: 10.150.0.57:50210"
  echo -e "\t -user: SAP control user"
  echo -e "\t -password: SAP control password"
  echo -e "\t -p: Prometheus version. If not provided, the latest version will be installed."
  echo -e "\t -n: Node Exporter version. If not provided, the latest version will be installed(optional)."
  echo -e "\t -u: Uninstall Prometheus and Node Exporter and its dependencies(optional)."
  echo -e "\t -h: Show this help message."
  echo
  exit 1;
}

uninstall() {
    echo "[+] Uninstalling Prometheus and Node Exporter..."
    /usr/bin/systemctl stop prometheus.service &>/dev/null
    /usr/bin/systemctl stop node_exporter.service &>/dev/null
    /usr/bin/systemctl disable prometheus.service &>/dev/null
    /usr/bin/systemctl disable node_exporter.service &>/dev/null
    /usr/bin/rm -rf /usr/local/bin/prometheus
    /usr/bin/rm -rf /usr/local/bin/node_exporter
    /usr/bin/rm -rf /etc/prometheus
    /usr/bin/rm -rf /opt/prometheus
    /usr/bin/rm -rf /etc/systemd/system/prometheus.service
    /usr/bin/rm -rf /etc/systemd/system/node_exporter.service
    /usr/bin/rm -rf $temp_dir/prometheus
    /usr/bin/rm -rf $temp_dir/node_exporter
    /usr/bin/rm -rf $temp_dir/prometheus.tar.gz
    /usr/bin/rm -rf $temp_dir/node_exporter.tar.gz
    /usr/sbin/userdel prometheus
    /usr/sbin/userdel node_exporter
    echo -e "[-] ${GREEN}OK${NC}"
    exit 0
}

while getopts r:t:s:user:password:p:n:uh flag
do
    case "${flag}" in
        r) endpoint=${OPTARG};;
        t) key=${OPTARG};;
        s) sap=${OPTARG};;
        user) user=${OPTARG};;
        password) password=${OPTARG};;
        p) prometheus=${OPTARG};;
        n) node_exporter=${OPTARG};;
        u) uninstall;;
        h) usage;;
        *) usage;;
    esac
done

# abort if endpoint or key are not provided
if [ -z "$endpoint" ] || [ -z "$key" ]
then
    echo 'Missing Cloud Monitor region (-r) or API Key token (-t)' >&2
    usage
    exit 1
fi

# abort if sap user and password are not provide when SAP instance does
if [ ! -n "$sap" ] && [[ -z "$user" ] || [ -z "$password"]]
then
    echo 'Missing SAP control user (-user) or SAP control password (-password)' >&2
    usage
    exit 1
fi

#install wget
echo "[+] Checking if CURL is installed... "
if command -v /usr/bin/curl &> /dev/null
then
    echo -e "[-] ${GREEN}CURL is already installed. Continuing... ${NC}"
else
    echo "[+] CURL is not installed. Installing..."
    /usr/bin/yum install -y curl &> /dev/null
    echo -e "\n[-] ${GREEN}OK${NC}"
fi

#install gunzip
echo "[+] Checking if gunzip is installed... "
if command -v /usr/bin/gunzip &> /dev/null
then
    echo -e "[-] ${GREEN}Gunzip is already installed. Continuing... ${NC}"
else
    echo "[+] Gunzip is not installed. Installing..."
    /usr/bin/yum install -y gunzip &> /dev/null
    echo -e "\n[-] ${GREEN}OK${NC}"
fi

if [ -z "$prometheus" ]
then #lastest version
    prometheus=$(/usr/bin/curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | /usr/bin/grep tag_name | /usr/bin/cut -d '"' -f 4)
    prometheus=${prometheus:1}
fi

if [ -z "$node_exporter" ]
then #lastest version
    node_exporter=$(/usr/bin/curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | /usr/bin/grep tag_name | /usr/bin/cut -d '"' -f 4)
    node_exporter=${node_exporter:1}
fi

if [ -z "$sap" ]
then #set last SAP Host exporter version
    sap_exporter=$(/usr/bin/curl -s https://api.github.com/repos/SUSE/sap_host_exporter/releases/latest | /usr/bin/grep tag_name | /usr/bin/cut -d '"' -f 4)
fi

# check credentials
echo "[+] Checking credentials... "
remote_key=$(/usr/bin/curl -s -H "Authorization: Bearer $key" -H "Content-Type: appli/usr/bin/cation/json" $endpoint/api/token | /usr/bin/grep -oE '"key":"[a-zA-Z0-9\-]*' | /usr/bin/cut -d ':' -f 2 | /usr/bin/tr -d '"')

if [ -z "$remote_key" ]
then
    echo -e "[*] ${RED}ERROR! Invalid credentials. Please check your endpoint and key.${NC}" >&2
    exit 1
fi

if [ "$key" != "$remote_key" ]
then
    echo -e "[*] ${RED}ERROR! Invalid credentials. Please check your endpoint and key.${NC}" >&2
    exit 1
fi

# build the ingestion endpoint based on the provided endpoint
ingestion_endpoint="https://ingest.$(/usr/bin/cut -d '/' -f 3 <<< "$endpoint")/prometheus/remote/write"

echo -e "[-] ${GREEN}OK${NC}"

#install wget
echo "[+] Checking if WGET is installed... "
if command -v wget &> /dev/null
then
    echo -e "[-] ${GREEN}WGET is already installed. Continuing... ${NC}"
else
    echo -n "[+] WGET is not installed. Installing..."
    /usr/bin/yum install -y wget &> /dev/null
    echo -e "\n[-] ${GREEN}OK${NC}"
fi

# download prometheus
echo "[+] Downloading Prometheus..."
/usr/bin/wget -q "https://github.com/prometheus/prometheus/releases/download/v$prometheus/prometheus-$prometheus.$arch.tar.gz" -O $temp_dir/prometheus.tar.gz

# abort if the download failed
if [ $? -ne 0 ]
then
  echo -e "[*] ${RED}ERROR: The selected Prometheus version doesn't exist or failed to download.${NC}" >&2
  exit 1
fi

echo -e "[-] ${GREEN}OK${NC}"

# download node_exporter
echo "[+] Downloading Node Exporter..."
/usr/bin/wget -q "https://github.com/prometheus/node_exporter/releases/download/v$node_exporter/node_exporter-$node_exporter.$arch.tar.gz" -O $temp_dir/node_exporter.tar.gz

# abort if the download failed
if [ $? -ne 0 ]
then
  echo -e "[*] ${RED}ERROR: The selected Node Exporter version doesn't exist or failed to download.${NC}" >&2
  exit 1
fi

echo -e "[-] ${GREEN}OK${NC}"

# download SAP Host exporter
if [ -z "$sap" ]
then
    echo "[+] Downloading SAP Host Exporter..."
    /usr/bin/wget -q "https://github.com/SUSE/sap_host_exporter/releases/download/$sap_exporter/sap_host_exporter-ppc64le.gz" -O $temp_dir/sap_host_exporter.gz

    # abort if the download failed
    if [ $? -ne 0 ]
    then
    echo -e "[*] ${RED}ERROR: SAP Host Exporter cannot be downloaded or failed to download.${NC}" >&2
    exit 1
    fi

    echo -e "[-] ${GREEN}OK${NC}"
fi

# make temp dir to extract prometheus and node exporter
echo "[+] Creating temp directory..."
/usr/bin/mkdir -p $temp_dir/prometheus
/usr/bin/mkdir -p $temp_dir/node_exporter
if [ -z "$sap" ]
then
    /usr/bin/mkdir -p $temp_dir/sap_host_exporter
fi

# if no $temp_dir found, abort
cd $temp_dir || { echo -e "[*] ${RED}ERROR: No $temp_dir found.${NC}"; exit 1; }

echo -e "[-] ${GREEN}OK${NC}"

# extract prometheus and node exporter
echo "[+] Extracting Prometheus and exporters..."
/usr/bin/tar xfz $temp_dir/prometheus.tar.gz -C $temp_dir/prometheus || { echo -e "[*] ${RED}ERROR! Extracting the Prometheus tar.${NC}"; exit 1; }
/usr/bin/tar xfz $temp_dir/node_exporter.tar.gz -C $temp_dir/node_exporter || { echo -e "[*] ${RED}ERROR! Extracting the Node Exporter.${NC}"; exit 1; }
if [ -z "$sap" ]
then
    /usr/bin/gunzip -c $temp_dir/sap_host_exporter.gz > $temp_dir/sap_host_exporter/sap_host_exporter || { echo -e "[*] ${RED}ERROR! Extracting the SAP Host Exporter.${NC}"; exit 1; }
fi
echo -e "[-] ${GREEN}OK${NC}"

# create prometheus and node exporter users
echo "[+] Creating system users users..."
/usr/sbin/useradd --no-create-home --shell /bin/false prometheus &>/dev/null
/usr/sbin/useradd --no-create-home --shell /bin/false node_exporter &>/dev/null
/usr/sbin/usermod -a -G prometheus prometheus &>/dev/null
/usr/sbin/usermod -a -G node_exporter node_exporter &>/dev/null
if [ -z "$sap" ]
then
    /usr/sbin/useradd --no-create-home --shell /bin/false sap_host_exporter &>/dev/null
    /usr/sbin/usermod -a -G sap_host_exporter sap_host_exporter &>/dev/null
fi
echo -e "[-] ${GREEN}OK${NC}"

# make prometheus and node exporter executable
echo "[+] Making Prometheus and exporters executable..."
/usr/bin/chmod +x "$temp_dir/prometheus/prometheus-$prometheus.$arch/prometheus"
/usr/bin/chmod +x "$temp_dir/node_exporter/node_exporter-$node_exporter.$arch/node_exporter"
if [ -z "$sap" ]
then
    /usr/bin/chmod +x "$temp_dir/sap_host_exporter/sap_host_exporter"
fi
echo -e "[-] ${GREEN}OK${NC}"

# change prometheus and node exporter ownership
echo "[+] Changing Prometheus and exporters ownership..."
/usr/bin/chown prometheus:prometheus "$temp_dir/prometheus/prometheus-$prometheus.$arch/prometheus"
/usr/bin/chown node_exporter:node_exporter "$temp_dir/node_exporter/node_exporter-$node_exporter.$arch/node_exporter"
if [ -z "$sap" ]
then
    /usr/bin/chown sap_host_exporter:sap_host_exporter "$temp_dir/sap_host_exporter/sap_host_exporter"
fi
echo -e "[-] ${GREEN}OK${NC}"

# create prometheus temp directory
echo "[+] Creating Prometheus and exporters directories..."
/usr/bin/mkdir /opt/prometheus &>/dev/null
/usr/bin/mkdir /etc/prometheus &>/dev/null
/usr/bin/chown prometheus:prometheus /opt/prometheus
if [ -z "$sap" ]
then
    /usr/bin/mkdir /etc/sap_host_exporter &>/dev/null
fi
echo -e "[-] ${GREEN}OK${NC}"

# move prometheus and node exporter to bin dir
echo "[+] Moving Prometheus and exporters to $bin_dir..."
/usr/bin/mv "$temp_dir/prometheus/prometheus-$prometheus.$arch/prometheus" "$bin_dir"
/usr/bin/mv "$temp_dir/node_exporter/node_exporter-$node_exporter.$arch/node_exporter" "$bin_dir"
if [ -z "$sap" ]
then
    /usr/bin/mv "$temp_dir/sap_host_exporter/sap_host_exporter" "$bin_dir"
fi
echo -e "[-] ${GREEN}OK${NC}"

# create prometheus service file
echo "[+] Creating Prometheus and exporters service files..."
/usr/bin/cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.agent.path=/opt/prometheus --enable-feature=agent --web.listen-address="127.0.0.1:9090"

[Install]
WantedBy=multi-user.target
EOF

# create node exporter service file
/usr/bin/cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.disable-defaults \
--collector.cpu \
--collector.diskstats \
--collector.filesystem \
--collector.meminfo \
--collector.netdev \
--web.listen-address="127.0.0.1:9100"

[Install]
WantedBy=multi-user.target
EOF

# create sap host exporter service file
if [ -z "$sap" ]
then
/usr/bin/cat <<EOF > /etc/systemd/system/sap_host_exporter.service
[Unit]
Description=SAP Host Exporter
After=network.target

[Service]
User=sap_host_exporter
Group=sap_host_exporter
Type=simple
ExecStart=/usr/local/bin/sap_host_exporter -c /etc/sap_host_exporter/sap_host_exporter.yml

[Install]
WantedBy=multi-user.target
EOF
fi

echo -e "[-] ${GREEN}OK${NC}"

# create prometheus config file
echo "[+] Creating Prometheus config file..."
/usr/bin/cat <<EOF > /etc/prometheus/prometheus.yml

global:
  scrape_interval: 10s
  evaluation_interval: 15s

remote_write:
- url: "$ingestion_endpoint"
  bearer_token: "$key"
  write_relabel_configs:
    - target_label: instance
      replacement: '$(/usr/bin/hostname)'

scrape_configs:
  - job_name: "powervs_linux_node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
    relabel_configs:
      - target_label: domain
        replacement: 'POWERVS'
EOF

/usr/bin/chown prometheus:prometheus /etc/prometheus/prometheus.yml
echo -e "[-] ${GREEN}OK${NC}"

# create sap host exporter service file
if [ -z "$sap" ]
then
echo "[+] Creating SAP Host Exporter config file..."
/usr/bin/cat <<EOF >> /etc/prometheus/prometheus.yml
  - job_name: "sap_host_exporter"
    static_configs:
      - targets:
          - localhost:9680
    relabel_configs:
      - target_label: domain
        replacement: 'SAP'
EOF
echo -e "[-] ${GREEN}OK${NC}"
fi

# reload systemd services
echo "[+] Reloading systemd services..."
/usr/bin/systemctl daemon-reload
echo -e "[-] ${GREEN}OK${NC}"

# disable SELinux for Prometheus and Node Exporter
echo "[+] Disabling SELinux for Prometheus and Node Exporter..."
/usr/sbin/restorecon -r /usr/local/bin/prometheus
/usr/sbin/restorecon -r /usr/local/bin/node_exporter
if [ -z "$sap" ]
then
    /usr/sbin/restorecon -r /usr/local/bin/sap_host_exporter
fi
echo -e "[-] ${GREEN}OK${NC}"

# enable prometheus and node exporter services
echo "[+] Enabling and starting Prometheus and Node Exporter services..."
/usr/bin/systemctl enable prometheus.service &>/dev/null
/usr/bin/systemctl enable node_exporter.service &>/dev/null
if [ -z "$sap" ]
then
    /usr/bin/systemctl enable sap_host_exporter.service &>/dev/null
fi

# start prometheus and node exporter services
/usr/bin/systemctl start prometheus.service
/usr/bin/systemctl start node_exporter.service
if [ -z "$sap" ]
then
    /usr/bin/systemctl start sap_host_exporter.service
fi
echo -e "[-] ${GREEN}OK${NC}"

# check if prometheus and exporters are running
echo "[+] Checking if Prometheus and exporters are running..."
if /usr/bin/systemctl is-active --quiet prometheus; then
    echo -e "[-] ${GREEN}Prometheus is running.${NC}"
else
    echo -e "[*] ${RED}Prometheus is NOT running.${NC}"
fi

if /usr/bin/systemctl is-active --quiet node_exporter; then
    echo -e "[-] ${GREEN}Node Exporter is running.${NC}"
else
    echo -e "[*] ${RED}Node Exporter is NOT running.${NC}"
fi

if [ -z "$sap" ]
then
    if /usr/bin/systemctl is-active --quiet sap_host_exporter; then
        echo -e "[-] ${GREEN}SAP Host exporter is running.${NC}"
    else
        echo -e "[*] ${RED}SAP Host exporter is NOT running.${NC}"
    fi
fi

if /usr/bin/systemctl is-active --quiet node_exporter && /usr/bin/systemctl is-active --quiet prometheus; then
    if [ -z "$sap" ]
    then
        if ! /usr/bin/systemctl is-active --quiet sap_host_exporter; then
            echo -e "[*] ${RED}ERROR! Someting went wrong. Please check your SAP endopoint and credentials.${NC}" >&2
            exit 1
        fi
    fi
    event_json='{"event": {"type": "CUSTOM","description": "Prometheus and Node Exporter installed successfully!","name": "New PowerVS host connected","scope": "host.hostName = \"'$(/usr/bin/hostname)'\"","severity": "LOW","source": "CMD","tags": {"source": "CMD"}}}'

    # send a event to Cloud Monitoring
    echo "[+] Sending a test event to Cloud Monitoring..."
    event=$(/usr/bin/curl -s -d "$event_json" -H "Authorization: Bearer $key" -H "Content-Type: application/json" $endpoint/api/v2/events)
    if [ -z "$event" ]
    then
        echo -e "[*] ${RED}ERROR! Someting went wrong. Please check your endpoint and key.${NC}" >&2
        exit 1
    fi
    echo -e "[-] ${GREEN}OK${NC}"
fi


# cleaning up
echo "[+] Cleaning up..."
/usr/bin/rm -rf $temp_dir/prometheus
/usr/bin/rm -rf $temp_dir/node_exporter
/usr/bin/rm -rf $temp_dir/prometheus.tar.gz
/usr/bin/rm -rf $temp_dir/node_exporter.tar.gz
if [ -z "$sap" ]
then
    /usr/bin/rm -rf $temp_dir/sap_host_exporter
    /usr/bin/rm -rf $temp_dir/sap_host_exporter.gz
fi
echo -e "[-] ${GREEN}OK${NC}"

echo "SUCCESS! Installation succeeded!"
exit 0

