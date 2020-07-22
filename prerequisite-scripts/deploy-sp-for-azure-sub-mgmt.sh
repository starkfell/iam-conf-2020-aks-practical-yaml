#!/bin/bash
: '
Name:             deploy-sp-for-azure-sub-mgmt.sh
Author:           Ryan Irujo

Description:      This Script is responsible for deploying the Management Service Principal for deploying and managing Kubernetes Clusters in an 
                  Azure Subscription. After the Service Principal is successfully created, a new Resource Group is created in the target 
                  Azure Subscription where the Service Principal credentials are securely stored in a newly deployed Azure Key Vault.

                  - User must be either a Co-Administrator or Owner of the target Azure Subscription.
                  - User must be a Global Administrator (Cloud Application Administrator) of the target Azure Active Directory associated 
                    with the Azure Subscription.

Synopsis:         Once this script is launched, the following actions will occur:

                  - Logging in to Azure the Azure Subscription.
                  - Set the Azure Subscription to work with.
                  - Checking if the Service Principal exists.
                      - Creating the Service Principal and scoping it to the Azure Subscription.
                      - Updating the Azure App associated with the Service Principal with the resource access definitions in [azure-sub-mgmt-manifest.json].
                      - Waiting 30 seconds to allow the resource access definitions to propagate from [azure-sub-mgmt-manifest.json].
                      - Granting Admin Consent on the resource access definitions for the Azure App.
                  - Checking to see if the Resource Group already exists.
                      - Creating the Resource Group.
                  - Checking to see if the Key Vault already exists.
                      - Creating the Key Vault.
                  - Adding the Service Principal Username to the Azure Key Vault.
                  - Adding the Service Principal Password to the Azure Key Vault.
                  - Deployment Complete.


Additional Notes: - Make sure to run this script in the same Directory where the [azure-sub-mgmt-manifest.json] file is!
                  - Make sure to add any AAD Users to the Access Policies of the Azure Key Vault of its secrets as required.
                    For example, if an AAD User needs to create a Service Connection in Azure DevOps, they are going to need
                    [get] and [list] access to the Secrets in the Azure Key Vault!


Syntax:

./deploy-sp-for-azure-sub-mgmt.sh \
-a "AZURE_SUBSCRIPTION_TENANT_ID" \
-s "AZURE_SUBSCRIPTION_ID" \
-d "SERVICE_PRINCIPAL_NAME" \
-f "AZURE_LOCATION" \
-g "RESOURCE_GROUP_NAME" \
-h "KEY_VAULT_NAME"

Example:

./deploy-sp-for-azure-sub-mgmt.sh \
-a "7f24e4c5-12f1-4047-afa1-c15d6927e745" \
-s "84f065f5-e37a-4127-9c82-0b1ecd57a652" \
-d "k8s-cluster-mgmt-sp" \
-f "westeurope" \
-g "k8s-cluster-mgmt" \
-h "k8s-cluster-mgmt"

'

# Parse Script Parameters.
while getopts ":a:s:d:f:g:h:" opt; do
    case "${opt}" in
        a) # The Azure Subscription Tenant ID where the Service Principal is being created.
             AZURE_SUBSCRIPTION_TENANT_ID=${OPTARG}
             ;;
        s) # The Azure Subscription ID where the Service Principal is being created.
             AZURE_SUBSCRIPTION_ID=${OPTARG}
             ;;
        d) # The Name of the Service Principal being created.
             SERVICE_PRINCIPAL_NAME=${OPTARG}
             ;;
        f) # The Azure Location where the Resource Group will be deployed.
             AZURE_LOCATION=${OPTARG}
             ;;
        g) # The Name of the Resource Group being created and where the Azure Key Vault will be deployed.
             RESOURCE_GROUP_NAME=${OPTARG}
             ;;
        h) # The Name of the Azure Key Vault being deployed.
             KEY_VAULT_NAME=${OPTARG}
             ;;
        \?) # Unrecognised option - show help.
            echo -e \\n"Option [-${BOLD}$OPTARG${NORM}] is not allowed. All Valid Options are listed below:"
            echo -e "-a AZURE_SUBSCRIPTION_TENANT_ID  - The Azure Subscription Tenant ID where the Service Principal is being created."
            echo -e "-s AZURE_SUBSCRIPTION_ID         - The Azure Subscription ID where the Service Principal is being created."
            echo -e "-d SERVICE_PRINCIPAL_NAME        - The Name of the Service Principal being created."
            echo -e "-f AZURE_LOCATION                - The Azure Location where the Resource Group will be deployed."
            echo -e "-g RESOURCE_GROUP_NAME           - The Name of the Resource Group being created and where the Azure Key Vault will be deployed."
            echo -e "-h KEY_VAULT_NAME                - The Name of the Azure Key Vault being deployed."
            echo -e ""
            echo -e "Additional script Syntax is in the comments section of this script."
            exit 2
            ;;
    esac
