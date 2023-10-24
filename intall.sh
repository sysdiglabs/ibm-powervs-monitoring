#!/bin/bash

arch="linux-ppc64le"
bin_dir="/usr/local/bin"

while getopts p:n:e:k: flag
do
    case "${flag}" in
        p) prometheus=${OPTARG};;
        n) node_exporter=${OPTARG};;
        e) endpoint=${OPTARG};;
        k) key=${OPTARG};;
        *)
            echo 'Error in command line parsing' >&2
            exit 1
    esac
done

# abort if endpoint or key are not provided
if [ -z "$endpoint" ] || [ -z "$key" ]; then
        echo 'Missing Cloud Monitor endpoit(-e) or API Key(-k)' >&2
        exit 1
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

#install wget
echo "Installing wget..."
yum install -y wget

# download prometheus
wget -q "https://github.com/prometheus/prometheus/releases/download/v$prometheus/prometheus-$prometheus.$arch.tar.gz" -O /tmp/prometheus.tar.gz

# abort if the download failed
if [ $? -ne 0 ]
then
  echo "The selected Prometheus version doesn't exist." >&2
  exit 1
fi

# download node_exporter
wget -q "https://github.com/prometheus/node_exporter/releases/download/v$node_exporter/node_exporter-$node_exporter.$arch.tar.gz" -O /tmp/node_exporter.tar.gz

# abort if the download failed
if [ $? -ne 0 ]
then
  echo "This selected Node Exporter version doesn't exist." >&2
  exit 1
fi

# make temp dir to extract prometheus and node exporter
mkdir -p /tmp/prometheus
mkdir -p /tmp/node_exporter

# if no /tmp found, abort
cd /tmp || { echo "ERROR! No /tmp found.."; exit 1; }

# extract prometheus and node exporter
tar xfz /tmp/prometheus.tar.gz -C /tmp/prometheus || { echo "ERROR! Extracting the prometheus tar"; exit 1; }
tar xfz /tmp/node_exporter.tar.gz -C /tmp/node_exporter || { echo "ERROR! Extracting the node_exporter tar"; exit 1; }

# create prometheus and node exporter users
useradd --no-create-home --shell /bin/false prometheus
useradd --no-create-home --shell /bin/false node_exporter
#groupadd prometheus
#groupadd node_exporter
usermod -a -G prometheus prometheus
usermod -a -G node_exporter node_exporter

# make prometheus and node exporter executable
chmod +x "/tmp/prometheus/prometheus-$prometheus.$arch/prometheus"
chmod +x "/tmp/node_exporter/node_exporter-$node_exporter.$arch/node_exporter"

# change prometheus and node exporter ownership
chown prometheus:prometheus "/tmp/prometheus/prometheus-$prometheus.$arch/prometheus"
chown node_exporter:node_exporter "/tmp/node_exporter/node_exporter-$node_exporter.$arch/node_exporter"

# move prometheus and node exporter to bin dir
mv "/tmp/prometheus/prometheus-$prometheus.$arch/prometheus" "$bin_dir"
mv "/tmp/node_exporter/node_exporter-$node_exporter.$arch/node_exporter" "$bin_dir"

cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.agent.path=/opt/prometheus
--enable-feature=agent

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.disable-defaults
--collector.cpu
--collector.diskstats
--collector.filesystem
--collector.meminfo
--collector.netdev

[Install]
WantedBy=multi-user.target
EOF

# reload systemd services
systemctl daemon-reload

# disable SELinux for Prometheus and Node Exporter
restorecon -rv /usr/local/bin/prometheus
restorecon -rv /usr/local/bin/node_exporter

# enable prometheus and node exporter services
systemctl enable prometheus.service
systemctl enable node_exporter.service

# start prometheus and node exporter services
systemctl start prometheus.service
systemctl start node_exporter.service

echo "SUCCESS! Installation succeeded!"