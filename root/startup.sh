#! /bin/sh

TTL=3600 # 1 hour
TTL2=1800 # TTL/2

# Wait for interfaces to become ready
if [ "${__HOME_INTERFACE}" != "" ]; then
  while ! ifconfig ${__HOME_INTERFACE} > /dev/null 2>&1 ; do
    sleep 1;
  done
fi
if [ "${__PRIVATE_INTERFACE}" != "" ]; then
  while ! ifconfig ${__PRIVATE_INTERFACE} > /dev/null 2>&1 ; do
    sleep 1;
  done
fi

# Allocate an IP to the home interface via DHCP
if [ "${__HOME_INTERFACE}" != "" -a "${ENABLE_DHCP}" != "" ]; then
  udhcpc -i ${__HOME_INTERFACE} -s /etc/udhcpc.script -F ${HOSTNAME} -x hostname:${HOSTNAME} -C -x 61:"'${HOSTNAME}'"
  echo "MINKE:DHCP:UP ${__HOME_INTERFACE}"
fi

# Set the private interface by hand (it probably already has this address)
if [ "${__PRIVATE_INTERFACE}" != "" -a "${__PRIVATE_INTERFACE_IP}" != "" ]; then
  ip addr add ${__PRIVATE_INTERFACE_IP} dev ${__PRIVATE_INTERFACE}
fi

# Report the allocated addresses back to the system
if [ "${__PRIVATE_INTERFACE}" != "" ]; then
  PIP=$(ip addr show dev ${__PRIVATE_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  echo "MINKE:PRIVATE:IP ${PIP}"
fi
if [ "${__HOME_INTERFACE}" != "" ]; then
  HIP=$(ip addr show dev ${__HOME_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  echo "MINKE:HOME:IP ${HIP}"
fi

# The primary interface is eth0. It may be the home network or the private network depending on how
# the app is configured. We open any NAT ports on the primary interface.
PRIMARY_INTERFACE=eth0
if [ "${__HOME_INTERFACE}" = "${PRIMARY_INTERFACE}" ]; then
  PRIMARY_IP=${HIP}
elif [ "${__PRIVATE_INTERFACE}" = "${PRIMARY_INTERFACE}" ]; then
  PRIMARY_IP=${PIP}
else
  PRIMARY_IP="127.0.0.1"
fi
PRIMARY_IP6=${__HOSTIP6}

if [ "${__GATEWAY}" != "" ]; then
  route add -net default gw ${__GATEWAY}
fi

echo "127.0.0.1 localhost
::1	localhost ip6-localhost ip6-loopback
fe00::0	ip6-localnet
ff00::0	ip6-mcastprefix
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters
${PRIMARY_IP} $(hostname)
${__DNSSERVER} dns-server" > /etc/hosts
if [ "${__GATEWAY}" != "" ]; then
  echo "${__GATEWAY} services" >> /etc/hosts
fi

echo "search ${__DOMAINNAME}. local.
nameserver ${__DNSSERVER}
options ndots:1 timeout:1 attempts:1 ndots:0" > /etc/resolv.conf

up()
{
  if [ "${ENABLE_NAT}" != "" ]; then
    for map in ${ENABLE_NAT}; do
      # port:protocol
      port=${map%%:*}
      protocol=${map#*:}
      upnpc -u ${__UPNPURL} -e ${HOSTNAME} -m ${PRIMARY_INTERFACE} -n ${PRIMARY_IP} ${port} ${port} ${protocol} ${TTL}
      if [ "${PRIMARY_IP6}" != "" ]; then
        upnpc -u ${__UPNPURL} -e ${HOSTNAME}_6 -m ${PRIMARY_INTERFACE} -6 -A "" 0 ${PRIMARY_IP6} ${port} ${protocol} ${TTL}
      fi
      echo "MINKE:NAT:UP ${PRIMARY_IP} ${port} ${protocol} ${TTL}"
    done
  fi
}

reup()
{
  if [ "${ENABLE_NAT}" != "" ]; then
    for map in ${ENABLE_NAT}; do
      # port:protocol
      port=${map%%:*}
      protocol=${map#*:}
      upnpc -u ${__UPNPURL} -e ${HOSTNAME} -m ${PRIMARY_INTERFACE} -n ${PRIMARY_IP} ${port} ${port} ${protocol} ${TTL}
      if [ "${PRIMARY_IP6}" != "" ]; then
        upnpc -u ${__UPNPURL} -e ${HOSTNAME}_6 -m ${PRIMARY_INTERFACE} -6 -A "" 0 ${PRIMARY_IP6} ${port} ${protocol} ${TTL}
      fi
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
      upnpc -u ${__UPNPURL} -m ${PRIMARY_INTERFACE} -d ${port} ${protocol}
      echo "MINKE:NAT:DOWN ${PRIMARY_IP} ${port} ${protocol}"
    done
  fi
  if [ "${__HOME_INTERFACE}" != "" -a "${ENABLE_DHCP}" != "" ]; then
    killall udhcpc
    echo "MINKE:DHCP:DOWN ${__HOME_INTERFACE} ${HIP}"
  fi
  echo "MINKE:DOWN"
}

trap "down; killall sleep; exit" TERM INT

up

echo "MINKE:UP"

if [ "${ENABLE_NAT}" != "" ]; then
  while true; do
    sleep ${TTL2} &
    wait "$!"
    reup
  done
else
  sleep 2147483647d &
  wait "$!"
fi