done
shift $((OPTIND-1))

# Verifying the Script Parameters Values exist.
if [ -z "${AZURE_SUBSCRIPTION_TENANT_ID}" ]; then
    echo "[---fail------] The Azure Subscription Tenant ID where the Service Principal is being created must be provided."
    exit 2
fi

if [ -z "${AZURE_SUBSCRIPTION_ID}" ]; then
    echo "[---fail------] The Azure Subscription ID where the Service Principal is being created must be provided."
    exit 2
fi

if [ -z "${SERVICE_PRINCIPAL_NAME}" ]; then
    echo "[---fail------] The Name of the Service Principal being created must be provided."
    exit 2
fi

if [ -z "${AZURE_LOCATION}" ]; then
    echo "[---fail------] The Azure Location where the Resource Group will be deployed must be provided."
    exit 2
fi

if [ -z "${RESOURCE_GROUP_NAME}" ]; then
    echo "[---fail------] he Name of the Resource Group being created and where the Azure Key Vault will be deployed must be provided."
    exit 2
fi

if [ -z "${KEY_VAULT_NAME}" ]; then
    echo "[---fail------] The Name of the Azure Key Vault being deployed must be provided."
    exit 2
fi

# Logging in to Azure the Azure Subscription.
az login --tenant $AZURE_SUBSCRIPTION_TENANT_ID > /dev/null 2>&0

if [ $? -eq 0 ]; then
    echo "[---success---] Logged into Azure."
else
    echo "[---fail------] Failed to login to Azure."
    exit 2
fi

# Set the Azure Subscription to work with.
az account set -s $AZURE_SUBSCRIPTION_ID > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "[---success---] Azure CLI set to Azure Subscription [$AZURE_SUBSCRIPTION_ID]."
else
    echo "[---fail------] Failed to set Azure CLI to Azure Subscription [$AZURE_SUBSCRIPTION_ID]."
    exit 2
fi

# Retrieving the name of the Azure Subscription.
AZURE_SUBSCRIPTION_NAME=$(az account show \
--query name \
--output tsv 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] The Name of the Azure Subscription is [$AZURE_SUBSCRIPTION_NAME]."
else
    echo "[---fail------] Failed to retrieve the Name of the Azure Subscription."
    echo "[---fail------] $AZURE_SUBSCRIPTION_NAME."
    exit 2
fi

# Checking if the Service Principal exists.
SERVICE_PRINCIPAL_CHECK=$(az ad sp list --all 2>&1 \
| jq --arg SERVICE_PRINCIPAL_NAME "$SERVICE_PRINCIPAL_NAME" '.[] | select(.appDisplayName == $SERVICE_PRINCIPAL_NAME).appDisplayName' \
| tr -d '"')

if [ ! -z "${SERVICE_PRINCIPAL_CHECK}" ]; then
    echo "[---info------] The Service Principal [$SERVICE_PRINCIPAL_NAME] already exists."
else
    echo "[---info------] The Service Principal [$SERVICE_PRINCIPAL_NAME] was not found."

    # Creating the Service Principal and scoping it to the Azure Subscription.
    CREATE_SERVICE_PRINCIPAL=$(az ad sp create-for-rbac \
    --role="Owner" \
    --name="http://$SERVICE_PRINCIPAL_NAME" \
    --years 50 \
    --scopes="/subscriptions/$AZURE_SUBSCRIPTION_ID" 2>&1)

    if [ $? -eq 0 ]; then
        echo "[---success---] Created Service Principal [$SERVICE_PRINCIPAL_NAME]"
    else
        echo "[---fail------] Failed to create Service Principal [$SERVICE_PRINCIPAL_NAME]."
        echo "[---fail------] $CREATE_SERVICE_PRINCIPAL"
        exit 2
    fi

    # Updating the Azure App associated with the Service Principal with the resource access definitions in 'azure-sub-mgmt-manifest.json'.
    UPDATE_SP_AZURE_APP_MANIFEST=$(az ad app update \
    --id "http://$SERVICE_PRINCIPAL_NAME" \
    --required-resource-accesses "./azure-sub-mgmt-manifest.json" 2>&1)

    if [ $? -eq 0 ]; then
        echo "[---success---] Updated Azure App [$SERVICE_PRINCIPAL_NAME] with the 'azure-sub-mgmt-manifest'."
    else
        echo "[---fail------] Failed to update Azure App [$SERVICE_PRINCIPAL_NAME] with the 'azure-sub-mgmt-manifest.json'."
        echo "[---fail------] $UPDATE_SP_AZURE_APP_MANIFEST"
        exit 2
    fi
