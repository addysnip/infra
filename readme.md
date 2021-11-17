This script sets up a new cluster, adds that cluster to the DBaaS firewall rules to access the DB cluster, 
installs chart-manager and ingress-nginx, and then adds the cluster to my existing ArgoCD install.

edit terraform/do/variables_override.tf (copy .example)
run cd do && bash setup.sh

To cleanup:
cd do && bash teardown.sh
