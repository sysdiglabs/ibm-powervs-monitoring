# Bash script to autodeploy the monitoring stack on IBM PowerVS over RHEL

### Description

This script will deploy the monitoring stack on IBM PowerVS over RHEL. The stack is composed by Prometheus and Node exporter for PPC64le architecture. The script will also configure the remote write endpoint to send the time series to the IBM Cloud Monitoring instance. No further extra configuration is needed.

### Prerequisites

- [IBM Cloud account](https://cloud.ibm.com/registration)
- A PowerVS instance with RHEL installed. The supported architecture is ppc64le.
- Root access to the PowerVS instance

### Usage

Example of usage:
```
./install.sh -r <region> -t <token> -p <Prometheus version, latest by default> -n <Node exporter version, latest by default>
./install.sh -r https://eu-es.monitoring.cloud.ibm.com -t XXXXXX-XXXXX-XXXXXX-XXXXXXXXX
```

#### Demo time
https://github.com/sysdiglabs/ibm-powervs-monitoring/assets/7352160/7ae2c42b-0243-45b2-b5f4-55f4aacb5e65

#### Custom event fired

<img width="1919" alt="ibm-powervs-monitoring" src="https://github.com/sysdiglabs/ibm-powervs-monitoring/assets/7352160/15451781-e835-4233-b224-0aa363c35799">