fi

# Checking to see if the Resource Group already exists.
RESOURCE_GROUP_CHECK=$(az group list \
| jq --arg RESOURCE_GROUP_NAME "$RESOURCE_GROUP_NAME" '.[] | select(.name == $RESOURCE_GROUP_NAME).name' \
| tr -d '"')

if [ ! -z "${RESOURCE_GROUP_CHECK}" ]; then
    echo "[---info------] Resource Group [$RESOURCE_GROUP_NAME] already exists."
else
    echo "[---info------] Resource Group [$RESOURCE_GROUP_NAME] not found."

    # Creating the Resource Group.
    CREATE_RESOURCE_GROUP=$(az group create \
    --name $RESOURCE_GROUP_NAME \
    --location $AZURE_LOCATION 2>&1 1>/dev/null)

    if [ $? -eq 0 ]; then
        echo "[---success---] Created the Resource Group [$RESOURCE_GROUP_NAME]."
    else
        echo "[---fail------] Failed to create the Resource Group [$RESOURCE_GROUP_NAME]."
        echo "[---fail------] $CREATE_RESOURCE_GROUP"
        exit 2
    fi
fi

# Checking to see if the Key Vault already exists.
KEY_VAULT_CHECK=$(az keyvault list \
| jq --arg KEY_VAULT_NAME "$KEY_VAULT_NAME" '.[] | select(.name == $KEY_VAULT_NAME).name' \
| tr -d '"')

if [ ! -z "${KEY_VAULT_CHECK}" ]; then
    echo "[---info------] Key Vault [$KEY_VAULT_NAME] already exists."
