#!/bin/bash

# check if the OS is supported
if [ ! -f /etc/os-release ]
then
    echo "Uncompatible OS. This script only supports RHEL."
    exit 1
    else
        os=$(cat /etc/os-release | grep -oP 'ID="rhel"$' | cut -d '"' -f 2)
        if [ "$os" != "rhel" ]
        then
            echo "Uncompatible OS. This script only supports RHEL."
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
temp_dir=$(mktemp -d)

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
  echo -e "\t -p: Prometheus version. If not provided, the latest version will be installed."
  echo -e "\t -n: Node Exporter version. If not provided, the latest version will be installed(optional)."
  echo -e "\t -u: Uninstall Prometheus and Node Exporter and its dependencies(optional)."
  echo -e "\t -h: Show this help message."
  echo
  exit 1;
}

uninstall() {
    echo "[+] Uninstalling Prometheus and Node Exporter..."
    systemctl stop prometheus.service &>/dev/null
    systemctl stop node_exporter.service &>/dev/null
    systemctl disable prometheus.service &>/dev/null
    systemctl disable node_exporter.service &>/dev/null
    rm -rf /usr/local/bin/prometheus
    rm -rf /usr/local/bin/node_exporter
    rm -rf /etc/prometheus
    rm -rf /opt/prometheus
    rm -rf /etc/systemd/system/prometheus.service
    rm -rf /etc/systemd/system/node_exporter.service
    rm -rf $temp_dir/prometheus
    rm -rf $temp_dir/node_exporter
    rm -rf $temp_dir/prometheus.tar.gz
    rm -rf $temp_dir/node_exporter.tar.gz
    userdel prometheus
    userdel node_exporter
    echo -e "[-] ${GREEN}OK${NC}"
    exit 1
}

while getopts r:t:p:n:uh flag
do
    case "${flag}" in
        r) endpoint=${OPTARG};;
        t) key=${OPTARG};;
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

#install wget
echo "[+] Checking if CURL is installed... "
if command -v curl &> /dev/null
then
    echo -e "[-] ${GREEN}CURL is already installed. Continuing... ${NC}"
else
    echo "[+] CURL is not installed. Installing..."
    yum install -y curl &> /dev/null
    echo -e "\n[-] ${GREEN}OK${NC}"
fi

if [ -z "$prometheus" ]
then #lastest version
    prometheus=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep tag_name | cut -d '"' -f 4)
    prometheus=${prometheus:1}
fi

if [ -z "$node_exporter" ]
then #lastest version
    node_exporter=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep tag_name | cut -d '"' -f 4)
    node_exporter=${node_exporter:1}
fi

# check credentials
echo "[+] Checking credentials... "
remote_key=$(curl -s -H "Authorization: Bearer $key" -H "Content-Type: application/json" $endpoint/api/token | grep -oE '"key":"[a-zA-Z0-9\-]*' | cut -d ':' -f 2 | tr -d '"')

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
ingestion_endpoint="https://ingest.$(cut -d '/' -f 3 <<< "$endpoint")/prometheus/remote/write"

echo -e "[-] ${GREEN}OK${NC}"

#install wget
echo "[+] Checking if WGET is installed... "
if command -v wget &> /dev/null
then
    echo -e "[-] ${GREEN}WGET is already installed. Continuing... ${NC}"
else
    echo -n "[+] WGET is not installed. Installing..."
    yum install -y wget &> /dev/null
    echo -e "\n[-] ${GREEN}OK${NC}"
fi

# download prometheus
echo "[+] Downloading Prometheus..."
wget -q "https://github.com/prometheus/prometheus/releases/download/v$prometheus/prometheus-$prometheus.$arch.tar.gz" -O $temp_dir/prometheus.tar.gz

# abort if the download failed
if [ $? -ne 0 ]
then
  echo -e "[*] ${RED}ERROR: The selected Prometheus version doesn't exist or failed to download.${NC}" >&2
  exit 1
fi

echo -e "[-] ${GREEN}OK${NC}"

# download node_exporter
echo "[+] Downloading Node Exporter..."
wget -q "https://github.com/prometheus/node_exporter/releases/download/v$node_exporter/node_exporter-$node_exporter.$arch.tar.gz" -O $temp_dir/node_exporter.tar.gz

# abort if the download failed
if [ $? -ne 0 ]
then
  echo -e "[*] ${RED}ERROR: The selected Node Exporter version doesn't exist or failed to download.${NC}" >&2
  exit 1
fi

echo -e "[-] ${GREEN}OK${NC}"

# make temp dir to extract prometheus and node exporter
echo "[+] Creating temp directory..."
mkdir -p $temp_dir/prometheus
mkdir -p $temp_dir/node_exporter

# if no $temp_dir found, abort
cd $temp_dir || { echo -e "[*] ${RED}ERROR: No $temp_dir found.${NC}"; exit 1; }

echo -e "[-] ${GREEN}OK${NC}"

# extract prometheus and node exporter
echo "[+] Extracting Prometheus and Node Exporter..."
tar xfz $temp_dir/prometheus.tar.gz -C $temp_dir/prometheus || { echo -e "[*] ${RED}ERROR! Extracting the prometheus tar.${NC}"; exit 1; }
tar xfz $temp_dir/node_exporter.tar.gz -C $temp_dir/node_exporter || { echo -e "[*] ${RED}ERROR! Extracting the node_exporter tar.${NC}"; exit 1; }
echo -e "[-] ${GREEN}OK${NC}"

