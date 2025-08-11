# Step 1 — Install Vector via Helm with StatsD on a non‑default port (UDP 9125)

We’ll run Vector as a single **aggregator** Deployment and expose a **ClusterIP** Service on UDP **9125** so it won’t clash with Datadog’s 8125.

```yaml
#add vector.dev repo
helm repo add vector https://helm.vector.dev
helm repo update

#create namespace
kubectl create ns vectorclear

#check namespace
kubectl get namespace
```

create secret key

```yaml
kubectl -n vector create secret generic datadog-secret \
  --from-literal=api-key='5cdea018e3f97b9fbfd267fe342bb3a8'
```

create a vector-values.yaml file

```yaml
cat > vector-values.yaml <<'YAML'
role: "Aggregator"
replicaCount: 1

service:
  enabled: true
  type: ClusterIP
  ports:
    - name: statsd
      port: 9125
      targetPort: 9125
      protocol: UDP

env:
  - name: DD_API_KEY
    valueFrom:
      secretKeyRef:
        name: datadog-secret
        key: api-key

customConfig:
  data_dir: /vector-data-dir
  sources:
    statsd:
      type: statsd
      address: "0.0.0.0:9125"
      mode: udp
  sinks:
    datadog_metrics:
      type: datadog_metrics
      inputs: ["statsd"]
      default_api_key: "${DD_API_KEY}"
      site: "us5.datadoghq.com"
    console:
      type: console
      inputs: ["statsd"]
      encoding:
        codec: json

YAML
```

Install vector

```yaml
# install
helm install vector vector/vector -f vector-values.yaml -n vector
```

Apply/upgrade Vector:clear

```bash
helm upgrade --install vector vector/vector -n vector -f vector-values.yaml
kubectl -n vector rollout status sts/vector
```

verify vector installation

```yaml
kubectl -n vector get pods -n vector
kubectl logs <pod name> -n vector

# check StatefulSet
kubectl -n vector get sts
kubectl  rollout status sts/vector -n vector

# pod + logs
kubectl get pods -n vector -n vector
```

## Check the Service & port 9125/UDP

```bash
kubectl -n vector get svc
kubectl -n vector describe svc vector | sed -n '1,120p'
```

## Smoke test: send a StatsD packet to Vector

```bash
VECTOR_IP=$(kubectl -n vector get svc vector -o jsonpath='{.spec.clusterIP}')
kubectl -n vector run -it --rm tmp --image=busybox --restart=Never -- sh -lc \
 'printf "ingestion_vectordev:1|c|#source:smoke" | nc -u -w1 '"$VECTOR_IP"' 9125; echo sent'

# now see if Vector received it
kubectl -n vector logs pod/vector-0 --tail=50
```

## Write the app

Create sharing-folders/eks_datadog_vectordot_java/metric-sender-vectordot-java-app/src/main/java/com/example/DogstatsdPing.java

```java
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
    final String metric = "ingestion_datadog_vectordot_java";
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
        System.out.printf("[%d/%d] queued metric (DogStatsD)%n", i, MAX_TRIES);
      } catch (Exception e) {
        failures++;
        System.out.printf("[%d/%d] FAILED to send metric: %s%n", i, MAX_TRIES, e);
      }
      Thread.sleep(5000);
    }

    System.out.printf("Done. Attempts=%d, Failures=%d%n", MAX_TRIES, failures);
    System.exit(failures == MAX_TRIES ? 1 : 0);
  }
}

```

Create `sharing-folders/eks_datadog_vectordot_java/metric-sender-vectordot-java-app/pom.xml`

