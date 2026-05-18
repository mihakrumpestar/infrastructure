# Orchestrator

## Certs

### Nomad

Generate certs (https://developer.hashicorp.com/nomad/docs/secure/traffic/tls):

```sh
cd infrastructure-secrets/secrets/nomad

# 100 year validity
nomad tls ca create -days 36524

nomad tls cert create -server \
  -additional-ipaddress 10.0.30.10 \
  -additional-ipaddress 10.0.30.20 \
  -additional-ipaddress 10.0.30.30 \
  -days 36523

nomad tls cert create -client \
  -additional-ipaddress 10.0.30.10 \
  -additional-ipaddress 10.0.30.20 \
  -additional-ipaddress 10.0.30.30 \
  -days 36523

nomad tls cert create -cli \
  -days 36523

# Generate client cert for browser
step certificate p12 --no-password --insecure \
  --ca nomad-agent-ca.pem \
  global-cli-nomad.p12 \
  global-cli-nomad.pem global-cli-nomad-key.pem
```

### Consul

```sh
cd infrastructure-secrets/secrets/consul

# 100 year validity
consul tls ca create -days 36524

consul tls cert create -server \
  -domain=consul \
  -additional-ipaddress=10.0.30.10 \
  -additional-ipaddress=10.0.30.20 \
  -additional-ipaddress=10.0.30.30 \
  -days 36523

consul tls cert create -client \
  -additional-ipaddress 10.0.30.10 \
  -additional-ipaddress 10.0.30.20 \
  -additional-ipaddress 10.0.30.30 \
  -days 36523

consul tls cert create -cli \
  -days 36523

step certificate p12 --no-password --insecure \
  --ca consul-agent-ca.pem \
  dc1-cli-consul-0.p12 \
  dc1-cli-consul-0.pem dc1-cli-consul-0-key.pem
```

## ACLs

ACLs are enabled for both Consul and Nomad with workload identity support (Nomad 1.7+).

### Initial Bootstrap (one-time setup)

#### 1. Consul ACL Bootstrap

```sh
# Bootstrap Consul ACLs (run once on any server)
consul acl bootstrap

# Save the SecretID (management token) - you'll need it for all subsequent operations
export CONSUL_HTTP_TOKEN=<management-token>
```

#### 2. Consul Agent Token

For the Consul agent itself (to register in the catalog and perform internal operations), you need an agent token:

```sh
# Set management token for CLI operations
export CONSUL_HTTP_TOKEN=<management-token-from-bootstrap>

# Universal agent policy for all nodes
cat > /tmp/agent-policy.hcl << 'EOF'
# Allow agent to read its own agent API
agent_prefix "" {
  policy = "read"
}

# Allow agent to register/update any node in catalog
node_prefix "" {
  policy = "write"
}

# Allow agent to register services (Nomad, Consul Connect, etc.)
service_prefix "" {
  policy = "write"
}
EOF

# Create the policy once
consul acl policy create -name "agent-policy" -rules @/tmp/agent-policy.hcl

# Create token with this policy (works on any node)
consul acl token create \
  -description "agent-token" \
  -policy-name "agent-policy"

# Set tokens to agent (do on each agent)
consul acl set-agent-token default <agent-token-secret-id>
consul acl set-agent-token agent <agent-token-secret-id>
```

With `enable_token_persistence = true`, tokens are persisted to disk.
If that is not set on, we would have to specify them in config to retain them.

#### 3. Create Consul Auth Method for Nomad Workload Identity

This allows Nomad workloads to authenticate to Consul automatically:

```sh
# Create auth method config
# Note: Uses http://127.0.0.1:4649 which is proxied through Caddy
# Caddy handles mTLS to Nomad and exposes only the JWKS endpoint
cat > /tmp/consul-auth-method.json << 'EOF'
{
  "JWKSURL": "http://127.0.0.1:4649/.well-known/jwks.json",
  "JWTSupportedAlgs": ["RS256"],
  "BoundAudiences": ["consul.io"],
  "ClaimMappings": {
    "nomad_namespace": "nomad_namespace",
    "nomad_job_id": "nomad_job_id",
    "nomad_task": "nomad_task",
    "nomad_service": "nomad_service"
  }
}
EOF

# Create the auth method
consul acl auth-method create \
  -name "nomad-workloads" \
  -type "jwt" \
  -description "Auth method for Nomad workload identities" \
  -config @/tmp/consul-auth-method.json
```

**Why Caddy proxy?**
Nomad is configured with `verify_https_client = true` (mTLS), requiring client certificates on all HTTPS endpoints. Consul's JWKS fetcher cannot provide client certificates, so Caddy proxies the endpoint on localhost:4649 → Nomad:4646 with mTLS, exposing only the public JWKS endpoint.

#### 4. Create Consul Binding Rules

```sh
# Binding rule for services
consul acl binding-rule create \
  -method 'nomad-workloads' \
  -description 'Services authenticated via workload identity' \
  -selector '"nomad_service" in value' \
  -bind-type service \
  -bind-name '${value.nomad_service}'

# Binding rule for tasks
consul acl binding-rule create \
  -method 'nomad-workloads' \
  -description 'Tasks authenticated via workload identity' \
  -selector '"nomad_service" not in value' \
  -bind-type role \
  -bind-name 'nomad-${value.nomad_namespace}-tasks'
```

#### 5. Nomad ACL Bootstrap

```sh
# Bootstrap Nomad ACLs (run once on any server)
nomad acl bootstrap

# Save the SecretID (management token)
export NOMAD_TOKEN=<management-token>
```

### UI Access

First import client certificates in browser.

#### Nomad UI

```sh
# Generate one-time access token
nomad ui -authenticate
```

Or access `https://<node-ip>:4646/ui` and login with management token.

#### Consul UI

Access `https://<node-ip>:8501/ui` and login with ACL management token.

// TODO: from this forward it is unverified

### Metrics Access (Prometheus)

With ACLs enabled, metrics endpoints require authentication.

#### Nomad Metrics

```sh
# Create policy for Nomad metrics read access
cat > /tmp/nomad-metrics-policy.hcl << 'EOF'
node {
  policy = "read"
}

namespace "default" {
  capabilities = ["read-job"]
}
EOF

nomad acl policy create -name "metrics" -rules @/tmp/nomad-metrics-policy.hcl

# Create token for Prometheus
nomad acl token create -name "prometheus-metrics" -policy metrics
# Save the SecretID for your Prometheus config
```

#### Consul Metrics

```sh
# Create policy for Consul metrics
cat > /tmp/consul-metrics-policy.hcl << 'EOF'
node {
  policy = "read"
}
service {
  policy = "read"
}
EOF

consul acl policy create -name "metrics" -rules @/tmp/consul-metrics-policy.hcl
consul acl token create -description "prometheus-metrics" -policy metrics
# Save the SecretID for your Prometheus config
```

#### Prometheus Configuration

```yaml
scrape_configs:
  - job_name: 'nomad'
    scheme: https
    tls_config:
      ca_file: /path/to/nomad-agent-ca.pem
    authorization:
      credentials: <nomad-metrics-token>
    static_configs:
      - targets: ['<node-ip>:4646']
  
  - job_name: 'consul'
    scheme: https
    tls_config:
      ca_file: /path/to/consul-agent-ca.pem
    authorization:
      credentials: <consul-metrics-token>
    static_configs:
      - targets: ['<node-ip>:8501']
```

### Mesh Intentions

With ACLs enabled, service-to-service communication requires intentions.

#### Default Mesh Policy

```sh
# Option A: Allow all by default (less secure)
consul config write - <<EOF
{
  "Kind": "mesh",
  "Defaults": {
    "DefaultIntentionPolicy": "allow"
  }
}
EOF

# Option B: Deny all by default (recommended)
consul config write - <<EOF
{
  "Kind": "mesh",
  "Defaults": {
    "DefaultIntentionPolicy": "deny"
  }
}
EOF
```

#### Create Intentions

```sh
# Allow web → api
consul config write - <<EOF
{
  "Kind": "service-intentions",
  "Name": "api",
  "Sources": [
    {
      "Name": "web",
      "Action": "allow"
    }
  ]
}
EOF

# L7 intentions (path-based)
consul config write - <<EOF
{
  "Kind": "service-intentions",
  "Name": "api",
  "Sources": [
    {
      "Name": "web",
      "Permissions": [
        {
          "Action": "allow",
          "HTTP": {
            "PathPrefix": "/api/",
            "Methods": ["GET", "POST"]
          }
        },
        {
          "Action": "deny",
          "HTTP": {
            "PathPrefix": "/api/admin/"
          }
        }
      ]
    }
  ]
}
EOF
```

### Variables

Nomad variables work automatically. Tasks can read variables from their job path without additional configuration.

#### Store Variables

```sh
# Store a variable for a job
nomad var put nomad/jobs/myapp/config api_key=secret123
```

#### Use in Jobs

```hcl
job "myapp" {
  group "web" {
    task "api" {
      template {
        data = <<EOF
API_KEY={{ with nomadVar "nomad/jobs/myapp/config" }}{{ .Value.api_key }}{{ end }}
EOF
        destination = "local/config"
      }
    }
  }
}
```

Tasks automatically have read access to `nomad/jobs/<job-id>/*` paths.
