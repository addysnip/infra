#!/bin/bash

set -e

. common.sh

########################### Config
# GCP Project ID
projectid="addysnip"
# Path to the JSON for the secret manager service account
serviceaccountjson_path="$HOME/.config/gcloud/.secretmanagerserviceaccount"
# Redis Secret Name
redis_secret="redis"
rancher_kubeconfig="$HOME/.kube/config-files/lvr.yaml"
########################### End Config

name=$1
region=$2
version=$3
env=$4

rancher_server=$(cat private.json | jq -r '.rancher.server')
rancher_token=$(cat private.json | jq -r '.rancher.token')

if [[ -z "$env" ]]; then
    echo "Usage: $0 <name> <region> <version> <env>"
    exit 1
fi

if [[ "$version" == "latest" ]]; then
    version=$(doctl kubernetes options versions -o json | jq -r '.[0].slug')
fi

if [[ $env != "prod" && $env != "dev" ]]; then
    echo "Invalid environment: $env"
    exit 1
fi

if [[ ! -f "$serviceaccountjson_path" ]]; then
    echo "Service account JSON not found at $serviceaccountjson_path"
    exit 1
fi

if [[ -z "$rancher_server" ]]; then
    echo "Rancher server not configured in private.json"
    exit 1
fi

if [[ -z "$rancher_token" ]]; then
    echo "Rancher token not configured in private.json"
    exit 1
fi


targetdir="data/$name.$env.$region"
mydir="$(pwd)"

if [[ -d "$targetdir" && $OVERRIDE != "1" ]]; then
    echo "Directory $targetdir already exists"
    exit 1
fi

cp -Rp terraform $targetdir
cd $targetdir

echo "- Appending variables_override.tf"
cat <<EOT >>variables_override.tf
variable "cluster_name" {
    default = "$name-$region-$env"
}

variable "tags" {
    default = ["addysnip","$region","$env"]
}

variable "k8s_version" {
    default = "$version"
}
EOT

echo "- Terraform init"
terraform init

echo "- Terraform apply"
terraform apply -auto-approve

echo "- Gathering some data"
clustername=$(terraform output -raw k8s_cluster_name)
clusterid=$(terraform output -raw k8s_cluster)
serviceaccountjson=$(cat $serviceaccountjson_path | base64 -w 0)

echo "- Adding cluster to database firewall"
doctl databases firewalls append 92f2d81c-446f-4f0e-8443-97919c2a9a5c --rule k8s:$clusterid

echo "- Getting kubeconfig"
doctl kubernetes cluster kubeconfig show $clusterid > kubeconfig
chmod 600 kubeconfig

echo "- Installing external secrets"
echo "  - Adding helm repo"
h repo add external-secrets https://charts.external-secrets.io
echo "  - Updating repos"
h repo update
echo "  - Installing external secrets"
h upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --set installCRDs=true
echo "  - Waiting for rollout to complete"
k rollout status deployment/external-secrets -n external-secrets
echo "  - Config: Secret Credentials"
cat <<EOT | k apply -f -
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
---
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

echo "- Setting up cert-manager items"
echo "  - Creating our CA"
cat <<EOT | k apply -f -
apiVersion: external-secrets.io/v1alpha1
kind: ExternalSecret
metadata:
    name: extsecret-addysnip-com-ca
    namespace: cert-manager
spec:
    secretStoreRef:
        kind: ClusterSecretStore
        name: gcp-secretstore
    target:
        name: addysnip-com-ca
        creationPolicy: Owner
        template:
            type: kubernetes.io/tls
    dataFrom:
        - key: addysnip-ca
EOT
echo -n "    - Waiting for secret deployment"
set +e
while true; do
    k get secret addysnip-com-ca -n cert-manager -o json &>/dev/null
    if [[ $? -eq 0 ]]; then
        echo " -- done"
        break
    fi
    sleep 1
done
set -e

echo "  - Creating Cluster Issuers"
cat <<EOT | k apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
    name: addysnip-com-ca
spec:
    ca:
        secretName: addysnip-com-ca
EOT

echo "- Installing ingress-nginx"
# https://github.com/kubernetes/ingress-nginx/blob/main/hack/manifest-templates/provider/do/values.yaml
cat <<EOF >/tmp/ingress-nginx.yaml
controller:
  service:
    type: LoadBalancer
    externalTrafficPolicy: Local
    annotations:
      service.beta.kubernetes.io/do-loadbalancer-enable-proxy-protocol: "false"
  config:
    use-proxy-protocol: "false"
  admissionWebhooks:
    timeoutSeconds: 29
  kind: DaemonSet
defaultBackend:
  enabled: true
EOF
h upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace --values /tmp/ingress-nginx.yaml

