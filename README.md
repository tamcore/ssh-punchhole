# ssh-punchhole

This is my simple way of exposing my self-hosted services without having to deal with port-forwarding and exposing my private IP to the public.

Technically it only requires a cheap VPS for the public endpoint. But having a local reverse proxy like Traefik is recommended. This container will be the connecting part between the both endpoints. It'll establish a SSH session to the VPS, then open ports there and forward the traffic arriving at those ports to the local destination.

If you fancy, you can have it bind directly to :80 and :443 (which would require it to connect as root), but then you'll lose the ability to log the Source IP. So I'd recommend having a

To create the known_hosts file for HostKeyVerification
````
ssh-keyscan $YOUR_VPS > known_hosts
````
and the id_rsa keypair (don't set a passphrase!)
````
ssh-keygen -f id_rsa
````

docker-compose.yaml
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
      - SSH_PORT=22              # Optional: Change if you have your SSHd running on a non-standard port
      - SSH_USER=root            # Optional: Change, if you want to login as a non-root user
      - REMOTE_HOST=             # Required: Hostname of your VPS
      # And this will forward 127.0.0.1:980 on the VPS to traefik:80 and :9443 to traefik:443
      - "REMOTE_FORWARD=127.0.0.1:980 127.0.0.1:9443"
      - "LOCAL_DESTINATION=traefik:80 traefik:443"
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
````

Example addition to your traefik entryPoints:
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


Example /etc/haproxy/haproxy.cfg for your VPS
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
