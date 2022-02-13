#!/bin/bash

kubeconfig=$1
name=$2

cat <<EOF | kubectl apply -f -
apiVersion: provisioning.cattle.io/v1
kind: Cluster
metadata:
  name: $name
  annotations: {}
  labels: {}
  namespace: fleet-default
spec: {}
EOF

echo "Waiting for cluster registration"
while true; do
    kubectl --kubeconfig $kubeconfig get cluster.provisioning.cattle.io/$name -n fleet-default -o json | jq -r .status.clusterName &>/dev/null
    if [[ $? == 0 ]]; then
        break
    fi
    sleep 1
done

clusterName=$(kubectl --kubeconfig $kubeconfig get cluster.provisioning.cattle.io/$name -n fleet-default -o json | jq -r .status.clusterName)

echo "Waiting for registration token generation"
while true; do
    kubectl --kubeconfig $kubeconfig get clusterregistrationtokens.management.cattle.io -n $clusterName default-token -o json | jq -r .status.command &>/dev/null
    if [[ $? == 0 ]]; then
        break
    fi
    sleep 1
done

manifestUrl=$(kubectl --kubeconfig $kubeconfig get clusterregistrationtokens.management.cattle.io -n $clusterName default-token -o json | jq -r .status.command)

echo "Apply $manifestUrl"