echo "- Installing Redis Cluster"
echo "  - Getting Redis Cluster credentials"
redis_versions=($(gcloud secrets versions list $redis_secret |grep -v 'NAME' | awk '{ print $1 }'))
redis_password=$(gcloud secrets versions access ${redis_versions[0]} --secret $redis_secret | jq -r '.REDIS_PASSWORD')

echo "  - Adding and updating helm repo"
h repo add bitnami https://charts.bitnami.com/bitnami
h repo update

echo "  - Install Cluster"
h upgrade --install redis bitnami/redis --namespace redis --create-namespace  --set auth.password=$redis_password --set sentinel.enabled=true --set sentinel.masterSet=master --set auth.sentinel=false

echo "- Annotating ingress-nginx service"
echo -n "  - Looking up load balancer IP ($clusterid) -- may take a minute to provision"
while true; do
    lbip=$(get_loadbalancer_ip $clusterid)
    if [[ $lbip != "null" && $? == "0" ]]; then
        break
    fi
    sleep 1
done
echo " -- $lbip"
echo "  - Creating DNS entry"
lbhost=$(echo -n $lbip | od -A n -t x1 | sed 's/ //g')
doctl compute domain records create inf.addysnip.com --record-name "$lbhost.$env" --record-type A --record-data $lbip --record-ttl 120
echo "  - Adding annotations"
k annotate service ingress-nginx-controller -n ingress-nginx --overwrite service.beta.kubernetes.io/do-loadbalancer-hostname="${lbhost}.${env}.inf.addysnip.com"
k annotate service ingress-nginx-controller -n ingress-nginx --overwrite service.beta.kubernetes.io/do-loadbalancer-name="${lbhost}.${env}.inf.addysnip.com"
k annotate service ingress-nginx-controller -n ingress-nginx --overwrite service.beta.kubernetes.io/do-loadbalancer-enable-proxy-protocol="false"

echo "- Creating Rancher Cluster"
curl -X POST -H "Authorization: Bearer $rancher_token" $rancher_server/v1/provisioning.cattle.io.clusters -H "Content-Type: application/json" -H "Accept: application/json" --data @<(cat <<EOF
{
    "metadata": {
        "labels": {
            "addysnip/fleet": "apply",
            "env": "$env"
        },
        "name": "$clustername",
        "namespace": "fleet-default"
    },
    "spec": {},
    "type": "provisioning.cattle.io.cluster"
}
EOF
)
echo "- Waiting for cluster object to be created"
set +e
while true; do
    kubectl --kubeconfig $rancher_kubeconfig get cluster.provisioning.cattle.io/$clustername -n fleet-default -o json &>/dev/null
    if [[ $? -eq 0 ]]; then
        echo " -- done"
        break
    fi
    sleep 1
done
set -e

echo -n "- Waiting for Cluster Registration Token to be generated"
rancherClusterId=$(kubectl --kubeconfig $rancher_kubeconfig get cluster.provisioning.cattle.io/$clustername -n fleet-default -o json | jq -r .status.clusterName)
set +e
while true; do
    kubectl --kubeconfig $rancher_kubeconfig get clusterregistrationtokens.management.cattle.io -n $rancherClusterId default-token -o json | jq -r '.status.manifestUrl' &>/dev/null
    if [[ $manifestUrl != "null" && $? == "0" ]]; then
        echo " -- done"
        break
    fi
done
set -e

manifestUrl=$(kubectl --kubeconfig $rancher_kubeconfig get clusterregistrationtokens.management.cattle.io -n $rancherClusterId default-token -o json | jq -r '.status.manifestUrl')

echo "- Applying manifest $manifestUrl"
k apply -f $manifestUrl

cp kubeconfig ~/.kube/config-files/$name-$region-$env.yaml
echo "$name-$region-$env" >> .name

echo "Waiting for redirector service to reconfigure ingress-nginx's default backend"
set +e
while true; do
    k get svc -n redirector | grep redirector &>/dev/null
    if [[ $? -eq 0 ]]; then
        echo "Redirector service is configured"
        break
    fi
    sleep 5
done
set -e
echo "Reconfiguring ingress-nginx"
cat <<EOF >/tmp/ingress-nginx.yaml
controller:
  service:
    type: LoadBalancer
    externalTrafficPolicy: Local
    annotations:
      service.beta.kubernetes.io/do-loadbalancer-enable-proxy-protocol: "false"
  config:
    use-proxy-protocol: "false"
  admissionWebhooks:
    timeoutSeconds: 29
  kind: DaemonSet
  extraArgs:
    default-backend-service: "redirector/redirector"
    default-ssl-certificate: "redirector/addysnip-com-ssl"
EOF

h upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace --values /tmp/ingress-nginx.yaml

echo "Waiting for ingress-nginx to be ready"

k rollout status ds/ingress-nginx-controller -n ingress-nginx

echo "- Done and done... now go reconfigure haproxy!"