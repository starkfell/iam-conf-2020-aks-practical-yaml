#!/bin/bash

# This script deploys the Spring App to the AKS Cluster in it's own separate Namespace.

# Parse Script Parameters.
while getopts "a:s:d:" opt; do
    case "${opt}" in
        a) # Base Name of the AKS Cluster.
             BASE_NAME=${OPTARG}
             ;;
        s) # The Namespace where the Spring Application runs on the AKS Cluster.
             NAMESPACE=${OPTARG}
             ;;
        d) # The Name of the Postgres Database being used by the Spring App.
             POSTGRES_DB_NAME=${OPTARG}
             ;;
        \?) # Unrecognised option - show help.
            echo -e \\n"Option [-${BOLD}$OPTARG${NORM}] is not allowed. All Valid Options are listed below:"
            echo -e "-a BASE_NAME                       - The Base Name of the AKS Cluster."
            echo -e "-s NAMESPACE                       - The Namespace where the Spring Application runs on the AKS Cluster."
            echo -e "-d POSTGRES_DB_NAME                - The Name of the Postgres Database being used by the Spring App."
            echo -e ""
            echo -e "An Example of how to use this script is shown below:"
            echo -e "./deploy-spring-app.sh -a iam-k8s-spring -s spring -d springdb\\n"
            exit 2
            ;;
    esac
done
shift $((OPTIND-1))

# Verifying the Script Parameters Values exist.
if [ -z "${BASE_NAME}" ]; then
    echo "The Base Name of the AKS Cluster must be provided."
    exit 2
fi

if [ -z "${NAMESPACE}" ]; then
    echo "The Namespace where the Spring Application runs on the AKS Cluster must be provided."
    exit 2
fi

if [ -z "${POSTGRES_DB_NAME}" ]; then
    echo "The Name of the Postgres Database being used by the Spring App must be provided."
    exit 2
fi

# Static Variables
K8S_CLUSTER_SP_USERNAME="${BASE_NAME}"
POSTGRES_DBS_KV_NAME="${BASE_NAME}-psql-dbs"
POSTGRES_SRV_NAME="${BASE_NAME}-psql"
AZ_POSTGRES_SRV_NAME_SECRET="az-postgres-server-name"
AZ_POSTGRES_DB_NAME_SECRET="az-postgres-db-name"
AZ_POSTGRES_DB_USERNAME_SECRET="az-postgres-db-username"
AZ_POSTGRES_DB_PASSWORD_SECRET="az-postgres-db-password"


