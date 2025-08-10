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

## 3.2 Dockerfile

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