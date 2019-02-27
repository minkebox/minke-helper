FROM alpine:edge

RUN apk --no-cache add miniupnpc avahi ; rm -f /etc/avahi/services/*.service

COPY root/ /

ENTRYPOINT ["/startup.sh"] 
