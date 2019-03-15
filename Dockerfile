FROM alpine:latest

RUN apk --no-cache add miniupnpc

COPY root/ /

ENTRYPOINT ["/startup.sh"] 
