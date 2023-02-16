# ssh-punchhole

This is my simple way of exposing my self-hosted services without having to deal with port-forwarding and exposing my home IP to the public.

Technically it only requires a cheap VPS for the public endpoint and could forward the traffic directly to your service (i.e. Nextcloud). But having a local reverse proxy like Traefik is recommended.

This container will be the connecting part between the both endpoints. It'll establish a SSH session to the VPS, open (public) ports there and forward the traffic arriving at those ports to the local destination.

If you fancy, you can have it bind directly to :80 and :443 (which would require it to connect as root, as everything bellow 1024 is restricted), but then you'll lose the ability to log the Source IP. So I'd recommend having a reverse proxy running on your VPS as well and have it configured to forward incoming (public) traffic to your local (tunnel) ports. If you want to bind to a non-loopback IP (i.e. 0.0.0.0 or your servers public IP), you have to enable the `GatewayPorts` in your server's `sshd_config`. Additionally, if the port is bellow 1024, you'll have to connect as root.

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
