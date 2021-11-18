#!/bin/bash

. config.sh

cluster=$(jq -r '.outputs.k8s_cluster_name.value' ../terraform/do/terraform.tfstate)
clusterid=$(jq -r '.outputs.k8s_cluster.value' ../terraform/do/terraform.tfstate)
region=$(jq -r '.outputs.k8s_region.value' ../terraform/do/terraform.tfstate)

echo "Removing cluster from ArgoCD"
echo " - Configuring port forwarding"
screen -S argocd-cluster -d -m bash -c "kubectl --kubeconfig $argokubeconfig port-forward svc/argocd-server -n argocd 8181:443"
chkfail $?
sleep 1

echo " - Logging in via CLI"
argocd login localhost:8181 --username $argocd_username --password "$argocd_password" --insecure
chkfail $?

echo " - Removing cluster"
argocd cluster rm do-${region}-${cluster}
#chkfail $?

echo " - Closing port forwarding"
screen -S argocd-cluster -X quit
#chkfail $?

echo ""
echo "Running teraform destroy"
cd ../terraform/do
terraform destroy
chkfail $?
