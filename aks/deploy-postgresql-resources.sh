#!/bin/bash

# This script is responsible for deploying the Postgres Server and multiple Databases, if desired.
# The Username of each Postgres Database is the same as the Database Name and is granted full rights to it.

# Parse Script Parameters.
while getopts "a:s:d:f:g:" opt; do
    case "${opt}" in
        a) # Base Name of the Kubernetes Cluster.
             BASE_NAME=${OPTARG}
             ;;
        s) # External IP Addresses that need access to the Azure Resources.
             EXTERNAL_IP_ADDRESSES=${OPTARG}
             ;;
        d) # The Postgres Server Admin Username.
             POSTGRES_SERVER_ADMIN_USERNAME=${OPTARG}
             ;;
        f) # The Names of the Postgres Databases being deployed.
             POSTGRES_DB_NAMES=${OPTARG}
             ;;
        g) # Azure Location where the Postgres Server is being deployed.
             AZURE_LOCATION=${OPTARG}
             ;;
        \?) # Unrecognised option - show help.
            echo -e \\n"Option [-${BOLD}$OPTARG${NORM}] is not allowed. All Valid Options are listed below:"
            echo -e "-a BASE_NAME                       - The Base Name of the Kubernetes Cluster."
            echo -e "-s EXTERNAL_IP_ADDRESSES           - The External IP Addresses that need access to the Azure Resources."
            echo -e "-d POSTGRES_SERVER_ADMIN_USERNAME  - The Postgres Server Admin Username."
            echo -e "-f POSTGRES_DB_NAMES               - The Names of the Postgres Databases being deployed."
            echo -e "-g AZURE_LOCATION                  - The Azure Location where the Postgres Server is being deployed."
            echo -e ""
            echo -e "An Example of how to use this script is shown below:"
            echo -e "./deploy-postgresql-resources.sh -a iam-k8s-spring -s 213.47.155.102 -d pgadmin -f springdb -g westeurope\\n"
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

if [ -z "${EXTERNAL_IP_ADDRESSES}" ]; then
    echo "The External IP Addresses that need access to the Azure Resources must be provided."
    exit 2
fi

if [ -z "${POSTGRES_SERVER_ADMIN_USERNAME}" ]; then
    echo "The Postgres Server Admin Username must be provided."
    exit 2
fi

if [ -z "${POSTGRES_DB_NAMES}" ]; then
    echo "The Names of the Postgres Databases being deployed must be provided."
    exit 2
fi

if [ -z "${AZURE_LOCATION}" ]; then
    echo "The Azure Location where the Postgres Server is being deployed must be provided."
    exit 2
fi

# Static Variables
K8S_CLUSTER_SP_USERNAME="${BASE_NAME}"
POSTGRES_SRV_RG_NAME="${BASE_NAME}-psql"
POSTGRES_SRV_NAME="${BASE_NAME}-psql"
POSTGRES_SRV_KV_NAME="${BASE_NAME}-psql-srv"
POSTGRES_DBS_KV_NAME="${BASE_NAME}-psql-dbs"


# Checking to see if the Kubernetes Database Resource Group already exists.
RESOURCE_GROUP_CHECK=$(/usr/bin/az group list \
| jq --arg POSTGRES_SRV_RG_NAME "$POSTGRES_SRV_RG_NAME" '.[] | select(.name == $POSTGRES_SRV_RG_NAME).name' \
| tr -d '"')

if [ ! -z "${RESOURCE_GROUP_CHECK}" ]; then
    echo "[---info------] Resource Group [$POSTGRES_SRV_RG_NAME] already exists."
else
    echo "[---info------] Resource Group [$POSTGRES_SRV_RG_NAME] not found."

    # Creating the Kubernetes Database Resource Group.
    CREATE_RESOURCE_GROUP=$(/usr/bin/az group create \
    --name $POSTGRES_SRV_RG_NAME \
    --location $AZURE_LOCATION 2>&1 1>/dev/null)

    if [ $? -eq 0 ]; then
        echo "[---success---] Created the Resource Group [$POSTGRES_SRV_RG_NAME]."
    else
        echo "[---fail------] Failed to create the Resource Group [$POSTGRES_SRV_RG_NAME]."
        echo "[---fail------] $CREATE_RESOURCE_GROUP"
        exit 2
    fi
