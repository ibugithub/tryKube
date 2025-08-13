import os, time, sys
from datadog import DogStatsd

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
        statsd.increment("ingestion_vectordot_python_v2", tags=["app:vectordot_python"])
        print(f"[{i}/{MAX_TRIES}] queued ingestion_vectordot-python_v2 to dd")
    except Exception as e:
        failures += 1
        print(f"[{i}/{MAX_TRIES}] FAILED to send metric ingestion_vectordot_python_v2 to dd: {e}")
    if i < MAX_TRIES:
        time.sleep(5)

print(f"Done. Attempts={MAX_TRIES}, Failures={failures}")
sys.exit(1 if failures == MAX_TRIES else 0)
