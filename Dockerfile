FROM alpine:latest

RUN apk add miniupnpc

COPY root/ /

HEALTHCHECK --interval=30s --timeout=5s CMD /health.sh

LABEL net.minkebox.system="true"

ENTRYPOINT ["/startup.sh"]
