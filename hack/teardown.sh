#!/usr/bin/env bash

all_cluster=(daas-euw1 daas-euc1 cp-euw1 argocd)

# delete all clusters
for cluster in "${all_cluster[@]}"; do
  kind delete cluster --name="${cluster}"
done