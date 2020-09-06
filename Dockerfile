FROM certbot/certbot:v1.6.0
MAINTAINER Sven Knispel <sven.knispel@pwc.com>

#RUN mkdir /etc/letsencrypt
RUN apk add python3 curl

COPY secret-patch-template.json /
COPY deployment-patch-template.json /
COPY entrypoint.sh /

WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/entrypoint.sh"]