fi

# Checking to see if the Azure Database for PostgresSQL Server already exists in the Azure Subscription.
POSTGRES_SERVER_CHECK=$(/usr/bin/az postgres server list \
--query "[].name" \
--output tsv)

if [[ "$POSTGRES_SRV_NAME" == "$POSTGRES_SERVER_CHECK" ]]; then
    echo "[---info------] The Postgres Server [$POSTGRES_SRV_NAME] already exists in the Azure Subscription."
else
    echo "[---info------] The Postgres Server [$POSTGRES_SRV_NAME] was not found in the Azure Subscription."

    # Generating a password for the Postgres Server Admin User.
    POSTGRES_SERVER_ADMIN_PASSWORD=$(cat /proc/sys/kernel/random/uuid 2>&1)

    if [ $? -eq 0 ]; then
        echo "[---success---] Generated a password for the Postgres Server Admin User."
    else
        echo "[---fail------] Failed to generate a password for the Postgres Server Admin User."
        echo "[---fail------] $POSTGRES_SERVER_ADMIN_PASSWORD"
        exit 2
    fi

    # Creating the Postgres Server in the Kubernetes Database Resource Group.
    CREATE_POSTGRES_SERVER=$(/usr/bin/az postgres server create \
    --name $POSTGRES_SRV_NAME \
    --admin-user $POSTGRES_SERVER_ADMIN_USERNAME \
    --admin-password "$POSTGRES_SERVER_ADMIN_PASSWORD" \
    --location $AZURE_LOCATION \
    --resource-group $POSTGRES_SRV_RG_NAME \
    --sku-name GP_Gen5_2 \
    --ssl-enforcement Disabled \
    --storage-size 51200 \
    --backup-retention 30 \
    --auto-grow enabled \
    --version 11 \
    --query userVisibleState \
    --output tsv)

    if [[ "$CREATE_POSTGRES_SERVER" == "Ready" ]]; then
        echo "[---success---] Created the Postgres Server [$POSTGRES_SRV_NAME] in Resource Group [$POSTGRES_SRV_RG_NAME]."
        echo "[---info------] SSL Enforcement is DISABLED on Postgres Server [$POSTGRES_SRV_NAME]."
        echo "[---info------] Make sure to turn on SSL Enforcement before using in Production!"
    else
        echo "[---fail------] Failed to create the Postgres Server [$POSTGRES_SRV_NAME] in Resource Group [$POSTGRES_SRV_RG_NAME]."
        echo "[---fail------] $CREATE_POSTGRES_SERVER"
        exit 2
    fi

    # Adding the Postgres Server Admin User Password to the Kubernetes Azure Key Vault.
    ADD_TO_VAULT=$(/usr/bin/az keyvault secret set \
    --name "$POSTGRES_SRV_NAME-acct-$POSTGRES_SERVER_ADMIN_USERNAME-password" \
    --vault-name "$POSTGRES_SRV_KV_NAME" \
    --value "$POSTGRES_SERVER_ADMIN_PASSWORD" \
    --output none 2>&1)

    if [ $? -eq 0 ]; then
        echo "[---success---] Added the Password for Postgres Server Admin User [$POSTGRES_SERVER_ADMIN_USERNAME] to Key Vault [$POSTGRES_SRV_KV_NAME]."
        echo "[---info------] Waiting 5 Seconds before continuing to let Key Vault [$POSTGRES_SRV_KV_NAME] Sync."
        sleep 5
    else
        echo "[---fail------] Failed to add the Password for Postgres Server Admin User [$POSTGRES_SERVER_ADMIN_USERNAME] to Key Vault [$POSTGRES_SRV_KV_NAME]."
        echo "[---fail------] $ADD_TO_VAULT"
        exit 2
    fi
fi

