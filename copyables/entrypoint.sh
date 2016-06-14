#!/bin/bash
set -e

if [ "$*" == "gencert" ]; then

  /gencert.sh
  exit 0

fi

if [ ! -f /opt/vpn_server.config ]; then

: ${PSK:='notasecret'}
: ${USERNAME:=user$(cat /dev/urandom | tr -dc '0-9' | fold -w 4 | head -n 1)}

printf '# '
printf '=%.0s' {1..24}
echo
echo \# ${USERNAME}

if [[ $PASSWORD ]]
then
  echo '# <use the password specified at -e PASSWORD>'
else
  PASSWORD=$(cat /dev/urandom | tr -dc '0-9' | fold -w 20 | head -n 1 | sed 's/.\{4\}/&./g;s/.$//;')
  echo \# ${PASSWORD}
fi

printf '# '
printf '=%.0s' {1..24}
echo

/opt/vpnserver start 2>&1 > /dev/null

# while-loop to wait until server comes up
# switch cipher
while : ; do
  set +e
  /opt/vpncmd localhost /SERVER /CSV /CMD ServerCipherSet DHE-RSA-AES256-SHA 2>&1 > /dev/null
  [[ $? -eq 0 ]] && break
  set -e
  sleep 1
done

# About command to grab version number
/opt/vpncmd localhost /SERVER /CSV /CMD About | head -2 | tail -1 | sed 's/^/# /;'

if [ -z ${L2TP_ENABLED+x} ]
then
  echo "# >>> L2TP_IPsec module disabled <<<"
  /opt/vpncmd localhost /SERVER /CSV /CMD IPsecEnable no /L2TP:no /L2TPRAW:no /ETHERIP:no /DEFAULTHUB:DEFAULT
else
  echo "# >>> L2TP_IPsec module enabled <<<"
  /opt/vpncmd localhost /SERVER /CSV /CMD IPsecEnable /L2TP:yes /L2TPRAW:yes /ETHERIP:no /PSK:${PSK} /DEFAULTHUB:DEFAULT
fi

if [ -z ${OPENVPN_ENABLED+x} ]
then
  echo "# >>> OpenVPN module disabled <<<"
  /opt/vpncmd localhost /SERVER /CSV /CMD OpenVpnEnable no /PORTS:1194
else
  echo "# >>> OpenVPN module enabled <<<"
  /opt/vpncmd localhost /SERVER /CSV /CMD OpenVpnEnable yes /PORTS:1194
fi

if [ -z ${SSTP_ENABLED+x} ]
then
  echo "# >>> SSTP module disabled <<<"
  /opt/vpncmd localhost /SERVER /CSV /CMD SstpEnable no
else
  echo "# >>> SSTP module enabled <<<"
  /opt/vpncmd localhost /SERVER /CSV /CMD SstpEnable yes
fi

# enable SecureNAT
/opt/vpncmd localhost /SERVER /CSV /HUB:DEFAULT /CMD SecureNatEnable

if [[ "*${CERT}*" != "**" && "*${KEY}*" != "**" ]]; then
  # server cert/key pair specified via -e
  CERT=$(echo ${CERT} | sed -r 's/\-{5}[^\-]+\-{5}//g;s/[^A-Za-z0-9\+\/\=]//g;')
  echo -----BEGIN CERTIFICATE----- > server.crt
  echo ${CERT} | fold -w 64 >> server.crt
  echo -----END CERTIFICATE----- >> server.crt

  KEY=$(echo ${KEY} | sed -r 's/\-{5}[^\-]+\-{5}//g;s/[^A-Za-z0-9\+\/\=]//g;')
  echo -----BEGIN PRIVATE KEY----- > server.key
  echo ${KEY} | fold -w 64 >> server.key
  echo -----END PRIVATE KEY----- >> server.key

  /opt/vpncmd localhost /SERVER /CSV /CMD ServerCertSet /LOADCERT:server.crt /LOADKEY:server.key
  rm server.crt server.key
  export KEY='**'
fi

/opt/vpncmd localhost /SERVER /CSV /CMD OpenVpnMakeConfig openvpn.zip 2>&1 > /dev/null

# extract .ovpn config
unzip -p openvpn.zip *_l3.ovpn > softether.ovpn
# delete "#" comments, \r, and empty lines
sed -i '/^#/d;s/\r//;/^$/d' softether.ovpn
# send to stdout
cat softether.ovpn

# disable extra logs
/opt/vpncmd localhost /SERVER /CSV /HUB:DEFAULT /CMD LogDisable packet
/opt/vpncmd localhost /SERVER /CSV /HUB:DEFAULT /CMD LogDisable security

# add user
/opt/vpncmd localhost /SERVER /HUB:DEFAULT /CSV /CMD UserCreate ${USERNAME} /GROUP:none /REALNAME:none /NOTE:none
/opt/vpncmd localhost /SERVER /HUB:DEFAULT /CSV /CMD UserPasswordSet ${USERNAME} /PASSWORD:${PASSWORD}

export PASSWORD='**'

# set password for hub
: ${HUB_PWD:=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 16 | head -n 1)}
/opt/vpncmd localhost /SERVER /HUB:DEFAULT /CSV /CMD SetHubPassword ${HUB_PWD}

# set password for server
: ${SERVER_PWD:=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 20 | head -n 1)}
/opt/vpncmd localhost /SERVER /CSV /CMD ServerPasswordSet ${SERVER_PWD}

/opt/vpnserver stop 2>&1 > /dev/null

# while-loop to wait until server goes away
set +e
while pgrep vpnserver > /dev/null; do sleep 1; done
set -e

echo \# [initial setup OK]

fi

exec "$@"

