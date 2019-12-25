#! /bin/sh

if [ "${ENABLE_DHCP}" != "" -a "$(pidof udhcpc)" = "" ]; then
  exit 1
fi

if [ "$(pidof sleep)" = "" ]; then
  exit 1
fi

exit 0
