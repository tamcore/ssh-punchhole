FROM alpine:3.18.2

RUN apk add --update --no-cache tini bash openssh-client

ENV SSH_PORT 22
ENV SSH_USER root
ENV SSH_OPTS ""
ENV REMOTE_FORWARD ""
ENV LOCAL_DESTINATION ""
ENV IDENTITYFILE /id_rsa

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN addgroup -g 1337 -S joe && \
    adduser -u 1337 -S joe -G joe

USER joe

ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
