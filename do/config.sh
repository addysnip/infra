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