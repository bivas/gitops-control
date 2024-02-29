#!/usr/bin/env bash

set -e

managed_clusters=(daas-euw1 daas-euc1 cp-euw1)
all_cluster=(daas-euw1 daas-euc1 cp-euw1 argocd)

# check if kind and yq are installed
if ! command -v kind &> /dev/null; then
  echo "kind could not be found. Please install kind first."
  exit 1
fi
if ! command -v yq &> /dev/null; then
  echo "yq could not be found. Please install yq first."
  exit 1
fi

# create cluster if not already exist
for cluster in "${all_cluster[@]}"; do
  if kind get clusters | grep -q "${cluster}"; then
    echo "Cluster ${cluster} already exists. Skipping ..."
  else
    kind create cluster --name="${cluster}"
  fi
done

# use argocd cluster
kubectl config use-context kind-argocd

# installing argocd server if not already installed
if kubectl get namespace argocd &> /dev/null; then
  echo "Argocd namespace already exists. Skipping ..."
else
  kubectl create namespace argocd
fi
if kubectl get deployment -n argocd argocd-server &> /dev/null; then
  echo "Argocd server already installed. Skipping ..."
else
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
fi

# wait for argocd server to be ready
echo "Waiting for argocd server to be ready ..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# change argocd server to use NodePort
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'

# change argocd admin password
echo "Change argocd admin password ..."
kubectl patch secret -n argocd argocd-secret \
  -p '{"stringData": { "admin.password": "'$(htpasswd -bnBC 10 "" adminadmin | tr -d ':\n')'"}}'


# connect argocd to managed clusters if not already connected
for cluster in "${managed_clusters[@]}"; do
  if kubectl get secret -n argocd "${cluster}" &> /dev/null; then
    echo "Cluster ${cluster} already connected to argocd. Skipping ..."
  else
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
  fi
done
