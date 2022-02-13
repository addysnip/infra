#!/bin/bash

function h {
    helm --kubeconfig kubeconfig $*
}

function k {
    kubectl --kubeconfig kubeconfig $*
}

function get_loadbalancer_ip() {
  clusterid=$1
  lb=$(doctl kubernetes cluster list-associated-resources $clusterid -o json | jq -r '.load_balancers[0].id')
  i=$(doctl compute load-balancer get $lb -o json | jq -r '.[0].ip')
  if [[ $? -ne 0 ]]; then
    echo "null"
  else
    echo $i
  fi
}