# create prometheus and node exporter users
echo "[+] Creating Prometheus and Node Exporter users..."
useradd --no-create-home --shell /bin/false prometheus &>/dev/null
useradd --no-create-home --shell /bin/false node_exporter &>/dev/null
usermod -a -G prometheus prometheus &>/dev/null
usermod -a -G node_exporter node_exporter &>/dev/null
echo -e "[-] ${GREEN}OK${NC}"

# make prometheus and node exporter executable
echo "[+] Making Prometheus and Node Exporter executable..."
chmod +x "$temp_dir/prometheus/prometheus-$prometheus.$arch/prometheus"
chmod +x "$temp_dir/node_exporter/node_exporter-$node_exporter.$arch/node_exporter"
echo -e "[-] ${GREEN}OK${NC}"

# change prometheus and node exporter ownership
echo "[+] Changing Prometheus and Node Exporter ownership..."
chown prometheus:prometheus "$temp_dir/prometheus/prometheus-$prometheus.$arch/prometheus"
chown node_exporter:node_exporter "$temp_dir/node_exporter/node_exporter-$node_exporter.$arch/node_exporter"
echo -e "[-] ${GREEN}OK${NC}"

# create prometheus temp directory
echo "[+] Creating Prometheus directories..."
mkdir /opt/prometheus &>/dev/null
mkdir /etc/prometheus &>/dev/null
chown prometheus:prometheus /opt/prometheus
echo -e "[-] ${GREEN}OK${NC}"

# move prometheus and node exporter to bin dir
echo "[+] Moving Prometheus and Node Exporter to $bin_dir..."
mv "$temp_dir/prometheus/prometheus-$prometheus.$arch/prometheus" "$bin_dir"
mv "$temp_dir/node_exporter/node_exporter-$node_exporter.$arch/node_exporter" "$bin_dir"
echo -e "[-] ${GREEN}OK${NC}"

# create prometheus service file
echo "[+] Creating Prometheus and Node Exporter service files..."
cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.agent.path=/opt/prometheus --enable-feature=agent

[Install]
WantedBy=multi-user.target
EOF

# create node exporter service file
cat <<EOF > /etc/systemd/system/node_exporter.service
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
--collector.netdev

[Install]
WantedBy=multi-user.target
EOF

echo -e "[-] ${GREEN}OK${NC}"

# create prometheus config file
echo "[+] Creating Prometheus config file..."
cat <<EOF > /etc/prometheus/prometheus.yml

global:
  scrape_interval: 10s
  evaluation_interval: 15s

remote_write:
- url: "$ingestion_endpoint"
  bearer_token: "$key"

scrape_configs:
  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
EOF

chown prometheus:prometheus /etc/prometheus/prometheus.yml
echo -e "[-] ${GREEN}OK${NC}"


# reload systemd services
echo "[+] Reloading systemd services..."
systemctl daemon-reload
echo -e "[-] ${GREEN}OK${NC}"

# disable SELinux for Prometheus and Node Exporter
echo "[+] Disabling SELinux for Prometheus and Node Exporter..."
restorecon -r /usr/local/bin/prometheus
restorecon -r /usr/local/bin/node_exporter
echo -e "[-] ${GREEN}OK${NC}"

# enable prometheus and node exporter services
echo "[+] Enabling and starting Prometheus and Node Exporter services..."
systemctl enable prometheus.service &>/dev/null
systemctl enable node_exporter.service &>/dev/null

# start prometheus and node exporter services
systemctl start prometheus.service
systemctl start node_exporter.service
echo -e "[-] ${GREEN}OK${NC}"

# check if prometheus and node exporter are running
echo "[+] Checking if Prometheus and Node Exporter are running..."
if systemctl is-active --quiet prometheus; then
    echo -e "[-] ${GREEN}Prometheus is running.${NC}"
else
    echo -e "[*] ${RED}Prometheus is NOT running.${NC}"
fi

if systemctl is-active --quiet node_exporter; then
    echo -e "[-] ${GREEN}Node Exporter is running.${NC}"
else
    echo -e "[*] ${RED}Node Exporter is NOT running.${NC}"
fi

if systemctl is-active --quiet node_exporter && systemctl is-active --quiet prometheus; then
    event_json='{"event": {"type": "CUSTOM","description": "Prometheus and Node Exporter installed successfully!","name": "New PowerVS host connected","scope": "host.hostName = \"'$(hostname)'\"","severity": "LOW","source": "CMD","tags": {"source": "CMD"}}}'

    # send a event to Cloud Monitoring
    echo "[+] Sending a test event to Cloud Monitoring..."
    event=$(curl -s -d "$event_json" -H "Authorization: Bearer $key" -H "Content-Type: application/json" $endpoint/api/v2/events)
    if [ -z "$event" ]
    then
        echo -e "[*] ${RED}ERROR! Someting went wrong. Please check your endpoint and key.${NC}" >&2
        exit 1
    fi
    echo -e "[-] ${GREEN}OK${NC}"
fi


# cleaning up
echo "[+] Cleaning up..."
rm -rf $temp_dir/prometheus
rm -rf $temp_dir/node_exporter
rm -rf $temp_dir/prometheus.tar.gz
rm -rf $temp_dir/node_exporter.tar.gz
echo -e "[-] ${GREEN}OK${NC}"

echo "SUCCESS! Installation succeeded!"
exit 0

