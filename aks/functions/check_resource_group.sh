#!/bin/bash

check_resource_group () {

    K8S_CLUSTER_SP_USERNAME=$1
    RESOURCE_GROUP_NAME=$2
    AZURE_LOCATION=$3

    echo "[---info------] - check_resource_group --- START ---"

    # Checking to see if the Resource Group already exists.
    RESOURCE_GROUP_CHECK=$(/usr/bin/az group list \
    | jq --arg RESOURCE_GROUP_NAME "$RESOURCE_GROUP_NAME" '.[] | select(.name == $RESOURCE_GROUP_NAME).name' \
    | tr -d '"')

    if [ ! -z "${RESOURCE_GROUP_CHECK}" ]; then
        echo "[---info------] Resource Group [$RESOURCE_GROUP_NAME] already exists."
    else
        echo "[---info------] Resource Group [$RESOURCE_GROUP_NAME] not found."

        # Creating the Resource Group.
        CREATE_RESOURCE_GROUP=$(/usr/bin/az group create \
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

    echo "[---info------] - check_resource_group --- END ---"
}