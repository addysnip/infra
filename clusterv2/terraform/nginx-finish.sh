#!/bin/bash

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

helm --kubeconfig kubeconfig upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace --values /tmp/ingress-nginx.yaml