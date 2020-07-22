#!/bin/bash

# This script is responsible for deploying the Azure Key Vaults for PostgreSQL Server Instance used by the AKS Cluster.

# Parse Script Parameters.
while getopts "a:s:" opt; do
    case "${opt}" in
        a) # Base Name of the Kubernetes Cluster.
             BASE_NAME=${OPTARG}
             ;;
        s) # Azure Location where the Key Vault for the PostgreSQL Server is being deployed.
             AZURE_LOCATION=${OPTARG}
             ;;
        \?) # Unrecognised option - show help.
            echo -e \\n"Option [-${BOLD}$OPTARG${NORM}] is not allowed. All Valid Options are listed below:"
            echo -e "-a BASE_NAME                       - The Base Name of the Kubernetes Cluster."
            echo -e "-h AZURE_LOCATION                  - The Azure Location where the Key Vault for the PostgreSQL Server is being deployed."
            echo -e ""
            echo -e "An Example of how to use this script is shown below:"
            echo -e "./deploy-postgresql-kv.sh -a iam-k8s-ryani -s westeurope\\n"
            exit 2
            ;;
    esac
done
shift $((OPTIND-1))

# Verifying the Script Parameters Values exist.
if [ -z "${BASE_NAME}" ]; then
    echo "The Base Name of the Kubernetes Cluster must be provided."
    exit 2
fi

if [ -z "${AZURE_LOCATION}" ]; then
    echo "The Azure Location where the Key Vault for the PostgreSQL Server is being deployed must be provided."
    exit 2
fi


# Static Variables
POSTGRES_KV_RG_NAME="${BASE_NAME}-psql-kv"
POSTGRES_SRV_KV_NAME="${BASE_NAME}-psql-srv"
POSTGRES_DBS_KV_NAME="${BASE_NAME}-psql-dbs"
POSTGRES_DB_KV_NAMES="${BASE_NAME}-psql-srv,${BASE_NAME}-psql-dbs"


# Checking to see if the PostgreSQL Server Key Vault Resource Group already exists.
RESOURCE_GROUP_CHECK=$(/usr/bin/az group list \
| jq --arg POSTGRES_KV_RG_NAME "$POSTGRES_KV_RG_NAME" '.[] | select(.name == $POSTGRES_KV_RG_NAME).name' \
| tr -d '"')

if [ ! -z "${RESOURCE_GROUP_CHECK}" ]; then
    echo "[---info------] Resource Group [$POSTGRES_KV_RG_NAME] already exists."
else
    echo "[---info------] Resource Group [$POSTGRES_KV_RG_NAME] not found."

    # Creating the PostgreSQL Server Key Vault Resource Group.
    CREATE_RESOURCE_GROUP=$(/usr/bin/az group create \
    --name $POSTGRES_KV_RG_NAME \
    --location $AZURE_LOCATION 2>&1 1>/dev/null)

    if [ $? -eq 0 ]; then
        echo "[---success---] Created the Resource Group [$POSTGRES_KV_RG_NAME]."
    else
        echo "[---fail------] Failed to create the Resource Group [$POSTGRES_KV_RG_NAME]."
        echo "[---fail------] $CREATE_RESOURCE_GROUP"
        exit 2
    fi
fi

# Replacing the comma-delimiter with '\n' for the entries.
POSTGRES_DB_KV_NAMES=$(echo $POSTGRES_DB_KV_NAMES | tr ',' '\n')

# Deploying the Key Vaults.
for DB_KV_NAME in $POSTGRES_DB_KV_NAMES; do

    # Checking to see if the Key Vault already exists.
    KEY_VAULT_CHECK=$(/usr/bin/az keyvault list \
    | jq --arg DB_KV_NAME "$DB_KV_NAME" '.[] | select(.name == $DB_KV_NAME).name' \
    | tr -d '"')

    if [ ! -z "${KEY_VAULT_CHECK}" ]; then
        echo "[---info------] Key Vault [$DB_KV_NAME] already exists."
    else
        echo "[---info------] Key Vault [$DB_KV_NAME] not found."

        # Check to see if Key Vault is soft-deleted.
        CHECK_SOFT_DELETE=$(az keyvault list-deleted \
        | jq --arg DB_KV_NAME "$DB_KV_NAME" '.[].name | select(.|test("^"+$DB_KV_NAME+"$"))' | tr -d '"')

        if [[ "$CHECK_SOFT_DELETE" == "$DB_KV_NAME" ]]; then
            echo "[---info------] Key Vault [$DB_KV_NAME] found soft-deleted."

            # Retrieving the Location of the soft-deleted Key Vault.
            DB_KV_LOCATION=$(az keyvault list-deleted \
            | jq --arg DB_KV_NAME "$DB_KV_NAME" '.[] | select(.name|test("^"+$DB_KV_NAME+"$")).properties.location' | tr -d '"')

            if [ $? -eq 0 ]; then
                echo "[---success---] Retrieved the Location [$DB_KV_LOCATION] of soft-deleted Key Vault [$DB_KV_NAME]."
            else
                echo "[---fail------] Failed to retrieve the Location [$DB_KV_LOCATION] of soft-deleted Key Vault [$DB_KV_NAME]."
                echo "[---fail------] $DB_KV_LOCATION."
                exit 2
            fi

            # Purging the soft-deleted Key Vault.
            PURGE_KV=$(az keyvault purge \
            --name $DB_KV_NAME \
            --location $DB_KV_LOCATION)

            if [ $? -eq 0 ]; then
                echo "[---success---] Purged soft-deleted Key Vault [$DB_KV_NAME]."
            else
                echo "[---fail------] Failed to purge soft-deleted Key Vault [$DB_KV_NAME]."
                echo "[---fail------] $PURGE_KV."
                exit 2
            fi
        else
            echo "[---info------] Key Vault [$DB_KV_NAME] was not found soft-deleted."
        fi

        # Creating the Key Vault.
        CREATE_KEY_VAULT=$(/usr/bin/az keyvault create \
        --name "$DB_KV_NAME" \
        --resource-group "$POSTGRES_KV_RG_NAME" \
        --enabled-for-deployment \
        --enabled-for-template-deployment 2>&1 1>/dev/null)

        if [ $? -eq 0 ]; then
            echo "[---success---] Deployed the Key Vault [$DB_KV_NAME] to Resource Group [$POSTGRES_KV_RG_NAME]."
        else
            echo "[---fail------] Failed to deploy the Key Vault [$DB_KV_NAME] to Resource Group [$POSTGRES_KV_RG_NAME]."
            echo "[---fail------] $CREATE_KEY_VAULT."
            exit 2
        fi
    fi
done

# Deployment Complete
echo "[---info------] Deployment of the PostgreSQL Server Key Vaults to Resource Group [$POSTGRES_KV_RG_NAME] is complete."