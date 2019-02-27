#! /bin/sh

if [ "${__HOME_INTERFACE}" != "" ]; then
  IFACE=${__HOME_INTERFACE}
elif [ "${__PRIVATE_INTERFACE}" != "" ]; then
  IFACE=${__PRIVATE_INTERFACE}
fi

TTL=3600 # 1 hour
TTL2=1800 # TTL/2

while ! ifconfig ${IFACE} > /dev/null 2>&1 ; do 
  sleep 1;
done

if [ "${ENABLE_DHCP}" != "" ]; then
  udhcpc -i ${IFACE} -s /etc/udhcpc.script -F ${HOSTNAME} -x hostname:${HOSTNAME} -C -x 61:"'${HOSTNAME}'"
  echo "MINKE:DHCP:UP ${IFACE}"
fi

IP=$(ip addr show dev ${IFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
if [ "${__HOME_INTERFACE}" != "" ]; then
  echo "MINKE:HOME:IP ${IP}"
elif [ "${__PRIVATE_INTERFACE}" != "" ]; then
  echo "MINKE:PRIVATE:IP ${IP}"
fi

if [ "${__GATEWAY}" != "" ]; then
  route add -net default gw ${__GATEWAY}
fi

if [ "${ENABLE_MDNS}" != "" ] ; then
  cat > /etc/avahi/services/helper.service <<__EOF__
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
__EOF__
  for map in ${ENABLE_MDNS}; do
    type=${map%%:*}
    map3=${map#*:}
    port=${map3%%:*}
    txt=${map3#*:}
    if [ "${port}" = "${txt}" ]; then
      txt=""
    else
      txt=$(echo ${txt} | sed "s/%20/ /g")
    fi
    echo "  <service><type>${type}</type><port>${port}</port>${txt}</service>" >> /etc/avahi/services/helper.service
  done
  echo "</service-group>" >> /etc/avahi/services/helper.service
  echo "
[server]
enable-dbus=no
allow-interfaces=${IFACE}
" > /etc/avahi/avahi-daemon.conf
  /usr/sbin/avahi-daemon --no-drop-root -D
  echo "MINKE:MDNS:UP"
fi

echo "127.0.0.1 localhost
::1	localhost ip6-localhost ip6-loopback
fe00::0	ip6-localnet
ff00::0	ip6-mcastprefix
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters
${IP} $(hostname)
${__DNSSERVER} dns-server" > /etc/hosts
if [ "${__GATEWAY}" != "" ]; then
  echo "${__GATEWAY} SERVICES" >> /etc/hosts
fi

up()
{
  if [ "${ENABLE_NAT}" != "" ]; then
    for map in ${ENABLE_NAT}; do
      # port:protocol
      port=${map%%:*}
      protocol=${map#*:}
      upnpc -m ${IFACE} -a ${IP} ${port} ${port} ${protocol} ${TTL}
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
      upnpc -m ${IFACE} -d ${port} ${protocol}
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
  echo "MINKE:DOWN"
}

trap "down; killall sleep; exit" TERM INT

up

echo "MINKE:UP"

while true; do
  sleep ${TTL2} &
  wait "$!"
  up
done