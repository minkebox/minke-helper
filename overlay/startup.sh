#! /bin/sh

if [ "${IFACE}" = "" ]; then
  IFACE=eth0
fi
TTL=3600 # 1 hour
TTL2=1800 # TTL/2

if [ "${IP}" = "" -a "${ENABLE_DHCP}" = "" ]; then
  echo "No IP or ENABLE_DHCP set"
  exit 1
fi

if [ "${ENABLE_DHCP}" != "" ]; then
  udhcpc -R -i ${IFACE} -s /udhcpc.script -F ${HOSTNAME} -x hostname:${HOSTNAME}
  IP=$(ip addr show dev ${IFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
fi

up()
{
  if [ "${ENABLE_NAT}" != "" ]; then
    for map in ${ENABLE_NAT}; do
      # port:protocol
      port=${map%%:*}
      protocol=${map#*:}
      upnpc -a ${IP} ${port} ${port} ${protocol} ${TTL}
    done
  fi
}

down()
{
  if [ "${ENABLE_NAT}" != "" ]; then
    for map in ${ENABLE_NAT}; do
      # port:protocol
      port=${map%%:*}
      protocol=${map#*:}
      upnpc -d ${port} ${protocol}
    done
  fi
  if [ "${ENABLE_DHCP}" != "" ]; then
    killall udhcpc
  fi
}

trap "down; killall sleep; exit" TERM INT

while true; do
  up
  sleep ${TTL2} &
  wait "$!"
done
