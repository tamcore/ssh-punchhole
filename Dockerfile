FROM alpine:3.23.3

RUN apk add --update --no-cache bash openssh-client iproute2-ss busybox-extras

ENV SSH_PORT 22
ENV SSH_USER root
ENV SSH_OPTS ""
ENV REMOTE_FORWARD ""
ENV LOCAL_DESTINATION ""
ENV IDENTITYFILE /id_rsa

COPY ./entrypoint.sh /entrypoint.sh
COPY ./healthcheck.sh /healthcheck.sh
COPY ./metrics-collector.sh /metrics-collector.sh
RUN chmod +x /entrypoint.sh /healthcheck.sh /metrics-collector.sh

EXPOSE 9090

USER nobody

ENTRYPOINT ["/entrypoint.sh"]
