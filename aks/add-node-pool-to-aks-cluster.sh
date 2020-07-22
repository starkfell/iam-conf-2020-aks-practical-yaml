#!/bin/bash

# This script is responsible for deploying a Node Pool to an existing AKS Cluster.

# Parse Script Parameters.
while getopts ":a:s:d:f:g:h:j:k:l:z:" opt; do
    case "${opt}" in
        a) # Base Name of the Kubernetes Deployment.
             BASE_NAME=${OPTARG}
             ;;
        s) # The Name of the AKS Node Pool Resource Group.
             AKS_NODE_POOL_RG_NAME=${OPTARG}
             ;;
        d) # The Name of the AKS Node Pool.
             AKS_NODE_POOL_NAME=${OPTARG}
             ;;
        f) # The Kubernetes Version being used by the AKS Cluster.
             K8S_VERSION=${OPTARG}
             ;;
        g) # The Minimum Node Count for the AKS Node Pool.
             MIN_NODE_COUNT=${OPTARG}
             ;;
        h) # The Maximum Node Count for the AKS Node Pool.
             MAX_NODE_COUNT=${OPTARG}
             ;;
        j) # The Initial Node Count for the AKS Node Pool.
             INITIAL_NODE_COUNT=${OPTARG}
             ;;
        k) # The Node OS Disk Size(GB) of each Node in the AKS Node Pool.
             NODE_OS_DISK_SIZE=${OPTARG}
             ;;
        l) # The Azure VM Size of each Node in the AKS Node Pool.
             NODE_VM_SIZE=${OPTARG}
             ;;
        z) # The OS Type (Windows or Linux) running on each Node in the AKS Node Pool.
             OS_TYPE=${OPTARG}
             ;;
        \?) # Unrecognised option - show help.
            echo -e \\n"Option [-${BOLD}$OPTARG${NORM}] is not allowed. All Valid Options are listed below:"
            echo -e "-a BASE_NAME                         - Base Name of the Kubernetes Deployment."
            echo -e "-s AKS_NODE_POOL_RG_NAME             - The Name of the AKS Node Pool Resource Group."
            echo -e "-d AKS_NODE_POOL_NAME                - The Name of the AKS Node Pool."
            echo -e "-f K8S_VERSION                       - The Kubernetes Version being used by the AKS Cluster."
            echo -e "-g MIN_NODE_COUNT                    - The Minimum Node Count for the AKS Node Pool."
            echo -e "-h MAX_NODE_COUNT                    - The Maximum Node Count for the AKS Node Pool."
            echo -e "-j INITIAL_NODE_COUNT                - The Initial Node Count for the AKS Node Pool."
            echo -e "-k NODE_OS_DISK_SIZE                 - The Node OS Disk Size(GB) of each Node in the AKS Node Pool."
            echo -e "-l NODE_VM_SIZE                      - The Azure VM Size of each Node in the AKS Node Pool."
            echo -e "-z OS_TYPE                           - The OS Type (Windows or Linux) running on each Node in the AKS Node Pool."
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

if [ -z "${AKS_NODE_POOL_RG_NAME}" ]; then
    echo "[$(date -u)][---fail---] The Name of the AKS Node Pool Resource Group. must be provided."
    exit 2
fi

if [ -z "${AKS_NODE_POOL_NAME}" ]; then
    echo "[$(date -u)][---fail---] The Name of the AKS Node Poolmust be provided."
    exit 2
fi

if [ -z "${K8S_VERSION}" ]; then
    echo "[$(date -u)][---fail---] The Kubernetes Version being used by the AKS Cluster must be provided."
    exit 2
fi

if [ -z "${MIN_NODE_COUNT}" ]; then
    echo "[$(date -u)][---fail---] The Minimum Node Count for the AKS Node Pool must be provided."
    exit 2
fi

if [ -z "${MAX_NODE_COUNT}" ]; then
    echo "[$(date -u)][---fail---] The Maximum Node Count for the AKS Node Pool must be provided."
    exit 2
fi

if [ -z "${INITIAL_NODE_COUNT}" ]; then
    echo "[$(date -u)][---fail---] The Initial Node Count for the AKS Node Pool must be provided."
    exit 2
fi

if [ -z "${NODE_OS_DISK_SIZE}" ]; then
    echo "[$(date -u)][---fail---] The Node OS Disk Size(GB) of each Node in the AKS Node Pool must be provided."
    exit 2
fi

if [ -z "${NODE_VM_SIZE}" ]; then
    echo "[$(date -u)][---fail---] The Azure VM Size of each Node in the AKS Node Pool must be provided."
    exit 2
fi

if [ -z "${OS_TYPE}" ]; then
    echo "[$(date -u)][---fail---] The OS Type (Windows or Linux) running on each Node in the AKS Node Pool must be provided."
    exit 2
fi

# Static Variables.
K8S_CLUSTER_SP_USERNAME="${BASE_NAME}"


echo "[---info------] - add_node_pool_to_aks_cluster --- START ---"

# Checking if the AKS node pool already exists.
CHECK_AKS_NODE_POOL=$(az aks nodepool show \
--name $AKS_NODE_POOL_NAME \
--cluster-name $K8S_CLUSTER_SP_USERNAME \
--resource-group $AKS_NODE_POOL_RG_NAME \
--query "name" \
--output tsv
)

if [[ "$CHECK_AKS_NODE_POOL" == "$AKS_NODE_POOL_NAME" ]]; then
   echo "[---info------] AKS Node Pool [$AKS_NODE_POOL_NAME] already exists."
else
   echo "[---info------] AKS Node Pool [$AKS_NODE_POOL_NAME] was not found, adding it."

    # Adding the AKS node pool.
    ADD_AKS_NODE_POOL=$(az aks nodepool add \
    --name $AKS_NODE_POOL_NAME \
    --cluster-name $K8S_CLUSTER_SP_USERNAME \
    --resource-group $AKS_NODE_POOL_RG_NAME \
    --enable-cluster-autoscaler \
    --kubernetes-version $K8S_VERSION \
    --min-count $MIN_NODE_COUNT \
    --max-count $MAX_NODE_COUNT \
    --node-count $INITIAL_NODE_COUNT \
    --node-osdisk-size $NODE_OS_DISK_SIZE \
    --node-vm-size $NODE_VM_SIZE \
    --os-type $OS_TYPE \
    --query "provisioningState" \
    --output tsv 2>&1)

    if [[ "$ADD_AKS_NODE_POOL" == "Succeeded" ]]; then
        echo "[---success---] Added Node Pool [$AKS_NODE_POOL_NAME] for AKS Cluster [$K8S_CLUSTER_SP_USERNAME] in Resource Group [$AKS_NODE_POOL_RG_NAME]."
    else
        echo "[---fail------] Failed to add Node Pool [$AKS_NODE_POOL_NAME] for AKS Cluster [$K8S_CLUSTER_SP_USERNAME] in Resource Group [$AKS_NODE_POOL_RG_NAME]."
        echo "[---fail------] $ADD_AKS_NODE_POOL"
        exit 2
    fi
fi

# Process Complete.
echo "[---info------] The Process of adding Node Pool [$AKS_NODE_POOL_NAME] to AKS Cluster [$K8S_CLUSTER_SP_USERNAME] in Resource Group [$AKS_NODE_POOL_RG_NAME] is complete."