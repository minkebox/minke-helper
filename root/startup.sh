#! /bin/sh

RETRY=10 # 10 seconds
TTL=3600 # 1 hour
TTL2=1800 # TTL/2

# Wait for interfaces to become ready
for iface in ${__DEFAULT_INTERFACE} ${__DHCP_INTERFACE} ${__NAT_INTERFACE} ${__INTERNAL_INTERFACE}; do
  while ! ifconfig ${iface} > /dev/null 2>&1 ; do
    sleep 1;
  done
done

# Allocate an IP to the home interface via DHCP
if [ "${__DHCP_INTERFACE}" != "" ]; then
  udhcpc -i ${__DHCP_INTERFACE} -s /etc/udhcpc.script -F ${HOSTNAME} -x hostname:${HOSTNAME} -C -x 61:"'${HOSTNAME}'"
  ip=$(ip addr show dev ${__DHCP_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  echo "MINKE:DHCP:IP ${ip}"
  echo "MINKE:DHCP:UP ${__DHCP_INTERFACE}"
fi

# Report the default interface IP (may match the DHCP ip)
if [ "${__DEFAULT_INTERFACE}" != "" ]; then
  DEFAULT_IP=$(ip addr show dev ${__DEFAULT_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  echo "MINKE:DEFAULT:IP ${DEFAULT_IP}"
fi

# Default gateway
ip route add 0.0.0.0/1 dev ${__DEFAULT_INTERFACE}
ip route add 128.0.0.0/1 dev ${__DEFAULT_INTERFACE}

echo "127.0.0.1 localhost
::1	localhost ip6-localhost ip6-loopback
fe00::0	ip6-localnet
ff00::0	ip6-mcastprefix
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters" > /etc/hosts
if [ "${DEFAULT_IP}" != "" ]; then
  echo "${DEFAULT_IP} $(hostname)" >> /etc/hosts
fi
if [ "${__GATEWAY}" != "" ]; then
  echo "${__GATEWAY} minkebox" >> /etc/hosts
fi
echo "${__DNSSERVER} dns-server" >> /etc/hosts

echo "search ${__DOMAINNAME}. local.
nameserver ${__DNSSERVER}
options ndots:1 timeout:1 attempts:1 ndots:0" > /etc/resolv.conf

# We open any NAT ports.
if [ "${__NAT_INTERFACE}" != "" -a "${ENABLE_NAT}" != "" ]; then

  NAT_IP=$(ip addr show dev ${__NAT_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  if [ "${__DHCP_INTERFACE}" = "${__NAT_INTERFACE}" ]; then
    NAT_IP6=${__HOSTIP6}
  fi

  natup()
  {
    while true; do
      for map in ${ENABLE_NAT}; do
        # port:protocol
        port=${map%%:*}
        protocol=${map#*:}
        upnpc -e ${HOSTNAME} -m ${__NAT_INTERFACE} -n ${NAT_IP} ${port} ${port} ${protocol} ${TTL}
        if [ "${NAT_IP6}" != "" ]; then
          upnpc -e ${HOSTNAME}_6 -m ${__NAT_INTERFACE} -6 -A "" 0 ${NAT_IP6} ${port} ${protocol} ${TTL}
        fi
      done
      sleep ${TTL2} &
      wait "$!"
    done
  }
  natup &

fi

if [ "${FETCH_REMOTE_IP}" != "" ]; then

  remoteip()
  {
    while true; do
      timeout=${RETRY}
      iface_default_up=$(route | grep default | head -1 | grep ${FETCH_REMOTE_IP})
      if [ "${iface_default_up}" != "" ]; then
        remote_ip=$(wget -q -T 5 -O - http://api.ipify.org)
        if [ "${remote_ip}" != "" ]; then
          echo "MINKE:REMOTE:IP ${remote_ip}"
          timeout=${TTL2}
        fi
      fi
      sleep ${timeout} &
      wait "$!"
    done
  }
  remoteip &

fi

trap "killall sleep upnpc wget; exit" TERM INT

echo "MINKE:UP"

sleep 2147483647d &
wait "$!"
