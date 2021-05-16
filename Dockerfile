FROM alpine:3.12

RUN apk add bash miniupnpc iptables iproute2

COPY root/ /
RUN chmod 755 /wondershaper.sh /health.sh /startup.sh

HEALTHCHECK --interval=30s --timeout=5s CMD /health.sh

LABEL net.minkebox.system="true"

ENTRYPOINT ["/startup.sh"]
