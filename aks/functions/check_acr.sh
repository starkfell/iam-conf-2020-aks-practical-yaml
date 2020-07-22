#!/bin/bash

check_acr () {

    ACR_NAME=$1
    ACR_RESOURCE_GROUP_NAME=$2
    AZURE_LOCATION=$3

    echo "[---info------] - check_acr --- START ---"

    # Checking to see if the Azure Container Registry already exists.
    ACR_CHECK=$(/usr/bin/az acr list \
    | jq --arg ACR_NAME "$ACR_NAME" '.[] | select(.name == $ACR_NAME).name' \
    | tr -d '"')

    if [ ! -z "${ACR_CHECK}" ]; then
        echo "[---info------] Azure Container Registry [$ACR_NAME] already exists."
    else
        echo "[---info------] Azure Container Registry [$ACR_NAME] not found."

        # Creating the Azure Container Registry.
        CREATE_ACR=$(/usr/bin/az acr create \
        --name $ACR_NAME \
        --resource-group "$ACR_RESOURCE_GROUP_NAME" \
        --sku Standard \
        --location "$AZURE_LOCATION" \
        --admin-enabled true 2>&1 1>/dev/null)

        if [ $? -eq 0 ]; then
            echo "[---success---] Created the Azure Container Registry [$ACR_NAME] in Resource Group [$ACR_RESOURCE_GROUP_NAME]."
        else
            echo "[---fail------] Failed to create the Azure Container Registry [$ACR_NAME] in Resource Group [$ACR_RESOURCE_GROUP_NAME]."
            echo "[---fail------] $CREATE_ACR."
            exit 2
        fi
    fi

    echo "[---info------] - check_acr --- END ---"
}