else
    echo "[---info------] Key Vault [$KEY_VAULT_NAME] not found."

    # Check to see if Key Vault is soft-deleted.
    CHECK_SOFT_DELETE=$(az keyvault list-deleted \
    | jq --arg KEY_VAULT_NAME "$KEY_VAULT_NAME" '.[].name | select(.|test("^"+$KEY_VAULT_NAME+"$"))' | tr -d '"')

    if [[ "$CHECK_SOFT_DELETE" == "$KEY_VAULT_NAME" ]]; then
        echo "[---info------] Key Vault [$KEY_VAULT_NAME] found soft-deleted."

        # Retrieving the Location of the soft-deleted Key Vault.
        KV_LOCATION=$(az keyvault list-deleted \
        | jq --arg KEY_VAULT_NAME "$KEY_VAULT_NAME" '.[] | select(.name|test("^"+$KEY_VAULT_NAME+"$")).properties.location' | tr -d '"')

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the Location [$KV_LOCATION] of soft-deleted Key Vault [$KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to retrieve the Location [$KV_LOCATION] of soft-deleted Key Vault [$KEY_VAULT_NAME]."
            echo "[---fail------] $KV_LOCATION."
            exit 2
        fi

        # Purging the soft-deleted Key Vault.
        PURGE_KV=$(az keyvault purge \
        --name $KEY_VAULT_NAME \
        --location $KV_LOCATION)

        if [ $? -eq 0 ]; then
            echo "[---success---] Purged soft-deleted Key Vault [$KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to purge soft-deleted Key Vault [$KEY_VAULT_NAME]."
            echo "[---fail------] $PURGE_KV."
            exit 2
        fi
    else
        echo "[---info------] Key Vault [$KEY_VAULT_NAME] was not found soft-deleted."
    fi

    # Creating the Key Vault.
    CREATE_KEY_VAULT=$(az keyvault create \
    --name "$KEY_VAULT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --enabled-for-deployment \
    --enabled-for-template-deployment 2>&1 1>/dev/null)

    if [ $? -eq 0 ]; then
        echo "[---success---] Deployed Key Vault [$KEY_VAULT_NAME] to Resource Group [$RESOURCE_GROUP_NAME]."
    else
        echo "[---fail------] Failed to deploy Key Vault [$KEY_VAULT_NAME] to Resource Group [$RESOURCE_GROUP_NAME]."
        echo "[---fail------] $CREATE_KEY_VAULT."
        exit 2
    fi
fi

# Adding the Service Principal Application ID to the Azure Key Vault.
SERVICE_PRINCIPAL_APP_ID=$(echo "${CREATE_SERVICE_PRINCIPAL}" | sed -n '/^{$/,$p' | jq '.appId' | tr -d '"')

ADD_TO_VAULT=$(az keyvault secret set \
--name "$SERVICE_PRINCIPAL_NAME-app-id" \
--vault-name "$KEY_VAULT_NAME" \
--value "$SERVICE_PRINCIPAL_APP_ID" \
--output none 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Service Principal Application ID [$SERVICE_PRINCIPAL_APP_ID] added to Key Vault [$KEY_VAULT_NAME]."
else
    echo "[---fail------] Failed to add Service Principal Application ID [$SERVICE_PRINCIPAL_APP_ID] to Key Vault [$KEY_VAULT_NAME]."
    echo "[---fail------] $ADD_TO_VAULT"
    exit 2
fi

# Adding the Service Principal Username to the Azure Key Vault.
SERVICE_PRINCIPAL_USERNAME=$(echo "${CREATE_SERVICE_PRINCIPAL}" | sed -n '/^{$/,$p' | jq '.name' | tr -d '"')

ADD_TO_VAULT=$(az keyvault secret set \
--name "$SERVICE_PRINCIPAL_NAME-username" \
--vault-name "$KEY_VAULT_NAME" \
--value "$SERVICE_PRINCIPAL_USERNAME" \
--output none 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Service Principal Username [$SERVICE_PRINCIPAL_USERNAME] added to Key Vault [$KEY_VAULT_NAME]."
else
    echo "[---fail------] Failed to add Service Principal Username [$SERVICE_PRINCIPAL_USERNAME] to Key Vault [$KEY_VAULT_NAME]."
    echo "[---fail------] $ADD_TO_VAULT"
    exit 2
fi

# Adding the Service Principal Password to the Azure Key Vault.
SERVICE_PRINCIPAL_PASSWORD=$(echo "${CREATE_SERVICE_PRINCIPAL}" | sed -n '/^{$/,$p' | jq '.password' | tr -d '"')

ADD_TO_VAULT=$(az keyvault secret set \
--name "$SERVICE_PRINCIPAL_NAME-password" \
--vault-name "$KEY_VAULT_NAME" \
--value "$SERVICE_PRINCIPAL_PASSWORD" \
--output none 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Service Principal Password for [$SERVICE_PRINCIPAL_NAME] added to Key Vault [$KEY_VAULT_NAME]."
else
    echo "[---fail------] Failed to add Service Principal Password for [$SERVICE_PRINCIPAL_NAME] to Key Vault [$KEY_VAULT_NAME]."
    echo "[---fail------] $ADD_TO_VAULT"
    exit 2
fi

# Waiting 30 seconds to allow the resource access definitions to propagate from'azure-sub-mgmt-manifest.json'..
echo "[---success---] Waiting 30 seconds to allow the resource access definitions to propagate from'azure-sub-mgmt-manifest.json'."
sleep 30

# Granting Admin Consent on the resource access definitions for the Azure App.
GRANT_ADMIN_CONSENT_TO_AZURE_APP=$(az ad app permission admin-consent \
--id http://$SERVICE_PRINCIPAL_NAME 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Granted Admin Consent on the resource access definition for Azure App [$SERVICE_PRINCIPAL_NAME]."
else
    echo "[---fail------] Failed to grant Admin Consent on the resource access definition for Azure App [$SERVICE_PRINCIPAL_NAME]."
    echo "[---fail------] $GRANT_ADMIN_CONSENT_TO_AZURE_APP"
    echo "[---fail------] Login to the Azure Portal and Grant this access manually under API Permissions in the App Registration."
    exit 2
fi

echo "[---info------] Service Connection Information to use is shown below:"
echo "[---info------] "
echo "[---info------] Subscription Id:         [$AZURE_SUBSCRIPTION_ID]"
echo "[---info------] Subscription Name:       [$AZURE_SUBSCRIPTION_NAME]"
echo "[---info------] Service Principal Id:    [$SERVICE_PRINCIPAL_APP_ID]"
echo "[---info------] Service Principal Key:   [$SERVICE_PRINCIPAL_PASSWORD]"
echo "[---info------] Tenant Id:               [$AZURE_SUBSCRIPTION_TENANT_ID]"
echo "[---info------] Service Connection Name: [$SERVICE_PRINCIPAL_NAME]"
echo "[---info------] "


# Deployment Complete
az account clear

if [ $? -eq 0 ]; then
    echo "[---success---] Logged out of the Azure Subscription [$AZURE_SUBSCRIPTION_ID]."
else
    echo "[---fail------] Failed to logout of Azure Subscription [$AZURE_SUBSCRIPTION_ID]."
    exit 2
fi

echo "[---success---] Deployment of Service Principal [$SERVICE_PRINCIPAL_NAME] in Azure Subscription [$AZURE_SUBSCRIPTION_ID] is complete."