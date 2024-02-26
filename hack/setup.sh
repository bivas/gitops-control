#!/usr/bin/env bash

set -e

managed_clusters=(daas-euw1 daas-euc1 cp-euw1)
all_cluster=(daas-euw1 daas-euc1 cp-euw1 argocd)


# start 4 kind clusters
for cluster in "${all_cluster[@]}"; do
  kind create cluster --name="${cluster}"
done

# use argocd cluster
kubectl config use-context kind-argocd

# install argocd
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# wait for argocd server to be ready
echo "Waiting for argocd server to be ready ..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# change argocd server to use NodePort
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'

# change argocd admin password
echo "Change argocd admin password ..."
kubectl patch secret -n argocd argocd-secret \
  -p '{"stringData": { "admin.password": "'$(htpasswd -bnBC 10 "" adminadmin | tr -d ':\n')'"}}'

# connect clusters to argocd
for cluster in "${managed_clusters[@]}"; do
   cat <<EOF | kubectl apply -n argocd -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${cluster}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: "${cluster}"
  server: "$(kind get kubeconfig --internal --name ${cluster} | yq '.clusters[0].cluster.server')"
  config: |
    {
      "tlsClientConfig": {
        "caData": "$(kind get kubeconfig --internal --name ${cluster} | yq '.clusters[0].cluster.certificate-authority-data')",
        "certData": "$(kind get kubeconfig --internal --name ${cluster} | yq '.users[0].user.client-certificate-data')",
        "keyData": "$(kind get kubeconfig --internal --name ${cluster} | yq '.users[0].user.client-key-data')"
      }
    }
EOF
done
