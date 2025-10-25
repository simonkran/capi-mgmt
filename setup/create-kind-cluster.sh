#!/bin/bash

cd "$(dirname "$0")/.."

CLUSTER_NAME="kind-mgmt"

# Check for existing kind clusters
CLUSTERS=$(kind get clusters 2>/dev/null)

if [ -n "$CLUSTERS" ]; then
    echo "Found existing kind cluster(s):"
    echo "$CLUSTERS"
    echo ""
    read -p "Do you want to delete these clusters? (y/n): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$CLUSTERS" | while read -r cluster; do
            echo "Deleting cluster: $cluster"
            kind delete cluster --name "$cluster"
        done
    else
        echo "Deletion cancelled. Exiting."
        exit 0
    fi
fi

# Create new cluster
echo "Creating new cluster: ${CLUSTER_NAME}"
kind create cluster --name "${CLUSTER_NAME}" --config setup/kind-cluster-with-extramounts.yaml

helm repo add capi-operator https://kubernetes-sigs.github.io/cluster-api-operator --force-update
helm repo add jetstack https://charts.jetstack.io --force-update

helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true --wait

helm install capi-operator capi-operator/cluster-api-operator \
  -n capi-operator-system --create-namespace \
  --set core.cluster-api.enabled=true \
  --set bootstrap.kubeadm.enabled=true \
  --set controlPlane.kubeadm.enabled=true \
  --set infrastructure.docker.enabled=true \
  --set addon.helm.enabled=true \
  --set manager.featureGates.core.ClusterTopology=true \
  --set manager.featureGates.kubeadm.ClusterTopology=true \
  --set manager.featureGates.docker.ClusterTopology=true \
  --wait --timeout 180s

echo "sleep 75s"
sleep 75

kubectl apply -f ./mgmt/base/mgmt/crs/

helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts --force-update
helm install flux fluxcd-community/flux2 -n flux-system --create-namespace --wait
helm install flux-sync fluxcd-community/flux2-sync -n flux-system --set gitRepository.spec.ref.branch=main \
  --set gitRepository.spec.url=https://github.com/simonkran/capi-mgmt \
  --set kustomization.spec.path=./mgmt/dev/mgmt-0