#!/bin/bash
. ../../common.sh

rancher_server=$(cat ../../private.json | jq -r '.rancher.server')
rancher_token=$(cat ../../private.json | jq -r '.rancher.token')
clustername=$(cat .name)

echo "- Removing from Rancher and Fleet"
curl -X DELETE -H "Authorization: Bearer $rancher_token" $rancher_server/v1/provisioning.cattle.io.clusters/fleet-default/$clustername

clusterid=$(terraform output -raw k8s_cluster)
rm ~/.kube/config-files/$clustername.yaml

echo "- Removing database firewall rule"
uuids=($(doctl databases firewalls list 92f2d81c-446f-4f0e-8443-97919c2a9a5c | grep $clusterid | awk '{print $1}') )

echo "- Deleting loadbalancer DNS record"
lbip=$(get_loadbalancer_ip $clusterid)
dnsid=($(doctl compute domain records list inf.addysnip.com | grep $lbip | awk '{print $1}') )
for d in "${dnsid[@]}"; do
    doctl compute domain records delete inf.addysnip.com $d
done

for uuid in "${uuids[@]}"; do
    doctl databases firewalls remove 92f2d81c-446f-4f0e-8443-97919c2a9a5c --uuid $uuid
done

echo "- Deleting cluster and associated resources"
doctl kubernetes cluster delete $clusterid --dangerous