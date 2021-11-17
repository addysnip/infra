#!/bin/bash

# provides: argocd_username and argocd_password for the cli operations
. $HOME/.config/argocd/creds.sh

# GCP Project ID
projectid="addysnip"

# ArgoCD main-cluster kubeconfig
argokubeconfig=$HOME/.config/argocd/kubeconfig.yaml

function h {
    helm --kubeconfig kubeconfig $*
}

function k {
    kubectl --kubeconfig kubeconfig $*
}

function chkfail {
    if [ $1 -ne 0 ]; then
        echo "Failed"
        exit 1
    fi
}

echo "Running the terraform works"
cd ../terraform/do
terraform init
chkfail $?

terraform apply
chkfail $?
cd ../../do
cluster=$(jq -r '.outputs.k8s_cluster_name.value' ../terraform/do/terraform.tfstate)
clusterid=$(jq -r '.outputs.k8s_cluster.value' ../terraform/do/terraform.tfstate)
region=$(jq -r '.outputs.k8s_region.value' ../terraform/do/terraform.tfstate)
projectid="addysnip"
serviceaccountjson=$(cat ~/.config/gcloud/.secretmanagerserviceaccount | base64 -w 0)

echo ""
echo "Adding new cluster to database firewall"
doctl databases firewalls append 92f2d81c-446f-4f0e-8443-97919c2a9a5c --rule k8s:$clusterid
chkfail $?

echo ""
echo "Getting kubeconfig"
doctl kubernetes cluster kubeconfig show $cluster > kubeconfig
chmod 600 kubeconfig
chkfail $?

echo ""
echo "Adding helm repo"
h repo add external-secrets https://charts.external-secrets.io
chkfail $?

echo ""
echo "Installing external secrets"
h upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --set installCRDs=true
chkfail $?

echo ""
echo "Waiting for rollout to complete"
k rollout status deployment/external-secrets -n external-secrets
chkfail $?

echo ""
echo "Creating needed YAMLs"
cat <<EOT >secret-creds.yaml
apiVersion: v1
kind: Secret
metadata:
  name: gcpsm-secret
  namespace: external-secrets
  labels:
    type: gcpsm
type: Opaque
data:
  secret-access-credentials: $serviceaccountjson
EOT

k apply -f secret-creds.yaml
chkfail $?

rm secret-creds.yaml

cat <<EOT >secretstore.yaml
apiVersion: external-secrets.io/v1alpha1
kind: ClusterSecretStore
metadata:
  name: gcp-secretstore
spec:
  provider:
    gcpsm:
      projectID: $projectid
      auth:
        secretRef:
          secretAccessKeySecretRef:
            name: gcpsm-secret
            key: secret-access-credentials
            namespace: external-secrets
EOT

k apply -f secretstore.yaml
chkfail $?

rm secretstore.yaml

echo ""
echo "Adding to ArgoCD"
echo " - Configuring port forwarding"
screen -S argocd-cluster -d -m bash -c "kubectl --kubeconfig $argokubeconfig port-forward svc/argocd-server -n argocd 8181:443"
chkfail $?
sleep 1

echo " - Logging in via CLI"
argocd login localhost:8181 --username $argocd_username --password "$argocd_password" --insecure
chkfail $?

echo " - Adding cluster"
argocd cluster add do-${region}-${cluster} --kubeconfig kubeconfig
chkfail $?

echo " - Closing port forwarding"
screen -S argocd-cluster -X quit
chkfail $?

echo ""
echo "Done."
