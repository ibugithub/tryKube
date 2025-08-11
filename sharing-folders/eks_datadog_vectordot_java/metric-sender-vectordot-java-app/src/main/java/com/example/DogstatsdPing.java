package com.example;

import com.timgroup.statsd.NonBlockingStatsDClientBuilder;
import com.timgroup.statsd.StatsDClient;

public class DogstatsdPing {
  private static String getenvOr(String k, String def) {
    String v = System.getenv(k);
    return (v == null || v.isEmpty()) ? def : v;
  }

  public static void main(String[] args) throws InterruptedException {
    final String udsPath = getenvOr("DOGSTATSD_SOCKET", "");
    final String metric = "ingestion_datadog_vectordot_java_v2";
    final String[] tags = new String[] {"app:datadog_vectordot_java", "env:dev"};

    NonBlockingStatsDClientBuilder b = new NonBlockingStatsDClientBuilder();
    String transport;

    if (!udsPath.isEmpty()) {
      // Prefer UDS if available
      b.address("unix://" + udsPath);
      transport = "uds:" + udsPath;
    } else {
      // Fallback to UDP
      String host = getenvOr("DOGSTATSD_HOST", "127.0.0.1");
      int port = Integer.parseInt(getenvOr("DOGSTATSD_PORT", "8125"));
      b.hostname(host).port(port);
      transport = "udp:" + host + ":" + port;
    }

    StatsDClient client = b.build();
    System.out.println("DogStatsD transport -> " + transport);

    final int MAX_TRIES = 10;
    int failures = 0;

    for (int i = 1; i <= MAX_TRIES; i++) {
      try {
        client.count(metric, 1, tags);
        System.out.printf("[%d/%d] queued metric_v2 (DogStatsD)%n", i, MAX_TRIES);
      } catch (Exception e) {
        failures++;
        System.out.printf("[%d/%d] FAILED to send metric_v2 : %s%n", i, MAX_TRIES, e);
      }
      Thread.sleep(5000);
    }

    System.out.printf("Done. Attempts=%d, Failures=%d%n", MAX_TRIES, failures);
    System.exit(failures == MAX_TRIES ? 1 : 0);
  }
}
