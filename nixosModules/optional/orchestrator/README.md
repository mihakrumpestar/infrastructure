# Orchestrator

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
