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

### Time-series comsumption and cost estimation

The following table shows the estimated time-series consumption for a single node. The values may vary depending on the number of cores, devices and interfaces of the node.

| Collector  | Metrics | TS Consumption          |
| ---------- | ------- | ----------------------- |
| CPU        | 3       | 2 x <# of cores> + 1    |
| Memory     | 50      | 50                      |
| Disk       | 19      | 18 x <# of devices> + 1 |
| Filesystem | 7       | 7 x <# of devices>      |
| Network    | 17      | 17 x <# of interfaces>  |

For a node with 2 cores, 1 devices and 2 interfaces, the estimated time-series consumption is ~514 time-series.

Based on the [pricing plans](https://cloud.ibm.com/docs/monitoring?topic=monitoring-pricing_plans), the estimated cost is **~$42 per month**.

### Collectors configuration

The following collectors are enabled by default:
- collector.cpu
- collector.diskstats
- collector.filesystem
- collector.meminfo
- collector.netdev

Collectors can be configured in the ```node_exporter.service``` file.

The full available list of collectors can be found in the official [node_exporter repository](https://github.com/prometheus/node_exporter).

### Uninstall

To uninstall the monitoring stack, run the following command:
```
./install.sh -u
```