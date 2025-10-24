#!/bin/bash

CLUSTER_NAME="kind-mgmt"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "${CLUSTER_NAME} cluster is running. Deleting it!"
    kind delete cluster --name kind-mgmt
else
    echo "${CLUSTER_NAME} cluster is not running. Installing it!"
fi

kind create cluster --name kind-mgmt --config kind-cluster-with-extramounts.yaml

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

kubectl apply -f ../mgmt/base/mgmt/crs/

helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts --force-update
helm install flux fluxcd-community/flux2 -n flux-system --create-namespace --wait
helm install flux-sync fluxcd-community/flux2-sync -n flux-system --set gitRepository.spec.ref.branch=main \
  --set gitRepository.spec.url=https://github.com/simonkran/capi-mgmt \
  --set kustomization.spec.path=./mgmt/dev/mgmt-0