# Creating the 'deploy' directory.
CREATE_DIR=$(rm -rf deploy && mkdir -p deploy 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Created directory [deploy]."
else
    echo "[---fail------] Unable to create directory [deploy]."
    echo "[---fail------] $CREATE_DIR"
    exit 2
fi

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

# Checking to see if the Spring Application Namespace already exists.
NAMESPACE_CHECK=$(/usr/local/bin/kubectl get namespaces -o json \
| jq --arg NAMESPACE "$NAMESPACE" '.items[].metadata | select(.name == $NAMESPACE).name' | tr -d '"')

if [[ "$NAMESPACE_CHECK" = "$NAMESPACE" ]]; then
    echo "[---success---] AKS Namespace [$NAMESPACE] already exists."
else
    echo "[---success---] AKS Namespace [$NAMESPACE] was not found, creating it."

    # Creating the Spring Application Namespace in the AKS Cluster.
    CREATE_NAMESPACE=$(/usr/local/bin/kubectl create namespace $NAMESPACE 2>&1)
    if [ $? -eq 0 ]; then
        echo "[---success---] Created the Namespace [$NAMESPACE] in K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    else
        echo "[---fail------] Failed to create the Namespace [$NAMESPACE] in K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
        echo "[---fail------] $CREATE_NAMESPACE"
        exit 2
    fi
fi

# Deleting the 'springdb' Postgres Server Name Secret in the AKS Cluster, by force.
DELETE_AZ_POSTGRES_SRV_NAME_SECRET=$(/usr/local/bin/kubectl delete secret "$AZ_POSTGRES_SRV_NAME_SECRET" \
--namespace $NAMESPACE 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Deleted secret [$AZ_POSTGRES_SRV_NAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
else
    echo "[---fail------] Failed to delete secret [$AZ_POSTGRES_SRV_NAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    echo "[---fail------] $DELETE_AZ_POSTGRES_SRV_NAME_SECRET"
fi

# Adding the 'springdb' Postgres Server Name Secret to a Secret in the AKS Cluster.
CREATE_AZ_POSTGRES_SRV_NAME_SECRET=$(/usr/local/bin/kubectl create secret generic "$AZ_POSTGRES_SRV_NAME_SECRET" \
--from-literal AZ_POSTGRES_SERVER_NAME="${POSTGRES_SRV_NAME}" \
--namespace $NAMESPACE 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Added the [springdb] Postgres Server Name to Secret [$AZ_POSTGRES_SRV_NAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
else
    echo "[---fail------] Failed to add the [springdb] Postgres Server Name to Secret [$AZ_POSTGRES_SRV_NAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    echo "[---fail------] $CREATE_AZ_POSTGRES_SRV_NAME_SECRET"
    exit 2
fi

# Deleting the 'springdb' Postgres DB Name Secret in the AKS Cluster, by force.
DELETE_AZ_POSTGRES_DB_NAME_SECRET=$(/usr/local/bin/kubectl delete secret "$AZ_POSTGRES_DB_NAME_SECRET" \
--namespace $NAMESPACE 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Deleted secret [$AZ_POSTGRES_DB_NAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
else
    echo "[---fail------] Failed to delete secret [$AZ_POSTGRES_DB_NAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    echo "[---fail------] $DELETE_AZ_POSTGRES_DB_NAME_SECRET"
fi

# Adding the 'springdb' Postgres DB Name Secret to a Secret in the AKS Cluster.
CREATE_AZ_POSTGRES_DB_NAME_SECRET=$(/usr/local/bin/kubectl create secret generic "$AZ_POSTGRES_DB_NAME_SECRET" \
--from-literal AZ_POSTGRES_DB_NAME="${POSTGRES_DB_NAME}" \
--namespace $NAMESPACE 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Added the [springdb] Postgres DB Name to Secret [$AZ_POSTGRES_DB_NAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
else
    echo "[---fail------] Failed to add the [springdb] Postgres DB Name to Secret [$AZ_POSTGRES_DB_NAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    echo "[---fail------] $CREATE_AZ_POSTGRES_DB_NAME_SECRET"
    exit 2
fi

# Deleting the 'springdb' Username Secret in the AKS Cluster, by force.
DELETE_AZ_POSTGRES_DB_USERNAME_SECRET=$(/usr/local/bin/kubectl delete secret "$AZ_POSTGRES_DB_USERNAME_SECRET" \
--namespace $NAMESPACE 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Deleted secret [$AZ_POSTGRES_DB_USERNAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
else
    echo "[---fail------] Failed to delete secret [$AZ_POSTGRES_DB_USERNAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    echo "[---fail------] $DELETE_AZ_POSTGRES_DB_USERNAME_SECRET"
fi

# Adding the 'springdb' Username to a Secret in the AKS Cluster.
CREATE_AZ_POSTGRES_DB_USERNAME_SECRET=$(/usr/local/bin/kubectl create secret generic "$AZ_POSTGRES_DB_USERNAME_SECRET" \
--from-literal AZ_POSTGRES_DB_USERNAME="${POSTGRES_DB_NAME}" \
--namespace $NAMESPACE 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Added the [springdb] password to Secret [$AZ_POSTGRES_DB_USERNAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
else
    echo "[---fail------] Failed to add the [springdb] password to Secret [$AZ_POSTGRES_DB_USERNAME_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    echo "[---fail------] $CREATE_AZ_POSTGRES_DB_PASSWORD_SECRET"
    exit 2
fi

# Retrieving the Azure Postgres DB User 'springdb' Password from the AKS Azure Key Vault.
RETRIEVE_AZ_POSTGRES_DB_PASSWORD=$(/usr/bin/az keyvault secret show \
--name "$POSTGRES_SRV_NAME-springdb-acct-password" \
--vault-name "$POSTGRES_DBS_KV_NAME" \
--query value \
--output tsv 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Retrieved the Password for the User 'springdb' for Azure Postgres DB [$POSTGRES_DB_NAME] from Key Vault [$POSTGRES_DBS_KV_NAME]."
else
    echo "[---fail------] Failed to retrieve the Password for the User 'springdb' for Azure Postgres DB [$POSTGRES_DB_NAME] from Key Vault [$POSTGRES_DBS_KV_NAME]."
    echo "[---fail------] $RETRIEVE_AZ_POSTGRES_DB_PASSWORD"
    exit 2
fi

# Deleting the 'springdb' Password Secret in the AKS Cluster, by force.
DELETE_AZ_POSTGRES_DB_PASSWORD_SECRET=$(/usr/local/bin/kubectl delete secret "$AZ_POSTGRES_DB_PASSWORD_SECRET" \
--namespace $NAMESPACE 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Deleted secret [$AZ_POSTGRES_DB_PASSWORD_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
else
    echo "[---fail------] Failed to delete secret [$AZ_POSTGRES_DB_PASSWORD_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    echo "[---fail------] $DELETE_AZ_POSTGRES_DB_PASSWORD_SECRET"
fi

# Adding the 'springdb' Password to a Secret in the AKS Cluster.
CREATE_AZ_POSTGRES_DB_PASSWORD_SECRET=$(/usr/local/bin/kubectl create secret generic "$AZ_POSTGRES_DB_PASSWORD_SECRET" \
--from-literal AZ_POSTGRES_DB_PASSWORD="${RETRIEVE_AZ_POSTGRES_DB_PASSWORD}" \
--namespace $NAMESPACE 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Added the [springdb] password to Secret [$AZ_POSTGRES_DB_PASSWORD_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
else
    echo "[---fail------] Failed to add the [springdb] password to Secret [$AZ_POSTGRES_DB_PASSWORD_SECRET] in Namespace [$NAMESPACE] on K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    echo "[---fail------] $CREATE_AZ_POSTGRES_DB_PASSWORD_SECRET"
    exit 2
fi

# Copying YAML Files from 'aks/apps/springboot/' to 'deploy/'.
COPY_YAML_FILES=$(cp -r aks/apps/springboot/* deploy)

if [ $? -eq 0 ]; then
    echo "[---success---] Copied all of the YAML files in [aks/apps/springboot/] to [deploy/]."
else
    echo "[---fail------] Unable to copy all of the YAML files in [aks/apps/springboot/] to [deploy]."
    echo "[---fail------] $COPY_YAML_FILES"
    exit 2
fi

# Replacing variables with their required values for all YAML files in 'target/k8s'.
find deploy/ -type f -name '*.yaml' -exec sed -i -e "s/{NAMESPACE}/$NAMESPACE/g" {} \;

if [ $? -eq 0 ]; then
    echo "[---success---] Replaced all variables with their required values for all YAML files in [deploy/]."
else
    echo "[---fail------] Failed to replace all variables with their required values for all YAML files in [deploy/]."
    exit 2
fi

# Applying the YAML Files to the AKS Cluster.
kubectl apply -f deploy

if [ $? -eq 0 ]; then
    echo "[---success---] Applied the YAML Files in [deploy/] to K8S Cluster [$K8S_CLUSTER_SP_USERNAME]."
else
    echo "[---fail------] Failed to apply the YAML Files in [deploy/] to K8S Cluster [$K8S_CLUSTER_SP_USERNAME]."
    exit 2
fi

# Deleting all the Pods in the Spring Namespace to force refresh of ConfigMap values.
DELETE_PODS=$(/usr/local/bin/kubectl delete --all pods --namespace=$NAMESPACE 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Deleted all Pods in Spring Namespace [$NAMESPACE] to force refresh of ConfigMap Values."
else
    echo "[---fail------] Failed to delete all Pods in Spring Namespace [$NAMESPACE] to force refresh of ConfigMap Values."
    echo "[---fail------] $DELETE_PODS"
    exit 2
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

# Deployment Complete.
echo "[---info------] Deployment of the Spring App to AKS Cluster [$K8S_CLUSTER_SP_USERNAME] is complete."