FROM alpine:edge

RUN apk --no-cache add miniupnpc avahi iptables ;\
    rm -f /etc/avahi/services/*.service

COPY root/ /

ENTRYPOINT ["/startup.sh"] 
