FROM registry.suse.com/bci/bci-base:15.5
RUN zypper addrepo --gpgcheck-allow-unsigned https://download.opensuse.org/repositories/server:/monitoring/SLE_15_SP4/server:monitoring.repo
RUN zypper --gpg-auto-import-keys refresh
RUN zypper --non-interactive install prometheus-sap_host_exporter
EXPOSE 9680
ADD /etc/monitoring/sap_host_exporter.yml /etc/sap_host_exporter.yml