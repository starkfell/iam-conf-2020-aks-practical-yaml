#!/bin/bash

# Parse Script Parameters.
while getopts ":a:s:d:f:g:h:" opt; do
    case "${opt}" in
        a) # Base Name of the Kubernetes Deployment.
             BASE_NAME=${OPTARG}
             ;;
        s) # The Azure Subscription Tenant ID where the Kubernetes Cluster is being deployed to.
             AZURE_SUBSCRIPTION_TENANT_ID=${OPTARG}
             ;;
        d) # The Azure Subscription ID where the Kubernetes Cluster is being deployed to.
             AZURE_SUBSCRIPTION_ID=${OPTARG}
             ;;
        f) # The Azure Subscription Fully Qualified Domain Name where the Kubernetes Cluster is being deployed to.
             AZURE_SUBSCRIPTION_FQDN=${OPTARG}
             ;;
        g) # The Azure Location where the Kubernetes Cluster is being deployed.
             AZURE_LOCATION=${OPTARG}
             ;;
        h) # The name of the AKS Cluster Manifest to use to deploy the Kubernetes Cluster.
             AKS_CLUSTER_MANIFEST=${OPTARG}
             ;;
        \?) # Unrecognised option - show help.
            echo -e \\n"Option [-${BOLD}$OPTARG${NORM}] is not allowed. All Valid Options are listed below:"
            echo -e "-a BASE_NAME                       - The Base Name of the Kubernetes Deployment."
            echo -e "-s AZURE_SUBSCRIPTION_TENANT_ID    - The Azure Subscription Tenant ID where the Kubernetes Cluster is being deployed to."
            echo -e "-d AZURE_SUBSCRIPTION_ID           - The Azure Subscription ID where the Kubernetes Cluster is being deployed to."
            echo -e "-f AZURE_SUBSCRIPTION_FQDN         - The Azure Subscription Fully Qualified Domain Name where the Kubernetes Cluster is being deployed to."
            echo -e "-g AZURE_LOCATION                  - The Azure Location where the Kubernetes Cluster is being deployed."
            echo -e "-h AKS_CLUSTER_MANIFEST            - The name of the AKS Cluster Manifest to use to deploy the Kubernetes Cluster."
            echo -e ""
            echo -e "Additional script Syntax is available in the README.md file in the root of the repository."
            exit 2
            ;;
    esac
done
shift $((OPTIND-1))

# Verifying the following Script Parameter Values exist.
if [ -z "${BASE_NAME}" ]; then
    echo "[$(date -u)][---fail---] The The Base Name of the Kubernetes Deployment must be provided."
    exit 2
fi

if [ -z "${AZURE_SUBSCRIPTION_TENANT_ID}" ]; then
    echo "[$(date -u)][---fail---] The Azure Subscription Tenant ID where the Kubernetes Cluster is being deployed to. must be provided."
    exit 2
fi

if [ -z "${AZURE_SUBSCRIPTION_ID}" ]; then
    echo "[$(date -u)][---fail---] The Azure Subscription ID where the Kubernetes Cluster is being deployed to. must be provided."
    exit 2
fi

if [ -z "${AZURE_SUBSCRIPTION_FQDN}" ]; then
    echo "[$(date -u)][---fail---] The Azure Subscription Fully Qualified Domain Name where the Kubernetes Cluster is being deployed to must be provided."
    exit 2
fi

if [ -z "${AZURE_LOCATION}" ]; then
    echo "[$(date -u)][---fail---] The Azure Location where to deploy the Kubernetes Cluster must be provided."
    exit 2
fi

if [ -z "${AKS_CLUSTER_MANIFEST}" ]; then
    echo "[$(date -u)][---fail---] The name of the AKS Cluster Manifest to use to deploy the Kubernetes Cluster must be provided."
    exit 2
fi


# Static Variables.
K8S_CLUSTER_SP_USERNAME="${BASE_NAME}"
K8S_RESOURCE_GROUP_NAME="${BASE_NAME}"
K8S_KEY_VAULT_RESOURCE_GROUP_NAME="${BASE_NAME}-kv"
K8S_ACR_RESOURCE_GROUP_NAME="${BASE_NAME}-acr"
K8S_ACR_NAME=$(echo "${BASE_NAME}acr" | tr -d -)
K8S_KEY_VAULT_NAME="${BASE_NAME}"
K8S_SSH_PRIVATE_KEY_NAME="${BASE_NAME}-access-key"
DNS_PREFIX="${BASE_NAME}"


# Installing Kubectl.
sudo bash -c ". ./aks/functions/check_kubectl.sh && check_kubectl"

# Deploying the AKS Cluster Prerequisites.
. ./aks/functions/check_resource_group.sh && check_resource_group $K8S_CLUSTER_SP_USERNAME $K8S_RESOURCE_GROUP_NAME $AZURE_LOCATION
. ./aks/functions/check_resource_group.sh && check_resource_group $K8S_CLUSTER_SP_USERNAME $K8S_KEY_VAULT_RESOURCE_GROUP_NAME $AZURE_LOCATION
. ./aks/functions/check_resource_group.sh && check_resource_group $K8S_CLUSTER_SP_USERNAME $K8S_ACR_RESOURCE_GROUP_NAME $AZURE_LOCATION
. ./aks/functions/check_acr.sh && check_acr $K8S_ACR_NAME $K8S_ACR_RESOURCE_GROUP_NAME $AZURE_LOCATION
. ./aks/functions/check_key_vault.sh && check_key_vault $K8S_KEY_VAULT_NAME $K8S_KEY_VAULT_RESOURCE_GROUP_NAME
. ./aks/functions/check_k8s_ssh_keys.sh && check_k8s_ssh_keys $K8S_SSH_PRIVATE_KEY_NAME $K8S_KEY_VAULT_NAME
. ./aks/functions/check_k8s_cluster_sp.sh && check_k8s_cluster_sp $K8S_CLUSTER_SP_USERNAME $AZURE_SUBSCRIPTION_ID $K8S_RESOURCE_GROUP_NAME $K8S_KEY_VAULT_NAME
. ./aks/functions/check_k8s_aad_auth.sh && check_k8s_aad_auth $K8S_CLUSTER_SP_USERNAME $K8S_KEY_VAULT_NAME

# Deploying the AKS Cluster.
. ./aks/functions/check_aks_cluster.sh && check_aks_cluster \
$K8S_CLUSTER_SP_USERNAME \
$K8S_RESOURCE_GROUP_NAME \
$AZURE_LOCATION \
$K8S_SSH_PRIVATE_KEY_NAME \
$K8S_KEY_VAULT_NAME \
$DNS_PREFIX \
$K8S_ACR_NAME \
$AKS_CLUSTER_MANIFEST
