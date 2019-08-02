FROM alpine:latest

RUN apk add miniupnpc

COPY root/ /

ENTRYPOINT ["/startup.sh"] 
