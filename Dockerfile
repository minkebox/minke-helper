FROM alpine:latest

RUN apk add bash miniupnpc iptables iproute2

COPY root/ /

HEALTHCHECK --interval=30s --timeout=5s CMD /health.sh

LABEL net.minkebox.system="true"

ENTRYPOINT ["/startup.sh"]
