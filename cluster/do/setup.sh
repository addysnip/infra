#!/bin/bash

. config.sh

function get_loadbalancer_ip() {
  clusterid=$1
  lb=$(doctl kubernetes cluster list-associated-resources $clusterid -o json | jq -r '.load_balancers[0].id')
  i=$(doctl compute load-balancer get $lb -o json | jq -r '.[0].ip')
  echo $i
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
echo "1-click installing ingress-nginx from Digital Ocean"
doctl kubernetes 1-click install $clusterid --1-clicks ingress-nginx
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

do_argocd=0

if [[ $do_argocd == "1" ]]; then
	echo ""
	echo "Adding to ArgoCD"
	echo " - Configuring port forwarding"
	screen -S argocd-cluster -d -m bash -c "kubectl --kubeconfig $argokubeconfig port-forward svc/argocd-server -n argocd 8181:443"
	chkfail $?
	sleep 2

	echo " - Logging in via CLI"
	argocd login localhost:8181 --username $argocd_username --password "$argocd_password" --insecure
	chkfail $?

	echo " - Adding cluster"
	argocd cluster add do-${region}-${cluster} --kubeconfig kubeconfig
	chkfail $?

	echo " - Closing port forwarding"
	screen -S argocd-cluster -X quit
	#chkfail $?
fi

echo ""
echo "Starting Certificate 'stuff'"
echo " - Cloudflare API Token Secret"
cat <<EOT |k apply -f -
apiVersion: external-secrets.io/v1alpha1
kind: ExternalSecret
metadata:
  name: cloudflare-apit-token
  namespace: cert-manager
spec:
  refreshInterval: 24h
  secretStoreRef:
    kind: ClusterSecretStore
    name: gcp-secretstore
  target:
    name: cloudflare-api-token-secret
    creationPolicy: Owner
  dataFrom:
  - key: cloudflare
EOT
echo " - ClusterIssuer (dns01)"
cat <<EOT |k apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: cloudflare-clusterissuer
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: privkey-cloudflare-secret
    solvers:
    - dns01:
        cloudflare:
          email: daniel@hawton.org
          apiKeySecretRef:
            name: cloudflare-api-token-secret
            key: api-token
EOT
echo " - ClusterIssuer (http01)"
cat <<EOT |k apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: addysnip-http01-issuer
spec:
  acme:
    privateKeySecretRef:
      name: issuer-private-key
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
    - http01:
        ingress:
          class: nginx
EOT

echo "- Install Redis cluster"
echo "  - Getting current Redis Password"
secret=redis
redis_versions=($(gcloud secrets versions list $secret |grep -v 'NAME' | awk '{ print $1 }'))
redis_password=$(gcloud secrets versions access ${redis_versions[0]} --secret $secret | jq -r '.REDIS_PASSWORD')

echo "  - Adding and updating Bitnami repo"
h repo add bitnami https://charts.bitnami.com/bitnami
h repo update

echo "  - Install"
k create ns redis
h install redis bitnami/redis --namespace redis --set auth.password=$redis_password --set sentinel.enabled=true --set sentinel.masterSet=master --set auth.sentinel=false

echo "Annotating ingress-nginx service"
echo "- Looking up load balancer IP"
lbip=$(get_loadbalancer_ip $clusterid)
echo "- Creating DNS entry"
lbhost=$(echo -n $lbip | od -A n -t x1 | sed 's/ //g')
doctl compute domain records create inf.addysnip.com --record-name $lbhost --record-type A --record-data $lbip --record-ttl 120
echo "- Adding annotations"
k annotate service ingress-nginx-controller -n ingress-nginx --overwrite service.beta.kubernetes.io/do-loadbalancer-hostname="${lbhost}.addysnip.com"
k annotate service ingress-nginx-controller -n ingress-nginx --overwrite service.beta.kubernetes.io/do-loadbalancer-name="${lbhost}.addysnip.com"
k annotate service ingress-nginx-controller -n ingress-nginx --overwrite service.beta.kubernetes.io/do-loadbalancer-enable-proxy-protocol="false"

echo ""
echo "Done."
