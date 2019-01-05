#! /bin/sh

if [ "${IFACE}" = "" ]; then
  IFACE=eth0
fi
TTL=3600 # 1 hour
TTL2=1800 # TTL/2

if [ "${NAME}" = "" ]; then
  echo "Name not set"
  exit 1
fi
if [ "${IP}" = "" -a "${ENABLE_DHCP}" = "" ]; then
  echo "No IP or ENABLE_DHCP set"
  exit 1
fi

if [ "${ENABLE_DHCP}" != "" ]; then
  udhcpc -R -i ${IFACE} -s /udhcpc.script -F ${HOSTNAME} -x hostname:${HOSTNAME}
  IP=$(ip addr show dev ${IFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  echo "MINKE:DHCP:UP ${IFACE} ${IP}"
fi

if [ "${ENABLE_MDNS}" != "" ] ; then
  /usr/sbin/avahi-daemon --no-drop-root -D
  for map in ${ENABLE_MDNS}; do
    type=${map%%:*}
    map3=${map#*:}
    port=${map3%%:*}
    txt=${map3#*:}
    if [ "${port}" = "${txt}" ]; then
      txt=""
    fi
    if [ "${txt}" != "" ]; then
      txt="TXT ${txt}"
    fi
    avahi-publish -s ${NAME} ${type} ${port} ${txt}
  done
  echo "MINKE:MDNS:UP"
fi

up()
{
  if [ "${ENABLE_NAT}" != "" ]; then
    for map in ${ENABLE_NAT}; do
      # port:protocol
      port=${map%%:*}
      protocol=${map#*:}
      upnpc -a ${IP} ${port} ${port} ${protocol} ${TTL}
      echo "MINKE:NAT:UP ${IP} ${port} ${protocol} ${TTL}"
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
      echo "MINKE:NAT:DOWN ${IP} ${port} ${protocol}"
    done
  fi
  if [ "${ENABLE_DHCP}" != "" ]; then
    killall udhcpc
    echo "MINKE:DHCP:DOWN ${IFACE} ${IP}"
  fi
  if [ "${ENABLE_MDNS}" != "" ] ; then
    killall avahi-daemon
    echo "MINKE:MDNS:DOWN"
  fi
}

trap "down; killall sleep; exit" TERM INT

up

echo "MINKE:UP"

while true; do
  sleep ${TTL2} &
  wait "$!"
  up
done
