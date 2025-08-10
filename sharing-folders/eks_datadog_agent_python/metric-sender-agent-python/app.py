import os, time, sys
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

MAX_TRIES = 10
failures = 0

for i in range(1, MAX_TRIES + 1):
  try:
    statsd.increment("ingestion_datadog", tags=["app:py-dogstatsd", "env:dev"])
    print(f"[{i}/{MAX_TRIES}] queued metric (DogStatsD)")
  except Exception as e:
    failures += 1
    print(f"[{i}/{MAX_TRIES}] FAILED to send metric: {e}")
  time.sleep(5)

print(f"Done. Attempts={MAX_TRIES}, Failures={failures}")
sys.exit(1 if failures == MAX_TRIES else 0)
