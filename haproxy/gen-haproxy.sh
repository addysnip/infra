#!/bin/bash

prodhaproxy=$1
if [[ $prodhaproxy == "" ]]; then
  prodhaproxy=0
fi

dropletid=$(jq -r '.outputs.id.value' terraform/terraform.tfstate)
dropletip=$(jq -r '.outputs.ip.value' terraform/terraform.tfstate)

if [ -z $clusterid ]; then
  clusterid="addysnip-tor1-prod"
fi

function chkfail() {
  if [ $? -ne 0 ]; then
    echo "Failed"
    if [ $1 -ne 0 ]; then
      exit $1
    fi
  fi
}

function _unassign() {
  doctl compute floating-ip-action unassign $1
}

function _assign() {
  doctl compute floating-ip-action assign $1 $2
  if [ $? != 0 ]; then
    echo " ++ Exit code $?, waiting and trying again..."
    sleep 10
    _assign $1 $2
  fi
}

function reassign() {
  echo " - Unassigning"
  _unassign $1
  echo " - Assigning"
  _assign $1 $2
}

function get_clusters() {
  echo $(python3 tools/get-clusters.py)
}

function get_loadbalancer_ip() {
  clusterid=$1
  local -n a=$2
  lb=$(doctl kubernetes cluster list-associated-resources $clusterid -o json | jq -r '.load_balancers[0].id')
  i=$(doctl compute load-balancer get $lb -o json | jq -r '.[0].ip')
  a+=($i)
}

echo "Getting cluster list"
clusters=$(get_clusters)
echo $clusters
echo "Parsing cluster list"
readarray -t dev < <(echo $clusters | jq -r '.dev[]')
readarray -t prod < <(echo $clusters | jq -r ".prod[]")

devips=()
prodips=()

echo "Getting development cluster load balancers"
for devcluster in "${dev[@]}"; do
  get_loadbalancer_ip $devcluster devips
done

echo "Getting production cluster load balancers"
for prodcluster in "${prod[@]}"; do
  get_loadbalancer_ip $prodcluster prodips
done

ips=("${devips[@]}")
if [[ $prodhaproxy == "1" ]]; then
  ips=("${prodips[@]}")
fi

#echo "Updating floating ip $prodfloatingip"
#reassign $prodfloatingip $dropletid

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
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  50000
    timeout server  50000
EOF

## Dev cluster
cat <<EOF >>playbooks/haproxy/haproxy.cfg
frontend http
    bind ${dropletip}:80
    mode tcp
    option tcplog
    default_backend http-be

frontend https
    bind ${dropletip}:443
    mode tcp
    option tcplog
    default_backend https-be

backend http-be
    mode tcp
EOF

for ip in "${ips[@]}"; do
    echo "    server $ip ${ip}:80" >>playbooks/haproxy/haproxy.cfg
done

cat <<EOF >>playbooks/haproxy/haproxy.cfg

backend https-be
    mode tcp
EOF
for ip in "${ips[@]}"; do
    echo "    server $ip ${ip}:80" >>playbooks/haproxy/haproxy.cfg
done
