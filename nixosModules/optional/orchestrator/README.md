# Orchestrator

## ACLs

ACLs are enabled for both Consul and Nomad. You need to bootstrap them once after initial cluster startup.

### Consul ACL Bootstrap

```sh
# Bootstrap Consul ACLs (run once)
consul acl bootstrap

# Save the SecretID (management token) - you'll need it for Nomad integration
export CONSUL_HTTP_TOKEN=<bootstrapped-token>

# Create agent token for Consul
consul acl token create -name "agent-token" -node-name "<node-name>"

# Set the agent token
consul acl set-agent-token agent <agent-token-secret-id>
```

### Nomad ACL Bootstrap

```sh
# Bootstrap Nomad ACLs (run once)
nomad acl bootstrap

# Save the SecretID (management token)
export NOMAD_TOKEN=<bootstrapped-token>
```

## Nomad

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

## Consul

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
