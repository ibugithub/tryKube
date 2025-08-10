import os, time
from datadog import DogStatsd

# Prefer UDS if available (more reliable locally), else UDP
socket_path = os.getenv("DOGSTATSD_SOCKET")
if socket_path:
  statsd = DogStatsd(socket_path=socket_path)
  transport = f"uds:{socket_path}"
else:
  host = os.getenv("DOGSTATSD_HOST", "127.0.0.1")
  port = int(os.getenv("DOGSTATSD_PORT", "8125"))
  statsd = DogStatsd(host=host, port=port)
  transport = f"udp:{host}:{port}"

print(f"DogStatsD transport -> {transport}")

while True:
  try:
    statsd.increment("ingestion_datadog", tags=["app:py-dogstatsd", "env:dev"])
    print("queued metric (DogStatsD)")
  except Exception as e:
    print(f"FAILED to send metric: {e}")
  time.sleep(5)