# Adding Firewall Rule to allow access to Azure Services.
ALLOW_AZURE_SERVICES=$(az postgres server firewall-rule create \
--name AllowAzureServices \
--server-name $POSTGRES_SRV_NAME \
--resource-group $POSTGRES_SRV_RG_NAME \
--start-ip-address 0.0.0.0 \
--end-ip-address 0.0.0.0 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Added IP Rule to allow access to Azure Services."
else
    echo "[---fail------] Failed to add IP Rule to allow access to Azure Services."
    echo "[---fail------] $ALLOW_AZURE_SERVICES"
    exit 2
fi

# Replacing the comma-delimiter with '\n' for the entries.
EXTERNAL_IP_ADDRESSES=$(echo $EXTERNAL_IP_ADDRESSES | tr ',' '\n')

# Deploying the Postgres Server Firewall IP Rules for External IP Addresses.
for IP in $EXTERNAL_IP_ADDRESSES; do

    # Configuring the IP Rule based on the IP Address.
    IP_RULE_NAME=$(echo $IP | sed s/[].]/-/g)

    # Checking to see if the IP Rule already exists in the Postgres Server Firewall.
    CHECK_IP_RULE=$(/usr/bin/az postgres server firewall-rule list \
    --server-name $POSTGRES_SRV_NAME \
    --resource-group $POSTGRES_SRV_RG_NAME \
    | jq --arg IP "$IP" '.[].startIpAddress | select(.|test($IP))' | tr -d '"' | cut -d/ -f 1)

    if [[ "$IP" == "$CHECK_IP_RULE" ]]; then
        echo "[---info------] Found IP Rule [$CHECK_IP_RULE] for IP [$IP] on Postgres Server [$POSTGRES_SRV_NAME]."
    else
        echo "[---info------] No IP Rule [$CHECK_IP_RULE] found for IP [$IP] on Postgres Server [$POSTGRES_SRV_NAME]."

        # Adding the IP Rule to the Postgres Server Firewall.
        ADD_IP_RULE=$(/usr/bin/az postgres server firewall-rule create \
        --name $IP_RULE_NAME \
        --server-name $POSTGRES_SRV_NAME \
        --resource-group $POSTGRES_SRV_RG_NAME \
        --start-ip-address $IP \
        --end-ip-address $IP 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Added the IP Rule for IP [$IP] on Postgres Server [$POSTGRES_SRV_NAME]."
        else
            echo "[---fail------] Failed to add IP Rule for IP [$IP] on Postgres Server [$POSTGRES_SRV_NAME]."
            echo "[---fail------] $ADD_IP_RULE"
            exit 2
        fi
    fi
done

# Retrieving the Postgres Server Admin User Password from the Kubernetes Azure Key Vault.
POSTGRES_SERVER_ADMIN_PASSWORD=$(/usr/bin/az keyvault secret show \
--name "$POSTGRES_SRV_NAME-acct-$POSTGRES_SERVER_ADMIN_USERNAME-password" \
--vault-name "$POSTGRES_SRV_KV_NAME" \
--query value \
--output tsv 2>&1)

if [ $? -eq 0 ]; then
    echo "[---success---] Retrieved the Postgres Server Admin User Password from Key Vault [$POSTGRES_SRV_KV_NAME]."
else
    echo "[---fail------] Failed to retrieve the Postgres Server Admin User Password from Key Vault [$POSTGRES_SRV_KV_NAME]."
    exit 2
fi

# Replacing the comma-delimiter with '\n' for the entries.
POSTGRES_DB_NAMES=$(echo $POSTGRES_DB_NAMES | tr ',' '\n')

# Deploying the required Postgres Databases and Database Users.
for DB in $POSTGRES_DB_NAMES; do

    # Checking if the Database exists on the Postgres Server.
    CHECK_DB=$(/usr/bin/az postgres db list \
    --server-name $POSTGRES_SRV_NAME \
    --resource-group $POSTGRES_SRV_RG_NAME 2>&1 | \
    jq --arg DB "$DB" '.[].name | select(.|test("^"+$DB+"$"))' | tr -d '"')

    if [[ "$CHECK_DB" == "$DB" ]]; then
        echo "[---info------] [$DB] Database was found on Postgres Server [$POSTGRES_SRV_NAME]."
    else
        echo "[---info------] [$DB] Database was not found on Postgres Server [$POSTGRES_SRV_NAME]."

        # Creating the Database on the Postgres Server.
        CREATE_DB=$(/usr/bin/az postgres db create \
        --resource-group $POSTGRES_SRV_RG_NAME \
        --server-name $POSTGRES_SRV_NAME \
        --name "$DB" \
        --collation 'nb_NO.UTF8' \
        --query name \
        --output tsv)

        if [[ "$CREATE_DB" == "$DB" ]]; then
            echo "[---success---] Created the [$DB] Database on Postgres Server [$POSTGRES_SRV_NAME]."
        else
            echo "[---fail------] Failed to create the [$DB] Database on Postgres Server [$POSTGRES_SRV_NAME]."
            echo "[---fail------] $CREATE_DB"
            exit 2
        fi

        # Generating the Password for the Database User.
        DB_PASSWORD=$(cat /proc/sys/kernel/random/uuid 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Generated the Password for Database User [$DB]."
        else
            echo "[---fail------] Failed to generate the Password for Database User [$DB]."
            echo "[---fail------] $DB_PASSWORD"
            exit 2
        fi

        # Creating the Database User for the Database.
        CREATE_USER=$(/usr/bin/psql \
        "host=psql host=$POSTGRES_SRV_NAME.postgres.database.azure.com port=5432 dbname=$DB user=$POSTGRES_SERVER_ADMIN_USERNAME@$POSTGRES_SRV_NAME password=$POSTGRES_SERVER_ADMIN_PASSWORD sslmode=require" \
        -c "CREATE USER "$DB" WITH PASSWORD '${DB_PASSWORD}';" 2>&1)
    
        if [[ "$CREATE_USER" == *"CREATE ROLE"* ]]; then
            echo "[---success---] Created User [$DB] in Database [$DB] on Postgres Server [$POSTGRES_SRV_NAME]."
        else
            echo "[---fail------] Failed to create User [$DB] in Database [$DB] on Postgres Server [$POSTGRES_SRV_NAME]."
            echo "[---fail------] $CREATE_USER"
            exit 2
        fi

        # Granting the Database User all privileges to the Database.
        GRANT_PRIVILEGES=$(/usr/bin/psql \
        "host=psql host=$POSTGRES_SRV_NAME.postgres.database.azure.com port=5432 dbname=$DB user=$POSTGRES_SERVER_ADMIN_USERNAME@$POSTGRES_SRV_NAME password=$POSTGRES_SERVER_ADMIN_PASSWORD sslmode=require" \
        -c "GRANT ALL PRIVILEGES ON DATABASE $DB to "$DB";" 2>&1)

        if [[ "$GRANT_PRIVILEGES" == "GRANT" ]]; then
            echo "[---success---] Granted User [$DB] all privileges to the [$DB] Database on Postgres Server [$POSTGRES_SRV_NAME]."
        else
            echo "[---fail------] Failed to grant User [$DB] all privileges to the [$DB] Database on Postgres Server [$POSTGRES_SRV_NAME]."
            echo "[---fail------] $GRANT_PRIVILEGES"
            exit 2
        fi

        # Adding the Database User Password to the Postgres Databases Key Vault.
        ADD_TO_VAULT=$(/usr/bin/az keyvault secret set \
        --name "$POSTGRES_SRV_NAME-$(echo "$DB" | tr '_' '-')-acct-password" \
        --vault-name "$POSTGRES_DBS_KV_NAME" \
        --value "$DB_PASSWORD" \
        --output none 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Added Postgres User [$DB] Password to Key Vault [$POSTGRES_DBS_KV_NAME]."
        else
            echo "[---fail------] Failed to add Postgres User [$DB] Password to Key Vault [$POSTGRES_DBS_KV_NAME]."
            echo "[---fail------] $ADD_TO_VAULT"
            exit 2
        fi
    fi
done

# Deployment Complete
echo "[---info------] Deployment of the PostgreSQL Server [$POSTGRES_SRV_NAME] for AKS Cluster [$K8S_CLUSTER_SP_USERNAME] is complete."