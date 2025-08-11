# add Helm repo + namespace :

```yaml
eksctl create cluster \
    --name exercises-learning \
    --region us-east-2 \
    --nodegroup-name linux-nodes \
    --node-type t3.small \ 
    --nodes 1 \                         
    --nodes-min 1 \ 
    --nodes-max 2 \  
    --managed
```

make sure your kube context points to the cluster:

```yaml
aws eks --region us-east-2 update-kubeconfig --name exercises-learning
kubectl get nodes -o wide
```

# add Helm repo + namespace :

```yaml
helm repo add datadog https://helm.datadoghq.com
helm repo update
kubectl create namespace datadog

#check the namespace created
kubectl get ns datadog
```

# store your API key as a secret:

```yaml
kubectl create secret generic datadog-secret \
  -n datadog \
  --from-literal api-key='5cdea018e3f97b9fbfd267fe342bb3a8'
```

You can verify that your `datadog-secret` was created in the `datadog` namespace with:

```yaml
kubectl get secret datadog-secret -n datadog

#with actual values:
kubectl get secret datadog-secret -n datadog -o jsonpath='{.data.api-key}' | base64 --decode

```

# create a minimal values file for DogStatsD + Admission Controller:

```yaml
cat > datadog-values.yaml <<'YAML'
datadog:
  site: us5.datadoghq.com
  apiKeyExistingSecret: datadog-secret
  dogstatsd:
    port: 8125
    useHostPort: true
    nonLocalTraffic: true
  kubelet:
    tlsVerify: false

# Admission Controller injects DD_AGENT_HOST/DD_* tags into pods automatically
admissionController:
  enabled: true
  mutateUnlabelled: true
YAML
```

# install the Agent (DaemonSet + Cluster Agent)

```yaml
helm install datadog datadog/datadog -n datadog -f datadog-values.yaml
```

verify agent installation:

```yaml
#check the ds, deployment, pods
kubectl get ds,deploy,pods -n datadog

# Confirm hostPort/UDP 8125 is present on the Agent container
kubectl -n datadog get ds datadog \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="agent")].ports}'
#You should see an entry including "containerPort":8125,"hostPort":8125,"protocol":"UDP"

# quick peek at the Agent container args/env
kubectl -n datadog describe ds datadog | sed -n '/Containers:/,/Events:/p' | sed -n '/agent/,/^\s*-/p'

#Is the Admission Controller (webhook) running?
kubectl -n datadog get deploy datadog-cluster-agent
kubectl get mutatingwebhookconfigurations | grep -i datadog
#You should see a MutatingWebhookConfiguration for Datadog (often named datadog-webhook)
```

check logs:

```yaml
kubectl logs <pods name> -n datadog
```

restart and upgrade datadog

```yaml
kubectl -n datadog rollout restart ds/datadog
helm upgrade datadog datadog/datadog -n datadog -f datadog-values.yaml
```

## Write the app

Create `app.py`:

```python
python
CopyEdit
import os
import time
from datadog import DogStatsd

host = os.getenv("DOGSTATSD_HOST", "127.0.0.1")
port = int(os.getenv("DOGSTATSD_PORT", "8125"))

statsd = DogStatsd(host=host, port=port)

print(f"Starting metrics loop -> host={host} port={port}")
while True:
    # counter + a couple of tags
    statsd.increment("ingestion_datadog", tags=["app:py-dogstatsd", "env:dev"])
    time.sleep(5)

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
aws ecr create-repository --repository-name metric-sender-with-agent-python
```

Create a .github/workflows/metric-sender-with-agent-python.yaml file

```yaml
name: Build and Push metric-sender-with-agent-python to ECR

on:
  push:
    paths:
      - 'sharing-folders/eks_datadog_agent_python/**'
      - '.github/workflows/metric-sender-with-agent-python.yaml'
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

      - name: Build and Push metric-sender-with-agent-python to ECR
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: metric-sender-with-agent-python
          IMAGE_TAG: with-agent-python
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG ./sharing-folders/eks_datadog_agent_python/metric-sender-agent-python
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
IMAGE_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/metric-sender-with-agent-python:with-agent-python"
echo $IMAGE_URI
```

create a deployment.yaml and use the full image_uri

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metric-sender-agent-python
  namespace: datadog
  labels:
    app: metric-sender-agent-python
spec:
  replicas: 1
  selector:
    matchLabels:
      app: metric-sender-agent-python
  template:
    metadata:
      labels:
        app: metric-sender-agent-python
    spec:
      containers:
        - name: app
          image: 156583401143.dkr.ecr.us-east-2.amazonaws.com/metric-sender-with-agent-python:with-agent-python
          imagePullPolicy: IfNotPresent
          env:
            - name: DOGSTATSD_HOST
              valueFrom:
                fieldRef:
                  fieldPath: status.hostIP
            - name: DOGSTATSD_PORT
              value: "8125"
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
kubectl apply -f deployment.yaml -n datadog

# verify by logs
kubectl logs <pod name> -n datadog
# details log
kubectl -n datadog describe pod <pod name> (metric-sender-66ff56f796-cwll4) 
```

verify 

```yaml
kubectl rollout status deploy/metric-sender-agent-python -n datadog 
kubectl get pods -l app=metric-sender-agent-python -n datadog
kubectl logs -f deploy/metric-sender-agent-python --tail=50 -n datadog
```

ReApply

```yaml
kubectl apply -f deployment.yaml -n datadog
kubectl rollout status deploy/metric-sender-agent-python -n datadog 
```