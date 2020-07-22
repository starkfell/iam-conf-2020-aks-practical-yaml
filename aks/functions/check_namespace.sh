#!/bin/bash

check_namespace () {

    K8S_CLUSTER_SP_USERNAME=$1
    K8S_KEY_VAULT_NAME=$2
    K8S_NAMESPACE=$3

    echo "[---info------] - check_namespace --- START ---"

    # Downloading the AKS cluster-admin 'kubeconfig' from the AKS Cluster.
    RETRIEVE_K8S_CLUSTER_ADMIN_KUBECONFIG=$(az aks get-credentials \
    --resource-group "${K8S_CLUSTER_SP_USERNAME}" \
    --name "${K8S_CLUSTER_SP_USERNAME}" \
    --file ./cluster-admin-kubeconfig \
    --overwrite-existing \
    --admin \
    --output none 2>&1)

    if [ $? -eq 0 ]; then
        echo "[---success---] Downloaded the cluster-admin kubeconfig to [./cluster-admin-kubeconfig]."
    else
        echo "[---fail------] Failed to download the cluster-admin kubeconfig to [./cluster-admin-kubeconfig]."
        echo "[---fail------] $RETRIEVE_K8S_CLUSTER_ADMIN_KUBECONFIG"
        exit 2
    fi

    # Configuring the Host to connect to the AKS Cluster. 
    export KUBECONFIG="./cluster-admin-kubeconfig"

    if [ $? -eq 0 ]; then
        echo "[---success---] The Host is now targeting K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    else
        echo "[---fail------] Failed to configure the Host to target K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
        exit 2
    fi

    # Checking to see if the Namespace already exists.
    NAMESPACE_CHECK=$(/usr/local/bin/kubectl get namespaces -o json \
    | jq --arg K8S_NAMESPACE "$K8S_NAMESPACE" '.items[].metadata | select(.name == $K8S_NAMESPACE).name' | tr -d '"')

    if [[ "$NAMESPACE_CHECK" = "$K8S_NAMESPACE" ]]; then
        echo "[---success---] Kubernetes Namespace [$K8S_NAMESPACE] already exists."
    else
        echo "[---success---] Kubernetes Namespace [$K8S_NAMESPACE] was not found, creating it."

        # Creating the Namespace in the Kubernetes Cluster.
        CREATE_NAMESPACE=$(/usr/local/bin/kubectl create namespace $K8S_NAMESPACE 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Created the Namespace [$K8S_NAMESPACE] in K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
        else
            echo "[---fail------] Failed to create the Namespace [$K8S_NAMESPACE] in K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
            echo "[---fail------] $CREATE_NAMESPACE"
            exit 2
        fi
    fi

    # Removing the local copy of the AKS Cluster Master 'kubeconfig', if it exists.
    if [ -e "cluster-admin-kubeconfig" ]; then
        rm -f "cluster-admin-kubeconfig"

        if [ $? -eq 0 ]; then
            echo "[---success---] Removed the K8s Master 'kubeconfig' file [cluster-admin-kubeconfig]."
        else
            echo "[---fail------] Failed to remove the K8s Master 'kubeconfig' file [cluster-admin-kubeconfig]."
            exit 2
        fi
    fi

    echo "[---info------] - check_namespace --- END ---"
}