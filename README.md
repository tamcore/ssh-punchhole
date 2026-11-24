# ssh-punchhole

This is my simple way of exposing my self-hosted services without having to deal with port-forwarding and exposing my home IP to the public.

Technically it only requires a cheap VPS for the public endpoint and could forward the traffic directly to your service (i.e. Nextcloud). But having a local reverse proxy like Traefik is recommended.

This container will be the connecting part between the both endpoints. It'll establish a SSH session to the VPS, open (public) ports there and forward the traffic arriving at those ports to the local destination.

If you fancy, you can have it bind directly to :80 and :443 (which would require it to connect as root, as everything bellow 1024 is restricted), but then you'll lose the ability to log the Source IP. So I'd recommend having a reverse proxy running on your VPS as well and have it configured to forward incoming (public) traffic to your local (tunnel) ports. If you want to bind to a non-loopback IP (i.e. 0.0.0.0 or your servers public IP), you have to set `GatewayPorts clientspecified` in your server's `sshd_config` (see [Remote host sshd configuration](#remote-host-sshd-configuration)). Additionally, if the port is bellow 1024, you'll have to connect as root.

## Quickstart with haproxy on the VPS, docker-compose for your this tunneling container and Traefik as reverse Proxy

1. Create the known_hosts file for HostKeyVerification
````
ssh-keyscan ${IP_OF_YOUR_VPS} > known_hosts
````
2. Create an id_rsa keypair (don't set a passphrase!)
````
ssh-keygen -f id_rsa
````
3. Create your docker-compose.yaml similar to this
 - Instead of using relative paths for your volumes you might want to use absolute paths
 - This will have the ssh-punchhole container connect as root on your VPS
    - and open both port 980 and 9443 on localhost (127.0.0.1)
    - and forward their traffic to traefik:80 and traefik:443
    - **Note:** If you, for example, would want to have both 980 and 9443 forwarded to the same destination, just omit the last destination. The script will take notice and use the first (and only) provided destination.
    - In this example, my traefik bridge network is called traefik-net, you might have to adjust that to your specific setup. Also, my instance of Traefik is deployed with the name "traefik". You might want to adjust that as well.
````
version: "3"

services:
  ssh-punchhole:
    container_name: ssh-punchhole
    image: ghcr.io/tamcore/ssh-punchhole:v1
    volumes:
      - './id_rsa:/id_rsa:ro'
      - './known_hosts:/known_hosts:ro'
    restart: unless-stopped
    environment:
      - SSH_PORT=22                             # Optional: Change if you have your SSHd running on a non-standard port
      - SSH_USER=root                           # Optional: Change, if you want to login as a non-root user
      - REMOTE_HOST=${IP_OF_YOUR_VPS}           # Required: Hostname of your VPS
      # And this will forward 127.0.0.1:980 on the VPS to traefik:80 and :9443 to traefik:443
      - "REMOTE_FORWARD=127.0.0.1:980 127.0.0.1:9443"
      - "LOCAL_DESTINATION=traefik:80 traefik:443"
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
````
4. To tell Traefik to trust the proxyProtocol headers it receives through the SSH-Tunnel, you'll have to add 10.0.0.0/16 as proxyProtocol.trustedIps for your endPoints. For my setup, the traefik.yaml contains the following
````
entryPoints:
  http:
    address: ":80"
    proxyProtocol:
      trustedIPs:
        - "10.0.0.0/16"
  https:
    address: ":443"
    proxyProtocol:
      trustedIPs:
        - "10.0.0.0/16"
````
5. Now, all that's left, is to install haproxy on your VPS (something alongside *{apt,dnf,yum} install haproxy* should do the trick) with an /etc/haproxy/haproxy.cfg configuration similar to
  - This will publicly open ports 80 and 443 on all available IP addresses provisioned on the VPS and forward the traffic as follows
    - $ENDUSER -> 0.0.0.0:80  (aka HTTP)  -> localhost:980  -> \<through your tunnel\> -> traefik:80  -> $WHATEVER_SERVICE
    - $ENDUSER -> 0.0.0.0:443 (aka HTTPS) -> localhost:9443 -> \<through your tunnel\> -> traefik:443 -> $WHATEVER_SERVICE
````
global
   maxconn 4096

defaults
   log   global
   mode   http
   retries   3
   option redispatch
   maxconn   2000
   timeout connect 5000
   timeout client  50000
   timeout server  50000

frontend http
    bind 0.0.0.0:80
    mode tcp
    default_backend backend-http

frontend https
    bind 0.0.0.0:443
    mode tcp
    default_backend backend-https

backend backend-http
    mode tcp
    server localhost 127.0.0.1:980 send-proxy-v2

backend backend-https
    mode tcp
    server localhost 127.0.0.1:9443 send-proxy-v2
````

## Features (v2.5.0+)

### Connection Resilience

Automatic reconnection with exponential backoff when SSH connections fail:

- **Keepalive**: Detects dead connections within 30 seconds (configurable)
- **Retry Logic**: Up to 10 reconnection attempts with exponential backoff
- **Health Checks**: Kubernetes liveness/readiness probes for automatic pod restart
- **Graceful Shutdown**: Clean SSH termination on pod deletion

**Configuration:**
```yaml
configuration:
  SSH_SERVER_ALIVE_INTERVAL: "10"    # Send keepalive every 10s
  SSH_SERVER_ALIVE_COUNT_MAX: "3"    # Fail after 3 missed keepalives
  SSH_CONNECT_TIMEOUT: "30"          # Connection timeout (seconds)
  SSH_MAX_RETRIES: "10"              # Max reconnection attempts
  SSH_INITIAL_BACKOFF: "5"           # Initial retry delay (seconds)
  SSH_MAX_BACKOFF: "300"             # Maximum retry delay (seconds)
```

### Performance Optimization

Optimized for file transfers and low-latency connections:

- **Fast Cipher**: ChaCha20-Poly1305 (CPU-friendly, fast)
- **IP QoS**: Low latency network prioritization
- **Disabled Auth Methods**: Faster connection establishment

**Configuration:**
```yaml
configuration:
  SSH_CIPHER: "chacha20-poly1305@openssh.com"  # Options: chacha20-poly1305@openssh.com, aes128-gcm@openssh.com, aes256-gcm@openssh.com
  SSH_COMPRESSION: "no"                        # Enable for text traffic, disable for binary
  SSH_IPQOS: "lowdelay"                        # Options: lowdelay, throughput, reliability
```

**Performance Tips:**
- Use `chacha20-poly1305@openssh.com` for best CPU efficiency (default)
- Use `aes128-gcm@openssh.com` if your CPU has AES-NI hardware acceleration
- Enable compression (`SSH_COMPRESSION: "yes"`) for text-heavy traffic only
- Use `SSH_IPQOS: "throughput"` for bulk data transfers

### Health Checks

Kubernetes probes automatically detect and restart failed tunnels:

**Configuration:**
```yaml
healthcheck:
  enabled: true  # Enabled by default
  livenessProbe:
    initialDelaySeconds: 30
    periodSeconds: 30
    timeoutSeconds: 10
    failureThreshold: 3
  readinessProbe:
    initialDelaySeconds: 10
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 2
```

**How it works:**
1. Health check script verifies SSH process is running
2. Validates SSH control socket exists
3. Tests connection responsiveness
4. Kubernetes restarts pod if checks fail

### Observability & Metrics

Optional Prometheus-compatible metrics for monitoring tunnel health. The metrics collector is included in the main container and runs as a sidecar when enabled.

**Metrics Exposed:**
- `ssh_punchhole_up` - Tunnel status (1=up, 0=down)
- `ssh_punchhole_connection_duration_seconds` - Current connection uptime
- `ssh_punchhole_bytes_sent_total` - Total bytes sent
- `ssh_punchhole_bytes_received_total` - Total bytes received
- `ssh_punchhole_retransmits_total` - TCP retransmissions (connection quality)
- `ssh_punchhole_container_uptime_seconds` - Container uptime
- `ssh_punchhole_haproxy_metrics_up` - Remote haproxy metrics fetched (1) or not (0). Only with `PROXY_PROTOCOL=true`
- `haproxy_*` - Metrics of the remote haproxy (built-in Prometheus exporter), for example `haproxy_frontend_current_sessions{proxy="fe_443"}`. Only with `PROXY_PROTOCOL=true` (v2.7.0+)

**Enable Metrics (Opt-in):**
```yaml
metrics:
  enabled: true
  collectionInterval: 30  # Scrape interval in seconds

  # Optional: Enable ServiceMonitor for Prometheus Operator
  serviceMonitor:
    enabled: true
    interval: 30s
```

**How it works:**
- Metrics collector runs as sidecar with `command: ["/metrics-collector.sh"]`
- Exposed on port 9090 at `/ssh_punchhole.prom`
- Configure alerts via `metrics.prometheusRule` in values.yaml
- With `PROXY_PROTOCOL=true`, the remote haproxy serves its metrics on a unix socket (`/tmp/sph-metrics-<pod name>.sock`, mode 600). The SSH session forwards it to `127.0.0.1:<HAPROXY_METRICS_PORT>` (default `9101`) in the pod. The collector fetches it on each interval and appends it to the same file, so the haproxy metrics are up to `collectionInterval` old

### PROXY Protocol (v2.6.0+)

Opt-in mode that keeps the client source IP. The container starts a temporary haproxy on the remote host. haproxy binds the public port and sends the PROXY protocol header to the tunnel. You do not need to configure haproxy on the remote host yourself (see the Quickstart above for the manual way).

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `PROXY_PROTOCOL` | `true`, `false` | `false` | Enable PROXY protocol mode for all forwards of this tunnel |
| `PROXY_PROTOCOL_VERSION` | `1`, `2` | `2` | `1` uses haproxy `send-proxy`, `2` uses `send-proxy-v2` |
| `HAPROXY_METRICS_PORT` | port | `9101` | Local port in the pod for the haproxy metrics forward (v2.7.0+). Must be free in the pod; with the default `ExitOnForwardFailure=yes`, a port in use stops the tunnel |

For each `REMOTE_FORWARD` entry `<addr>:<port>`:

- The tunnel binds `127.0.0.1:<10000+port>` on the remote host.
- haproxy binds `<addr>:<port>` in TCP mode and forwards to the tunnel with the PROXY header. `0.0.0.0`, `*` or no address binds IPv4 and IPv6 separately (`0.0.0.0:<port>` and `:::<port> v6only`), so IPv4 clients appear as plain IPv4 addresses in the PROXY header. The remote host must have IPv6 enabled; else set an explicit IPv4 address.
- The public port must be between 1 and 55535. A tunnel port must not be equal to a public port of the same tunnel.

The local destination must accept the PROXY protocol (for example nginx `listen ... proxy_protocol`, Traefik `proxyProtocol.trustedIPs`).

haproxy runs as the remote command of the SSH session and stops when the session ends. When the session stays open but haproxy stops, the container reconnects. This mode always uses `ControlPersist=no`; a `ControlPersist` value in `SSH_OPTS` has no effect.

**Remote host requirements:**

- `haproxy` must be installed (e.g. `dnf install haproxy`). Do not enable its system service. If `haproxy` is not found or cannot run (remote exit code 127), the container stops immediately and does not retry.
- The remote login shell must be POSIX compatible (sh, bash, zsh).
- `GatewayPorts` must be `no` or `clientspecified`, **never `yes`**. See [Remote host sshd configuration](#remote-host-sshd-configuration).
- Ports below 1024 require a privileged bind: `SSH_USER=root`, `CAP_NET_BIND_SERVICE` for haproxy, or `net.ipv4.ip_unprivileged_port_start` set to the lowest public port or less.
- `ClientAliveInterval` should be set. See [Remote host sshd configuration](#remote-host-sshd-configuration).
- For haproxy metrics (v2.7.0+): haproxy must be built with the Prometheus exporter (`haproxy -vv` shows `+PROMEX`), and sshd must allow `AllowStreamLocalForwarding` (default `yes`). Without them, only `ssh_punchhole_haproxy_metrics_up` is `0`; the tunnel works.

Use separate tunnels (Helm: list form of `configuration`) to mix PROXY and plain forwards:

```yaml
configuration:
  - REMOTE_HOST: "pub.example.com"
    REMOTE_FORWARD: "0.0.0.0:80 0.0.0.0:443"
    LOCAL_DESTINATION: "gateway.svc:80 gateway.svc:443"
    PROXY_PROTOCOL: "true"
  - REMOTE_HOST: "pub.example.com"
    REMOTE_FORWARD: "0.0.0.0:5000"
    LOCAL_DESTINATION: "app.svc:5000"
```

### Remote host sshd configuration

Recommended `sshd_config` settings on the remote host, for example in `/etc/ssh/sshd_config.d/50-ssh-punchhole.conf`:

```
GatewayPorts clientspecified
ClientAliveInterval 10
ClientAliveCountMax 3
```

Reload sshd after the change (e.g. `systemctl reload sshd`).

**`GatewayPorts`** controls which address a remote forward (`-R`) binds:

| Value | Behavior |
|-------|----------|
| `no` (default) | Always binds loopback. `REMOTE_FORWARD=0.0.0.0:<port>` is not public. |
| `clientspecified` | Binds the address in `REMOTE_FORWARD`. Use this value. |
| `yes` | Always binds all addresses and ignores the address in `REMOTE_FORWARD`. |

> **Security warning:** Do not use `GatewayPorts yes` with `PROXY_PROTOCOL=true`. sshd then binds the tunnel ports (`10000+port`) on all addresses instead of `127.0.0.1`. Clients can connect to the tunnel port directly, bypass haproxy and send a forged PROXY header with a false source IP. Also block the tunnel ports in the firewall of the remote host as a second layer.

**`ClientAliveInterval`** makes sshd detect a dead client. The default `0` disables this check. After a network drop without a TCP close (for example a NAT timeout or a link failure), sshd keeps the old session until TCP keepalive closes it, which can take hours. During this time the old session holds the forwarded ports (and, with `PROXY_PROTOCOL=true`, the haproxy ports). The reconnect then fails with `remote port forwarding failed` or haproxy `cannot bind socket`. With `ClientAliveInterval 10` and `ClientAliveCountMax 3`, sshd closes the old session after approximately 30 seconds.

## Kubernetes / Helm Usage

Install via Helm:

```bash
# Add repository
helm repo add tamcore https://ghcr.io/tamcore/charts

# Install basic tunnel
helm install my-tunnel tamcore/ssh-punchhole \
  --set configuration.REMOTE_HOST=your-vps.example.com \
  --set configuration.REMOTE_FORWARD="0.0.0.0:80 0.0.0.0:443" \
  --set configuration.LOCAL_DESTINATION="nginx:80 nginx:443" \
  --set data.privateKey="$(cat id_rsa)" \
  --set data.knownHosts="$(cat known_hosts)"

# Install with metrics enabled
helm install my-tunnel tamcore/ssh-punchhole \
  --set configuration.REMOTE_HOST=your-vps.example.com \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true \
  --set-file data.privateKey=./id_rsa \
  --set-file data.knownHosts=./known_hosts
```

**Minimal values.yaml:**

```yaml
configuration:
  REMOTE_HOST: "vps.example.com"
  REMOTE_FORWARD: "0.0.0.0:80 0.0.0.0:443"
  LOCAL_DESTINATION: "ingress-nginx:80 ingress-nginx:443"

data:
  privateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
  knownHosts: |
    vps.example.com ssh-rsa AAAAB3...

# Optional: Enable metrics and alerts
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
  prometheusRule:
    enabled: true
```

See chart/values.yaml for all available options.

## Troubleshooting

- **Connection fails**: Check SSH key authorization, known_hosts, and pod logs
- **Frequent disconnects**: Check `ssh_punchhole_retransmits_total` metric, review VPS firewall
- **Poor performance**: Try `SSH_CIPHER: "aes128-gcm@openssh.com"` or `SSH_IPQOS: "throughput"`
- **Health checks fail**: Increase `healthcheck.livenessProbe.initialDelaySeconds`
- **No metrics**: Verify Prometheus Operator installed, check ServiceMonitor labels
- **`remote port forwarding failed` or haproxy `cannot bind socket` after a reconnect**: An old session still holds the port on the remote host. Set `ClientAliveInterval` (see [Remote host sshd configuration](#remote-host-sshd-configuration)). With `PROXY_PROTOCOL=true`, also make sure the haproxy system service is stopped
- **`ssh_punchhole_haproxy_metrics_up` is `0`**: Check `haproxy -vv | grep PROMEX` on the remote host and `AllowStreamLocalForwarding` in its sshd configuration. In the ssh-punchhole log, `open failed` means the socket forward was rejected or the socket is missing
- **PROXY protocol: tunnel ports `10000+port` are public**: `GatewayPorts yes` is set on the remote host. Change it to `clientspecified`

## Migration from v1.x

v2.5.0 is backwards compatible. New features are opt-in (except health checks, enabled by default).

## Development

### Running Tests

```bash
# Run BATS tests
bats .

# Build Docker image
docker build -t ssh-punchhole:test .
```

### Building Locally

```bash
# Build image
docker build -t ghcr.io/tamcore/ssh-punchhole:latest .

# Run SSH tunnel
docker run --rm -it \
  -e REMOTE_HOST=vps.example.com \
  -e REMOTE_FORWARD="127.0.0.1:8080" \
  -e LOCAL_DESTINATION="nginx:80" \
  -v $(pwd)/id_rsa:/id_rsa:ro \
  -v $(pwd)/known_hosts:/known_hosts:ro \
  ghcr.io/tamcore/ssh-punchhole:latest

# Run metrics collector (same image, different command)
docker run --rm -it \
  -e REMOTE_HOST=vps.example.com \
  -e SSH_PORT=22 \
  -p 9090:9090 \
  ghcr.io/tamcore/ssh-punchhole:latest \
  /metrics-collector.sh
```
