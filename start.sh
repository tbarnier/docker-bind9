#!/bin/bash

if [[ ! -f /etc/bind/.stamp_installed/ok ]]; then
  if [[ -z "${BIND9_ROOTDOMAIN}" ]];then
    echo "The variable BIND9_ROOTDOMAIN must be set"
    exit 1
  fi
  if [[ -z "${BIND9_KEYNAME}" ]];then
    echo "The variable BIND9_KEYNAME must be set"
    exit 1
  fi
  if [[ -z "${BIND9_KEY}" ]];then
    echo "The variable BIND9_KEY must be set"
    exit 1
  fi
  if [[ -z "${BIND9_IP}" ]];then
    if [[ "${RANCHER_ENV}" == "true" ]]; then
      BIND9_IP=`curl rancher-metadata/latest/self/host/agent_ip`
      if [[ "$?" != "0" ]] || [[ "$BIND9_IP" == "" ]]; then
        echo "Unable to get host ip" && exit 1
      fi
    else
      echo "The variable BIND9_IP must be set" && exit 1
    fi
  fi
  echo "Creating key configuration"
  cat <<EOF > /etc/bind/tsig.key
key "${BIND9_KEYNAME}" {
  algorithm hmac-md5;
  secret "${BIND9_KEY}";
};
EOF
  echo "Creating named configuration"
  cat <<EOF > /etc/bind/named.conf.local
include "/etc/bind/tsig.key";
zone "${BIND9_ROOTDOMAIN}" {
       type master;
       file "/etc/bind/zones/db.${BIND9_ROOTDOMAIN}";
       allow-update { key "${BIND9_KEYNAME}"; } ;
};
EOF
  echo "Creating ${BIND9_ROOTDOMAIN} configuration"
  cat <<EOF >> "/etc/bind/zones/db.${BIND9_ROOTDOMAIN}"
@		IN SOA	ns.${BIND9_ROOTDOMAIN}. root.${BIND9_ROOTDOMAIN}. (
				${BIND9_SOA_SERIAL}   ; serial
				${BIND9_SOA_REFRESH}     ; refresh
				${BIND9_SOA_RETRY}      ; retry
				${BIND9_SOA_EXPIRE}    ; expire
				${BIND9_SOA_NEGATIVE_TTL}     ; negative ttl
				)
			NS	ns.${BIND9_ROOTDOMAIN}.
ns			A	${BIND9_IP}
EOF
  echo "Creating named.conf.options configuration"
  if [[ -z "${BIND9_FORWARDERS}" ]];then
    forwarders=""
  else
    fowarders="forwarders {$BIND9_FORWARDERS};"
  fi

  if [[ -z "${BIND9_ALSO_NOTIFY}" ]];then
    also_notify=""
  else
    also_notify="also-notify {${BIND9_ALSO_NOTIFY};};"
    echo "@			NS	ns2.${BIND9_ROOTDOMAIN}." >> "/etc/bind/zones/db.${BIND9_ROOTDOMAIN}"
    echo "ns2			A	${BIND9_ALSO_NOTIFY}" >> "/etc/bind/zones/db.${BIND9_ROOTDOMAIN}"
  fi

  cat <<EOF > "/etc/bind/named.conf.options"
options {
	directory "/var/cache/bind";
        allow-recursion {any;};
        allow-query-cache {any;};
        allow-query {any;};
        recursion yes;
	${fowarders}
	${also_notify}
	dnssec-enable yes;
	dnssec-validation yes;

	auth-nxdomain no;    # conform to RFC1035
	//listen-on-v6 { any; };
};
EOF

  chown -R bind:bind /etc/bind/zones/
  mkdir /etc/bind/.stamp_installed
  touch /etc/bind/.stamp_installed/ok
fi

ipv4=""
if [[ ! -z "${BIND9_IPV4ONLY}" ]];then
  ipv4="-4"
fi

named $ipv4 -g -c /etc/bind/named.conf -u bind
