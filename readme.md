# Provision new cluster

1. cd clusterv2 && bash build.sh <name> <region> <k8s version/latest> <env>
2. reconfigure HAProxy repo:edge-provisioner: bash reconfigure.sh <env>
3. Check to make sure environment is working as expected
4. Bring down old environment: cd data/<name>; bash destroy.sh
5. Repeat step 2 to remove old cluster from HAProxy config
