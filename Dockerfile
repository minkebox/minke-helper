FROM alpine:edge

COPY overlay/ /

RUN apk --no-cache add miniupnpc

ENTRYPOINT ["/startup.sh"]
