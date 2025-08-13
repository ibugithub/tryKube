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
role: "Agent"
service:
  enabled: false

podHostNetwork: true
dnsPolicy: ClusterFirstWithHostNet

containerPorts:
  - name: statsd
    containerPort: 9125
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

Create `app.py`:

```python
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
    statsd.increment("ingestion_datadog_agent_python", tags=["app:datadog_agent_python", "env:dev"])
    print(f"[{i}/{MAX_TRIES}] queued metric (DogStatsD)")
  except Exception as e:
    failures += 1
    print(f"[{i}/{MAX_TRIES}] FAILED to send metric: {e}")
  time.sleep(5)

print(f"Done. Attempts={MAX_TRIES}, Failures={failures}")
sys.exit(1 if failures == MAX_TRIES else 0)

```

Create `requirements.txt`:

```
datadog==0.49.1
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
aws ecr create-repository --repository-name metric-sender-with-vectordot-python-app
```

Create a .github/workflows/metric-sender-with-agent-python.yaml file

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
  name: metric-sender-vectordot-python-app
  namespace: vector
  labels:
    app: metric-sender-vectordot-python-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: metric-sender-vectordot-python-app
  template:
    metadata:
      labels:
        app: metric-sender-vectordot-python-app
    spec:
      containers:
        - name: app
          image: 156583401143.dkr.ecr.us-east-2.amazonaws.com/metric-sender-with-vectordot-python-app:with-vectordot-python
          imagePullPolicy: Always
          env:
            - name: DOGSTATSD_HOST
              valueFrom:
                fieldRef:
                  fieldPath: status.hostIP
            - name: DOGSTATSD_PORT
              value: "9125"
            - name: PYTHONUNBUFFERED
              value: "1"
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
kubectl get pods -l app=metric-sender-vectordot-python-app -n vector
kubectl logs -f deploy/metric-sender-vectordot-python-app --tail=50 -n vector
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