```xml
xml
CopyEdit
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                             http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>metric-sender-vectordot-java</artifactId>
  <version>1.0.0</version>

  <properties>
    <maven.compiler.source>21</maven.compiler.source>
    <maven.compiler.target>21</maven.compiler.target>
  </properties>

  <dependencies>
    <!-- DogStatsD Java client -->
    <dependency>
      <groupId>com.datadoghq</groupId>
      <artifactId>java-dogstatsd-client</artifactId>
      <version>4.4.4</version>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <!-- Make it runnable -->
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-jar-plugin</artifactId>
        <version>3.4.2</version>
        <configuration>
          <archive>
            <manifest>
              <mainClass>com.example.DogstatsdPing</mainClass>
            </manifest>
          </archive>
        </configuration>
      </plugin>
      <!-- Copy dependencies -->
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-dependency-plugin</artifactId>
        <version>3.6.1</version>
        <executions>
          <execution>
            <id>copy-dependencies</id>
            <phase>package</phase>
            <goals><goal>copy-dependencies</goal></goals>
            <configuration>
              <outputDirectory>${project.build.directory}/dependency</outputDirectory>
            </configuration>
          </execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>

```

install maven

```java
sudo apt install maven
```

1. Verify which compiler you’re using. and check the versions of the following

```bash
which javac
javac -version
java  -version
mvn -v
```

build locally before pushing to ecr

```java
cd sharing-folders/eks_datadog_vectordot_java/metric-sender-vectordot-java-app
mvn clean package
```

Quick local run test

If you have a DogStatsD listener locally (Datadog Agent/Vector on UDP 8125):

```bash
DOGSTATSD_HOST=127.0.0.1 DOGSTATSD_PORT=8125 \
java -cp target/metric-sender-vectordot-java-1.0.0.jar:target/dependency/* \
  com.example.DogstatsdPing
```

## Dockerfile

Create `Dockerfile`

```docker
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN useradd -u 10001 pyuser
USER pyuser

CMD ["python", "app.py"]
```

# Push the Image To ECR

Create ECR

```yaml
aws ecr create-repository --repository-name metric-sender-with-vectordot-python
```

Create a .github/workflows/metric-sender-with-vector-java.yaml file

```yaml
name: Build and Push metric-sender-with-vectordot to ECR

on:
  push:
    paths:
      - 'sharing-folders/eks_datadog_vectordot_python/**'
      - '.github/workflows/metric-sender-vectordot-python.yaml'
    branches:
      - main

jobs:
  build-and-push:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v3

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: us-east-2

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and Push metric-sender-with-vectordot-python to ECR
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: metric-sender-with-vectordot-python
          IMAGE_TAG: with-vectordot-python
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG ./sharing-folders/eks_datadog_vectordot_python/metric-sender-vectordot-python-app
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

```

Push to Ecr by git

```yaml
git add .
git commit -m '..'
git push origin main
```

# Deploy the sender app

1. Get your full ECR image UR

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-east-2
IMAGE_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/metric-sender-with-vectordot-python:with-vectordot-python"
echo $IMAGE_URI
```

create a deployment.yaml and use the full image_uri

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metric-sender-vectordot-java
  namespace: vector
  labels:
    app: metric-sender-vectordot-java
spec:
  replicas: 1
  selector:
    matchLabels:
      app: metric-sender-vectordot-java
  template:
    metadata:
      labels:
        app: metric-sender-vectordot-java
    spec:
      containers:
        - name: app
          image: 156583401143.dkr.ecr.us-east-2.amazonaws.com/metric-sender-with-vectordot-java:with-vectordot-java
          imagePullPolicy: Always
          env:
            - name: DOGSTATSD_HOST
              value: "vector.vector.svc.cluster.local"
            - name: DOGSTATSD_PORT
              value: "9125"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          securityContext:
            runAsNonRoot: true
            runAsUser: 10001
            allowPrivilegeEscalation: false

```

apply the yaml

```yaml
kubectl apply -f deployment.yaml -n vector

# verify by logs
kubectl logs <pod name> -n vector
# details log
kubectl describe pod <pod name> (metric-sender-66ff56f796-cwll4) -n vector
```

verify 

```yaml
kubectl get pods -l app=metric-sender-vectordot-java -n vector
kubectl logs -f deploy/metric-sender-vectordot-java --tail=50 -n vector
```

ReApply

```yaml
kubectl apply -f deployment.yaml -n vector
kubectl  rollout status sts/vector -n vector
```

**Uninstall the existing release**

```bash
helm uninstall vector -n vector
```

**3️⃣ Verify it’s gone**

```bash
helm list -n vector
```