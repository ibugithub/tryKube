from datadog import initialize, statsd
import time
import socket
import os

options = {
    "statsd_host": os.getenv("DD_AGENT_HOST", "localhost"),
    "statsd_port": int(os.getenv("DD_DOGSTATSD_PORT", 8125)),
}

initialize(**options)
print('hello from metric-sender', flush=True)
while True:
    statsd.increment("for_ingestion_tags_before", tags=[
        f"host:{socket.gethostname()}",
        "env:eks",
        "app:cardinality-check"
    ])
    print("Metric sent", flush=True)
    time.sleep(10)
