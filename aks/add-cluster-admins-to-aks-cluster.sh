#!/bin/bash

# Parse Script Parameters.
while getopts ":a:s:d:f:" opt; do
    case "${opt}" in
        a) # Base Name of the Kubernetes Deployment.
             BASE_NAME=${OPTARG}
             ;;
        s) # The Azure Subscription Fully Qualified Domain Name where the Kubernetes Cluster is being deployed to.
             AZURE_SUBSCRIPTION_FQDN=${OPTARG}
             ;;
        d) # The comma delimited list of E-mail Addresses of the Users being added to the cluster-admin Role in the Kubernetes Cluster.
             CLUSTER_ADMIN_EMAIL_ADDRESSES=${OPTARG}
             ;;
        f) # The Azure Location where the Kubernetes Cluster is being deployed.
             AZURE_LOCATION=${OPTARG}
             ;;
        \?) # Unrecognised option - show help.
            echo -e \\n"Option [-${BOLD}$OPTARG${NORM}] is not allowed. All Valid Options are listed below:"
            echo -e "-a BASE_NAME                       - The Base Name of the Kubernetes Deployment."
            echo -e "-f AZURE_SUBSCRIPTION_FQDN         - The Azure Subscription Fully Qualified Domain Name where the Kubernetes Cluster is being deployed to."
            echo -e "-d CLUSTER_ADMIN_EMAIL_ADDRESSES   - The comma delimited list of E-mail Addresses of the Users being added to the cluster-admin Role in the Kubernetes Cluster."
            echo -e "-f AZURE_LOCATION                  - The Azure Location where the Kubernetes Cluster is being deployed."
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

if [ -z "${AZURE_SUBSCRIPTION_FQDN}" ]; then
    echo "[$(date -u)][---fail---] The Azure Subscription Fully Qualified Domain Name where the Kubernetes Cluster is being deployed to must be provided."
    exit 2
fi

if [ -z "${CLUSTER_ADMIN_EMAIL_ADDRESSES}" ]; then
    echo "[$(date -u)][---fail---] The comma delimited list of E-mail Addresses of the Users being added to the cluster-admin Role in the Kubernetes Cluster must be provided."
    exit 2
fi

if [ -z "${AZURE_LOCATION}" ]; then
    echo "[$(date -u)][---fail---] The Azure Location where to deploy the Kubernetes Cluster must be provided."
    exit 2
fi

# Static Variables.
K8S_CLUSTER_SP_USERNAME="${BASE_NAME}"


# Downloading the Kubernetes cluster-admin 'kubeconfig' from the Kubernetes Cluster.
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

# Configuring the Host to connect to the Kubernetes Cluster. 
export KUBECONFIG="./cluster-admin-kubeconfig"

if [ $? -eq 0 ]; then
    echo "[---success---] The Host is now targeting K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
else
    echo "[---fail------] Failed to configure the Host to target K8s Cluster [$K8S_CLUSTER_SP_USERNAME]."
    exit 2
fi

# Replacing the comma delimiter with '\n' for the E-Mail Addresses to add as cluster-admin(s) to the Kubernetes Cluster.
CLUSTER_ADMIN_EMAIL_ADDRESSES=$(echo $CLUSTER_ADMIN_EMAIL_ADDRESSES | tr ',' '\n')

