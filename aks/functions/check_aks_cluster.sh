#!/bin/bash

check_aks_cluster () {

    K8S_CLUSTER_SP_USERNAME=$1
    K8S_RESOURCE_GROUP_NAME=$2
    AZURE_LOCATION=$3
    K8S_SSH_PRIVATE_KEY_NAME=$4
    K8S_KEY_VAULT_NAME=$5
    DNS_PREFIX=$6
    K8S_ACR_NAME=$7
    AKS_CLUSTER_MANIFEST=$8

    echo "[---info------] - check_aks_cluster --- START ---"

    # Checking to see if the AKS Cluster already exists.
    AKS_CLUSTER_CHECK=$(az aks show \
    --name $K8S_CLUSTER_SP_USERNAME \
    --resource-group $K8S_RESOURCE_GROUP_NAME \
    --query provisioningState \
    --output tsv 2> /dev/null)

    if [[ "$AKS_CLUSTER_CHECK" == "Succeeded" ]]; then
        echo "[---info------] AKS Cluster [$K8S_CLUSTER_SP_USERNAME], already exists."
        echo "[---info------] Provisioning State [$AKS_CLUSTER_CHECK]."
    else
        # If the AKS Cluster isn't found, a new Deployment will start.
        echo "[---info------] AKS Cluster [$K8S_CLUSTER_SP_USERNAME] was not found. Continuing with the Deployment."

        # Install aks-preview extension.
        INSTALL_EXTENSION=$(az extension add \
        --name aks-preview 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Installed the [aks-preview] extension."
        else
            echo "[---fail------] Failed to install the [aks-preview] extension."
            echo "[---fail------] $INSTALL_EXTENSION"
            exit 2
        fi

        # Retrieving the Azure Subscription Tenant ID.
        AZURE_SUB_TENANT_ID=$(az account show \
        --query tenantId \
        --output tsv 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the Azure Subscription Tenant ID [$AZURE_SUB_TENANT_ID]."
        else
            echo "[---fail------] Failed to retrieve the Azure Subscription Tenant ID [$AZURE_SUB_TENANT_ID]."
            echo "[---fail------] $AZURE_SUB_TENANT_ID"
            exit 2
        fi

         # Downloading the SSH Public Key for the Kubernetes Cluster from the Key Vault.
        RETRIEVE_SSH_PUBLIC_KEY=$(/usr/bin/az keyvault secret show \
        --name "$K8S_SSH_PRIVATE_KEY_NAME-pub" \
        --vault-name $K8S_KEY_VAULT_NAME \
        --query value \
        --output tsv 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Downloaded the AKS Cluster SSH Private Key to [$K8S_SSH_PRIVATE_KEY_NAME-pub] from Key Vault [$K8S_KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to download the AKS Cluster SSH Private Key to [$K8S_SSH_PRIVATE_KEY_NAME-pub] from Key Vault [$K8S_KEY_VAULT_NAME]."
            echo "[---fail------] $RETRIEVE_SSH_PUBLIC_KEY"
            exit 2
        fi

        # Retrieving the Password of the Kubernetes Cluster Service Principal.
        RETRIEVE_K8S_CLUSTER_SP_PASSWORD=$(/usr/bin/az keyvault secret show \
        --name "sp-$K8S_CLUSTER_SP_USERNAME-password" \
        --vault-name $K8S_KEY_VAULT_NAME \
        --query value \
        --output tsv 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Downloaded the Password of the AKS Cluster Service Principal [$K8S_CLUSTER_SP_USERNAME] from Key Vault [$K8S_KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to download the Password of the AKS Cluster Service Principal [$K8S_CLUSTER_SP_USERNAME] from Key Vault [$K8S_KEY_VAULT_NAME]."
            echo "[---fail------] $RETRIEVE_K8S_CLUSTER_SP_PASSWORD"
            exit 2
        fi

        # Retrieving the Password of the Server AAD Application.
        RETRIEVE_K8S_APISRV_APP_SECRET=$(/usr/bin/az keyvault secret show \
        --name "$K8S_CLUSTER_SP_USERNAME-aad-apisrv-password" \
        --vault-name $K8S_KEY_VAULT_NAME \
        --query value \
        --output tsv 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Downloaded the Password of Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv] from Key Vault [$K8S_KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to download the Password of Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv] from Key Vault [$K8S_KEY_VAULT_NAME]."
            echo "[---fail------] $RETRIEVE_K8S_APISRV_APP_SECRET"
            exit 2
        fi

        # Retrieving the Client ID of the Server AAD Application.
        RETRIEVE_K8S_APISRV_APP_ID=$(az ad app show \
        --id http://$K8S_CLUSTER_SP_USERNAME-aad-apisrv \
        --query appId \
        --output tsv 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the Client ID of Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv]."
        else
            echo "[---fail------] Failed to retrieve the Client ID of Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv]."
            echo "[---fail------] $RETRIEVE_K8S_APISRV_APP_ID"
            exit 2
        fi

        # Retrieving the Client ID of the Client AAD Application.
        RETRIEVE_K8S_APICLI_APP_ID=$(az ad app list \
        | jq --arg K8S_APICLI_APP_NAME "$K8S_CLUSTER_SP_USERNAME-aad-apicli" '.[] | select (.displayName|test($K8S_APICLI_APP_NAME)).appId' \
        | tr -d '"' 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the Client ID of Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apicli]."
        else
            echo "[---fail------] Failed to retrieve the Client ID of Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apicli]."
            echo "[---fail------] $RETRIEVE_K8S_APICLI_APP_ID"
            exit 2
        fi

        # Retrieving the values from the AKS Cluster Manifest.
        ADMIN_USERNAME=$(cat aks/aks-cluster-manifests/$AKS_CLUSTER_MANIFEST | jq -r .adminUsername) && \
        NODE_POOL_NAME=$(cat aks/aks-cluster-manifests/$AKS_CLUSTER_MANIFEST | jq -r .nodePoolName) && \
        K8S_VERSION=$(cat aks/aks-cluster-manifests/$AKS_CLUSTER_MANIFEST | jq -r .kubernetesVersion) && \
        INITIAL_NODE_COUNT=$(cat aks/aks-cluster-manifests/$AKS_CLUSTER_MANIFEST | jq -r .initialNodeCount) && \
        MIN_NODE_COUNT=$(cat aks/aks-cluster-manifests/$AKS_CLUSTER_MANIFEST | jq -r .minNodeCount) && \
        MAX_NODE_COUNT=$(cat aks/aks-cluster-manifests/$AKS_CLUSTER_MANIFEST | jq -r .maxNodeCount) && \
        NODE_OS_DISK_SIZE=$(cat aks/aks-cluster-manifests/$AKS_CLUSTER_MANIFEST | jq -r .nodeOsDiskSizeGB) && \
        NODE_VM_SIZE=$(cat aks/aks-cluster-manifests/$AKS_CLUSTER_MANIFEST | jq -r .nodeVmSize)

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the values from AKS Cluster Manifest [$AKS_CLUSTER_MANIFEST]."
        else
            echo "[---fail------] Failed to retrieve the values from AKS Cluster Manifest [$AKS_CLUSTER_MANIFEST]."
            exit 2
        fi

        # Deploying a new Kubernetes Cluster.
        echo "[---info------] Deploying AKS Cluster [$K8S_CLUSTER_SP_USERNAME] to Resource Group [$K8S_CLUSTER_SP_USERNAME]."
        echo "[---info------] Please be patient, this can take up to 30 minutes to complete."

        DEPLOY_AKS_CLUSTER=$(az aks create \
        --name $K8S_CLUSTER_SP_USERNAME \
        --dns-name-prefix $K8S_CLUSTER_SP_USERNAME \
        --node-resource-group "$K8S_CLUSTER_SP_USERNAME-nodes" \
        --resource-group $K8S_RESOURCE_GROUP_NAME \
        --location $AZURE_LOCATION \
        --ssh-key-value "$RETRIEVE_SSH_PUBLIC_KEY" \
        --enable-cluster-autoscaler \
        --admin-username $ADMIN_USERNAME \
        --nodepool-name $NODE_POOL_NAME \
        --kubernetes-version $K8S_VERSION \
        --node-count $INITIAL_NODE_COUNT \
        --min-count $MIN_NODE_COUNT \
        --max-count $MAX_NODE_COUNT \
        --node-osdisk-size $NODE_OS_DISK_SIZE \
        --node-vm-size $NODE_VM_SIZE \
        --service-principal "http://$K8S_CLUSTER_SP_USERNAME" \
        --client-secret $RETRIEVE_K8S_CLUSTER_SP_PASSWORD \
        --aad-client-app-id $RETRIEVE_K8S_APICLI_APP_ID \
        --aad-server-app-id $RETRIEVE_K8S_APISRV_APP_ID \
        --aad-server-app-secret $RETRIEVE_K8S_APISRV_APP_SECRET \
        --aad-tenant-id $AZURE_SUB_TENANT_ID \
        --attach-acr $K8S_ACR_NAME \
        --query  provisioningState \
        --output tsv)

        if [[ "$DEPLOY_AKS_CLUSTER" == "Succeeded" ]]; then
            echo "[---success---] Deployed AKS Cluster [$K8S_CLUSTER_SP_USERNAME] to Resource Group [$K8S_CLUSTER_SP_USERNAME]."
        else
            echo "[---fail------] Failed to deploy AKS Cluster [$K8S_CLUSTER_SP_USERNAME] to Resource Group [$K8S_CLUSTER_SP_USERNAME]."
            echo "[---fail------] $DEPLOY_AKS"
            exit 2
        fi
    fi

    echo "[---info------] - check_aks_cluster --- END ---"
}