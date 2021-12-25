#! /bin/sh

ACTIVE=true
RETRY=10 # 10 seconds

#TTL=3600 # 1 hour
#TTL2=1800 # TTL/2

TTL=
TTL2=1d

date

# Wait for interfaces to become ready
for iface in ${__DEFAULT_INTERFACE} ${__DHCP_INTERFACE} ${__NAT_INTERFACE} ${__INTERNAL_INTERFACE} ${__SECONDARY_INTERFACE} ${__DNS_INTERFACE}; do
  while ! ifconfig ${iface} > /dev/null 2>&1 ; do
    sleep 1;
  done
done
NR_IFACES=$(ls -1d /sys/class/net/eth* | wc -l)

# Allocate an IP to the home interface via DHCP
if [ "${__DHCP_INTERFACE}" != "" ]; then
  # Reset mac addess is nececessary. We may need to do this if the interface is secondary.
  if [ "${__DHCP_INTERFACE_MAC}" != "" ]; then
    ip link set dev ${__DHCP_INTERFACE} address ${__DHCP_INTERFACE_MAC}
  fi
  udhcpc -i ${__DHCP_INTERFACE} -s /etc/udhcpc.script -F ${HOSTNAME} -x hostname:${HOSTNAME}
  ip=$(ip addr show dev ${__DHCP_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  echo "MINKE:DHCP:IP ${ip}"
  echo "MINKE:DHCP:UP ${__DHCP_INTERFACE}"
fi

# Report the default interface IP (may match the DHCP ip)
if [ "${__DEFAULT_INTERFACE}" != "" ]; then
  if [ "${__DEFAULT_INTERFACE_IP}" != "" ]; then
    ip addr flush dev ${__DEFAULT_INTERFACE}
    ip addr add ${__DEFAULT_INTERFACE_IP} broadcast + dev ${__DEFAULT_INTERFACE}
    echo "MINKE:STATIC:IP $(echo ${__DEFAULT_INTERFACE_IP} | sed s:/.*::)"
    echo "MINKE:STATIC:UP ${__DEFAULT_INTERFACE}"
  fi
  DEFAULT_IP=$(ip addr show dev ${__DEFAULT_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  echo "MINKE:DEFAULT:IP ${DEFAULT_IP}"
fi

# Report the secondary interface IP (may match the DHCP ip)
if [ "${__SECONDARY_INTERFACE}" != "" ]; then
  SECONDARY_IP=$(ip addr show dev ${__SECONDARY_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  echo "MINKE:SECONDARY:IP ${SECONDARY_IP}"
fi

# Default gateway
if [ "${__GATEWAY}" != "" ]; then
  ip route add 0.0.0.0/1 via ${__GATEWAY}
  ip route add 128.0.0.0/1 via ${__GATEWAY}
fi

cp /etc/hosts /etc/hosts.orig
if [ "${DEFAULT_IP}" != "" ]; then
  awk "!/$(hostname)/ || /127.0.0.1/" /etc/hosts.orig > /etc/hosts
  echo "${DEFAULT_IP} $(hostname)" >> /etc/hosts
else
  cat /etc/hosts.orig > /etc/hosts
fi
if [ "${__GATEWAY}" != "" ]; then
  echo "${__GATEWAY} ${__MINKENAME}-gateway" >> /etc/hosts
fi
echo "${__DNSSERVER} ${__MINKENAME}" >> /etc/hosts

echo "search ${__DOMAINNAME} local
nameserver ${__DNSSERVER}
options ndots:1 timeout:2 attempts:1" > /etc/resolv.conf

# Network monitoring
/sbin/iptables -N RX
/sbin/iptables -N TX
/sbin/iptables -I RX
/sbin/iptables -I TX
# Single interface
if [ "${NR_IFACES}" = "1" ]; then
  /sbin/iptables -I OUTPUT -j TX
  /sbin/iptables -I INPUT -j RX
fi
# Applications which want to monitor traffic over multiple networks are more problematic as we don't know
# what is tx or rx traffic. Let them setup the specifics themselves

# Bandwidth control
if [ "${__DEFAULT_INTERFACE_BANDWIDTH}" != "" ]; then
  /wondershaper.sh -a ${__DEFAULT_INTERFACE} -u ${__DEFAULT_INTERFACE_BANDWIDTH} -d ${__DEFAULT_INTERFACE_BANDWIDTH}
fi
if [ "${__SECONDARY_INTERFACE_BANDWIDTH}" != "" ]; then
  /wondershaper.sh -a ${__SECONDARY_INTERFACE} -u ${__SECONDARY_INTERFACE_BANDWIDTH} -d ${__SECONDARY_INTERFACE_BANDWIDTH}
fi

# Monitor network changes
if [ "${__DEFAULT_INTERFACE}" != "" ]; then
  flags="/sys/class/net/${__DEFAULT_INTERFACE}/flags"
  echo "MINKE:DEFAULT:FLAGS $(cat ${flags})"
  (ip monitor link dev ${__DEFAULT_INTERFACE} | while read line; do
    echo "MINKE:DEFAULT:FLAGS $(cat ${flags})"
  done) &
fi

# We open any NAT ports.
if [ "${__NAT_INTERFACE}" != "" -a "${ENABLE_NAT}" != "" ]; then

  NAT_IP=$(ip addr show dev ${__NAT_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  if [ "${__DHCP_INTERFACE}" = "${__NAT_INTERFACE}" ]; then
    NAT_IP6=${__HOSTIP6}
  fi

  # We dont use the NAT_INTERFACE when forwarding ports because in some circumstances the relevant interface
  # is changed by the app (e.g. VPN's might setup a bridge). Just let upnpc work it out.
  natup()
  {
    date
    while ${ACTIVE}; do
      for map in ${ENABLE_NAT}; do
        # port:protocol
        port=${map%%:*}
        protocol=${map#*:}
        upnpc -e ${HOSTNAME} -a ${NAT_IP} ${port} ${port} ${protocol} ${TTL}
        if [ "${NAT_IP6}" != "" ]; then
          upnpc -e ${HOSTNAME}_6 -6 -a ${NAT_IP6} ${port} ${port} ${protocol} ${TTL}
        fi
      done
      sleep ${TTL2} &
      wait "$!"
    done
    for map in ${ENABLE_NAT}; do
      # port:protocol
      port=${map%%:*}
      protocol=${map#*:}
      upnpc -d ${port} ${protocol}
      if [ "${NAT_IP6}" != "" ]; then
        upnpc -6 -d ${port} ${protocol}
      fi
    done
  }
  natup &

fi

if [ "${FETCH_REMOTE_IP}" != "" ]; then

  remoteip()
  {
    date
    while ${ACTIVE}; do
      timeout=${RETRY}
      remote_ip=$(wget -q -T 5 -O - http://api.ipify.org)
      if [ "${remote_ip}" != "" ]; then
        echo "MINKE:REMOTE:IP ${remote_ip}"
        timeout=${TTL2}
      fi
      sleep ${timeout} &
      wait "$!"
    done
  }
  remoteip &

fi

trap "ACTIVE=false; killall ip sleep;" TERM INT

echo "MINKE:UP"

sleep 2147483647d &
wait "$!"