# Granting the E-Mail Addresses cluster-admin access to the Kubernetes Cluster.
for EMAIL_ADDRESS in $CLUSTER_ADMIN_EMAIL_ADDRESSES
do

    # Parsing out the Domain Name of the E-Mail Address and comparing it to the target Azure Subscription.
    EMAIL_ADDRESS_FQDN=$(echo ${EMAIL_ADDRESS#*@})
    EMAIL_USERNAME=$(echo ${EMAIL_ADDRESS%%@*})

    # Adding in the User if they are a Member of the Azure Subscription.
    if [ "$EMAIL_ADDRESS_FQDN" == "$AZURE_SUBSCRIPTION_FQDN" ]; then
        echo "[---info------] [$EMAIL_ADDRESS] is a Member of Azure Subscription [$AZURE_SUBSCRIPTION_FQDN]."

        # Retrieving the AAD User's ObjectId from Azure Active Directory.
        AAD_USER_OBJECT_ID=$(az ad user show --id $EMAIL_ADDRESS 2>&1 | jq '.objectId' | tr -d '"')

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the AAD ObjectId [$AAD_USER_OBJECT_ID] using UPN [$EMAIL_ADDRESS]."
        else
            echo "[---fail------] Failed to retrieve the AAD ObjectId using UPN [$EMAIL_ADDRESS]."
            echo "[---fail------] $AAD_USER_OBJECT_ID"
            exit 2
        fi

        # Creating a copy of 'cluster-admin-template.yaml' for the User being added as a cluster-admin.
        cp aks/k8s-rbac-templates/cluster-admin-template.yaml $EMAIL_ADDRESS-cluster-admin-template.yaml

        if [ $? -eq 0 ]; then
            echo "[---success---] Created a Copy of [cluster-admin-template.yaml] called [$EMAIL_ADDRESS-cluster-admin-template.yaml]."
        else
            echo "[---fail------] Unable to create a Copy of [cluster-admin-template.yaml] called [$EMAIL_ADDRESS-cluster-admin-template.yaml]."
            exit 2
        fi

        # Adding the the E-mail Address and AAD User Object ID to the User's Template File.
        sed -i -e "s/{EMAIL_ADDRESS}/$EMAIL_ADDRESS/g" $EMAIL_ADDRESS-cluster-admin-template.yaml
        sed -i -e "s/{AAD_USER_OBJECT_ID}/$AAD_USER_OBJECT_ID/g" $EMAIL_ADDRESS-cluster-admin-template.yaml

        if [ $? -eq 0 ]; then
            echo "[---success---] Added [$EMAIL_ADDRESS] and [$AAD_USER_OBJECT_ID] to [$EMAIL_ADDRESS-cluster-admin-template.yaml]."
        else
            echo "[---fail------] Unable to add [$EMAIL_ADDRESS] and [$AAD_USER_OBJECT_ID] to [$EMAIL_ADDRESS-cluster-admin-template.yaml]"
            echo "[---fail------] $CLUSTER_ADMIN_CRB"
            exit 2
        fi

        # Adding the User to the Cluster Admin Role on the Kubernetes Cluster.
        ADD_USER_TO_CLUSTER=$(kubectl apply -f $EMAIL_ADDRESS-cluster-admin-template.yaml)

        if [ $? -eq 0 ]; then
            echo "[---success---] Added [$EMAIL_ADDRESS] to the Cluster Admin Role on the K8s Cluster."
        else
            echo "[---fail------] Failed to add [$EMAIL_ADDRESS] to the Cluster Admin Role on the K8s Cluster."
            echo "[---fail------] $ADD_USER_TO_CLUSTER"
            exit 2
        fi
    else
        # Adding in User if they are a Guest in the Azure Subscription.
        echo "[---info------] [$EMAIL_ADDRESS] is a Guest in Azure Subscription [$AZURE_SUBSCRIPTION_FQDN]."
        echo "[---info------] Creating a usable UPN value of [$EMAIL_ADDRESS] to use to search for the user in Azure Subscription [$AZURE_SUBSCRIPTION_FQDN]."

        # Crafting the UPN Value used for Guest Users of an Azure Active Directory Subscription.
        NEW_UPN_VALUE="${EMAIL_USERNAME}_${EMAIL_ADDRESS_FQDN}#EXT#@${AZURE_SUBSCRIPTION_FQDN}"
        echo "[---info------] New UPN Value [$NEW_UPN_VALUE] for [$EMAIL_ADDRESS]."

        # Retrieving the AAD User's ObjectId from Azure Active Directory.
        AAD_USER_OBJECT_ID=$(az ad user show --id $NEW_UPN_VALUE | jq '.objectId' | tr -d '"')

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the AAD ObjectId [$AAD_USER_OBJECT_ID] using UPN [$NEW_UPN_VALUE]."
        else
            echo "[---fail------] Failed to retrieve the AAD ObjectId using UPN [$NEW_UPN_VALUE]."
            echo "[---fail------] $AAD_USER_OBJECT_ID"
            exit 2
        fi

        # Creating a copy of 'cluster-admin-template.yaml' for the User being added as a cluster-admin.
        cp aks/k8s-rbac-templates/cluster-admin-template.yaml $EMAIL_ADDRESS-cluster-admin-template.yaml

        if [ $? -eq 0 ]; then
            echo "[---success---] Created a Copy of [cluster-admin-template.yaml] called [$EMAIL_ADDRESS-cluster-admin-template.yaml]."
        else
            echo "[---fail------] Unable to create a Copy of [cluster-admin-template.yaml] called [$EMAIL_ADDRESS-cluster-admin-template.yaml]."
            exit 2
        fi

        # Adding the the E-mail Address and AAD User Object ID to the User's Template File.
        sed -i -e "s/{EMAIL_ADDRESS}/$EMAIL_ADDRESS/g" $EMAIL_ADDRESS-cluster-admin-template.yaml
        sed -i -e "s/{AAD_USER_OBJECT_ID}/$AAD_USER_OBJECT_ID/g" $EMAIL_ADDRESS-cluster-admin-template.yaml

        if [ $? -eq 0 ]; then
            echo "[---success---] Added [$EMAIL_ADDRESS] and [$AAD_USER_OBJECT_ID] to [$EMAIL_ADDRESS-cluster-admin-template.yaml]."
        else
            echo "[---fail------] Unable to add [$EMAIL_ADDRESS] and [$AAD_USER_OBJECT_ID] to [$EMAIL_ADDRESS-cluster-admin-template.yaml]"
            echo "[---fail------] $CLUSTER_ADMIN_CRB"
            exit 2
        fi

        # Adding the User to the Cluster Admin Role on the Kubernetes Cluster.
        ADD_USER_TO_CLUSTER=$(kubectl apply -f $EMAIL_ADDRESS-cluster-admin-template.yaml)

        if [ $? -eq 0 ]; then
            echo "[---success---] Added [$EMAIL_ADDRESS] to the Cluster Admin Role on the K8s Cluster."
        else
            echo "[---fail------] Failed to add [$EMAIL_ADDRESS] to the Cluster Admin Role on the K8s Cluster."
            echo "[---fail------] $ADD_USER_TO_CLUSTER"
            exit 2
        fi
    fi
done

# Removing all 'cluster-admin-template.yaml' files from the Host.
rm -f "*cluster-admin-template.yaml"

if [ $? -eq 0 ]; then
    echo "[---success---] Removed all [cluster-admin-template.yaml] files from the Host."
else
    echo "[---fail------] Failed to remove all [cluster-admin-template.yaml] files from the Host."
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

# Process Complete
echo "[---info------] Process of adding new [cluster-admin] Users to AKS Cluster [$K8S_CLUSTER_SP_USERNAME] is complete."