#!/bin/bash

clusterid=$1

if [ -z $clusterid ]; then
  clusterid="addysnip-tor1-prod"
fi

function chkfail() {
  if [ $? -ne 0 ]; then
    echo "Failed"
    exit 1
  fi
}

echo "Checking for $clusterid"
echo "Getting load balancer id"
loadbalancerid=$(doctl kubernetes cluster list-associated-resources $clusterid -o json | jq -r '.load_balancers[0].id')
chkfail $?
if [ -z $loadbalancerid ] || [ $loadbalancerid == 'null' ]; then
  echo "No load balancer found"
  exit 1
fi

echo "Getting load balancer ip"
loadbalancer=$(doctl compute load-balancer get $loadbalancerid -o json | jq -r '.[0].ip')
chkfail $?
if [ -z $loadbalancer ] || [ $loadbalancer == 'null' ]; then
  echo "No load balancer ip found"
  exit 1
fi

echo ""
echo "Generating haproxy config"
cat <<EOF >playbooks/haproxy/haproxy.cfg
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Default SSL material locations
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

    # See: https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5s
    timeout client  50000
    timeout server  50000

frontend http
    bind :80
    mode tcp
    default_backend http

frontend https
    bind :443
    mode tcp
    default_backend https

backend http
    server $loadbalancerid ${loadbalancer}:80

backend https
    server $loadbalancerid ${loadbalancer}:443
EOF