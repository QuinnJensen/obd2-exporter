# obd2-exporter
### ELM327 Prometheus exporter and Grafana MQTT streamer

This program provides two data streams from a single ELM327 based OBD2-to-USB dongle
- a real-time MQTT stream of the specified OBD2 PIDs, suitable for display in Grafana live mode
- a Prometheus metrics exporter of all the sampled PIDs, for storage in a Prometheus time series database for later retrieval and analysis.

I have it running on an in-vehicle OrangePi Zero along with 3 server containers running under docker:
- Mosquitto
- Prometheus
- Grafana

### Sample OBD2 telemetry during a trip to work

Grafana dashboard showing prometheus record of OBD2 data.  1999 F350 7.3L Diesel Turbo

![Grafana dashboard showing prometheus telemetry during a trip to work](https://github.com/QuinnJensen/obd2-exporter/blob/main/Screenshot_20230801_101121.jpg)
