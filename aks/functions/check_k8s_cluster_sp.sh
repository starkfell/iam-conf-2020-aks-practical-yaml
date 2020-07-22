#!/bin/bash

check_k8s_cluster_sp () {

    K8S_CLUSTER_SP_USERNAME=$1
    AZURE_SUBSCRIPTION_ID=$2
    K8S_RESOURCE_GROUP_NAME=$3
    K8S_KEY_VAULT_NAME=$4

    echo "[---info------] - check_k8s_cluster_sp --- START ---"

    # Checking to see if the K8s Cluster Service Principal already exists in the Azure Subscription.
    K8S_CLUSTER_SP_CHECK=$(/usr/bin/az ad sp list --all 2>&1 \
    | jq --arg K8S_CLUSTER_SP_USERNAME "$K8S_CLUSTER_SP_USERNAME" '.[] | select(.appDisplayName == $K8S_CLUSTER_SP_USERNAME).appDisplayName' \
    | tr -d '"')

    if [ ! -z "${K8S_CLUSTER_SP_CHECK}" ]; then
        echo "[---info------] The K8s Cluster Service Principal [$K8S_CLUSTER_SP_USERNAME] already exists."
    else
        echo "[---info------] The K8s Cluster Service Principal [$K8S_CLUSTER_SP_USERNAME] was not found."

        # Creating the K8s Cluster Service Principal and scoping it to the Kubernetes Cluster Resource Group.
        CREATE_K8S_CLUSTER_SP=$(/usr/bin/az ad sp create-for-rbac \
        --role="Contributor" \
        --name="http://$K8S_CLUSTER_SP_USERNAME" \
        --years 50 \
        --scopes="/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$K8S_RESOURCE_GROUP_NAME" 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Created the Kubernetes Cluster Service Principal [$K8S_CLUSTER_SP_USERNAME]"
        else
            echo "[---fail------] Failed to create the Kubernetes Cluster Service Principal [$K8S_CLUSTER_SP_USERNAME]."
            echo "[---fail------] $CREATE_K8S_CLUSTER_SP"
            exit 2
        fi

        # Adding the K8s Cluster Service Principal Username to the Azure Key Vault.
        K8S_CLUSTER_SP_NAME=$(echo "${CREATE_K8S_CLUSTER_SP}" | sed -n '/^{$/,$p' | jq '.name' | tr -d '"')

        ADD_TO_VAULT=$(/usr/bin/az keyvault secret set \
        --name "sp-$K8S_CLUSTER_SP_USERNAME-username" \
        --vault-name "$K8S_KEY_VAULT_NAME" \
        --value "$K8S_CLUSTER_SP_NAME" \
        --output none 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] The K8s Cluster Service Principal Username has been added to Key Vault [$K8S_KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to add the K8s Cluster Service Principal Username to Key Vault [$K8S_KEY_VAULT_NAME]."
            echo "[---fail------] $ADD_TO_VAULT"
            exit 2
        fi

        # Adding the K8s Cluster Service Principal Password to the Azure Key Vault.
        K8S_CLUSTER_SP_PASSWORD=$(echo "${CREATE_K8S_CLUSTER_SP}" | sed -n '/^{$/,$p' | jq '.password' | tr -d '"')

        ADD_TO_VAULT=$(/usr/bin/az keyvault secret set \
        --name "sp-$K8S_CLUSTER_SP_USERNAME-password" \
        --vault-name "$K8S_KEY_VAULT_NAME" \
        --value "$K8S_CLUSTER_SP_PASSWORD" \
        --output none 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] The K8s Cluster Service Principal Password has been added to Key Vault [$K8S_KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to add the K8s Cluster Service Principal Password to Key Vault [$K8S_KEY_VAULT_NAME]."
            echo "[---fail------] $ADD_TO_VAULT"
            exit 2
        fi
    fi

    echo "[---info------] - check_k8s_cluster_sp --- END ---"
}