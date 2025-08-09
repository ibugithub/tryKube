# End-to-End Guide: Install OpenTelemetry Collector & Java App Telemetry (Amazon Linux 2023 Graviton EC2 + Datadog)

This guide walks you through setting up OpenTelemetry Collector on an **Amazon Linux 2023 (ARM/Graviton)** EC2 instance and instrumenting a **Java (Spring PetClinic)** application to export telemetry to **Datadog**.

---

## 1. Launch the EC2 Instance

- **AMI**: Amazon Linux 2023 (ARM/Graviton)
- **Instance Type**: `t4g.medium`
- **Architecture**: `arm64`
- **Tags**: Add some tags (e.g., `Name=metricZero-for-telemetry`)
- **Security Group**: Allow **port 22** (SSH) and **port 8080** (Java App)

SSH into your instance:

```bash
ssh ec2-user@<public-ip>
```

---

## 2. Install OpenTelemetry Collector (ARM64 RPM)

```bash
# Download the ARM64 build
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.131.1/otelcol-contrib_0.131.1_linux_arm64.rpm

# Install
sudo rpm -ivh otelcol-contrib_0.131.1_linux_arm64.rpm

# Confirm version
/usr/bin/otelcol-contrib --version

```

---

## 3. Configure Datadog API Key

```bash
# Make DD_API_KEY available as an environment variable to the systemd service
sudo mkdir -p /etc/systemd/system/otelcol-contrib.service.d
sudo tee /etc/systemd/system/otelcol-contrib.service.d/env.conf >/dev/null <<'EOF'
[Service]
Environment="DD_API_KEY=5cdea01..."
Environment="ORGANIZATION_NAME=sre"
EOF

# edit the otelcol-contrib config
sudo systemctl edit otelcol-contrib

#check the environment
systemctl show -p Environment otelcol-contrib
```

> Replace YOUR_API_KEY_HERE with your actual Datadog API key.
> 

---

## 4. Configure the Collector

```yaml
sudo tee /etc/otelcol-contrib/config.yaml > /dev/null << 'EOF'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  resourcedetection/ec2:
    detectors: ["ec2"]
    ec2:
      tags: ["^.*$"]
      max_attempts: 5

  resource/add_env_tags:
    attributes:
      - action: upsert
        key: organization
        value: ${env:ORGANIZATION_NAME}

  transform/remove_ec2_tag_prefix:
    error_mode: ignore
    trace_statements:
      - context: resource
        statements:
          - replace_all_patterns(resource.attributes, "key", "^ec2\\.tag\\.(.*)$", "$1")
    metric_statements:
      - context: resource
        statements:
          - replace_all_patterns(resource.attributes, "key", "^ec2\\.tag\\.(.*)$", "$1")
    log_statements:
      - context: resource
        statements:
          - replace_all_patterns(resource.attributes, "key", "^ec2\\.tag\\.(.*)$", "$1")

  batch:
    send_batch_size: 10
    send_batch_max_size: 100
    timeout: 10s

exporters:
  datadog:
    api:
      site: us5.datadoghq.com
      key: ${env:DD_API_KEY}
    host_metadata:
      enabled: false
    metrics:
      resource_attributes_as_tags: true
      histograms:
        mode: distributions

extensions:
  health_check: {}
  pprof: {}
  zpages: {}

service:
  extensions: [health_check, pprof, zpages]
  pipelines:
    traces:
      receivers:  [otlp]
      processors: [resourcedetection/ec2, resource/add_env_tags, transform/remove_ec2_tag_prefix, batch]
      exporters:  [datadog]
    metrics:
      receivers:  [otlp]
      processors: [resourcedetection/ec2, resource/add_env_tags, transform/remove_ec2_tag_prefix, batch]
      exporters:  [datadog]
    logs:
      receivers:  [otlp]
      processors: [resourcedetection/ec2, resource/add_env_tags, transform/remove_ec2_tag_prefix, batch]
      exporters:  [datadog]
      
EOF

```

---

## 5. Start the Collector

```bash
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart otelcol-contrib
sudo systemctl enable otelcol-contrib
```

To upgrade :

```yaml
sudo systemctl restart otelcol-contrib
```

Confirm the collector is working fine

```yaml
sudo systemctl status otelcol-contrib --no-pager
sudo otelcol-contrib --config /etc/otelcol-contrib/config.yaml
curl -f http://localhost:13133/health && echo "Collector healthy"
```

Check logs if needed:

```bash
sudo journalctl -u otelcol-contrib -n 50 --no-pager
sudo journalctl -u otelcol-contrib -f (live)
```

---

create python app

```yaml
cat > app.py <<'EOF'

#!/usr/bin/env python3

"""
demo_metrics.py
Send exactly 10 counter points to the local OTLP-HTTP Collector,
print the export result for each batch, then exit.
"""

import socket, sys, time
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import (
    PeriodicExportingMetricReader,
    MetricExportResult,
)
from opentelemetry.exporter.otlp.proto.http.metric_exporter import (
    OTLPMetricExporter,
)

class VerboseOTLPExporter(OTLPMetricExporter):
    def export(self, metrics_data, timeout_millis=None):
        result = super().export(metrics_data, timeout_millis=timeout_millis)
        msg = (
            "Metric batch sent OK"
            if result is MetricExportResult.SUCCESS
            else f"Metric export failed: {result}"
        )
        print(msg, flush=True)
        return result

EXPORTER = VerboseOTLPExporter(
    endpoint="http://localhost:4318/v1/metrics",
    timeout=5,
)

reader = PeriodicExportingMetricReader(
    EXPORTER,
    export_interval_millis=1_000,
)

metrics.set_meter_provider(MeterProvider(metric_readers=[reader]))
meter = metrics.get_meter(__name__)

counter = meter.create_counter(
    name="demo_counter",
    unit="1",
    description="Connectivity-test counter",
)

hostname = socket.gethostname()

print("Sending 10 points …\n", flush=True)

for i in range(1, 11):
    counter.add(1, attributes={"host": hostname})
    print(f"Recorded point
    time.sleep(1)

print("\nDone — 10 points sent.", flush=True)
sys.exit(0)

EOF
```

### Run

```bash
python3 -u app.py
```

# 

## Verify

Tail the logs:

```bash
journalctl -u otelcol-contrib -f | grep resourcedetection
```