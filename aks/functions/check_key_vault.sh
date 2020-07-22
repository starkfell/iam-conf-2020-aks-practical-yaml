#!/bin/bash

check_key_vault () {

    K8S_KV_NAME=$1
    K8S_KV_RG_NAME=$2

    echo "[---info------] - check_key_vault --- START ---"

    # Checking to see if the Key Vault already exists.
    K8S_KV_CHECK=$(/usr/bin/az keyvault list \
    | jq --arg K8S_KV_NAME "$K8S_KV_NAME" '.[] | select(.name == $K8S_KV_NAME).name' \
    | tr -d '"')

    if [ ! -z "${K8S_KV_CHECK}" ]; then
        echo "[---info------] Key Vault [$K8S_KV_NAME] already exists."
    else
        echo "[---info------] Key Vault [$K8S_KV_NAME] not found."

        # Check to see if Key Vault is soft-deleted.
        CHECK_SOFT_DELETE=$(az keyvault list-deleted \
        | jq --arg K8S_KV_NAME "$K8S_KV_NAME" '.[].name | select(.|test("^"+$K8S_KV_NAME+"$"))' | tr -d '"')

        if [[ "$CHECK_SOFT_DELETE" == "$K8S_KV_NAME" ]]; then
            echo "[---info------] Key Vault [$K8S_KV_NAME] found soft-deleted."

            # Retrieving the Location of the soft-deleted Key Vault.
            K8S_KV_LOCATION=$(az keyvault list-deleted \
            | jq --arg K8S_KV_NAME "$K8S_KV_NAME" '.[] | select(.name|test("^"+$K8S_KV_NAME+"$")).properties.location' | tr -d '"')

            if [ $? -eq 0 ]; then
                echo "[---success---] Retrieved the Location [$K8S_KV_LOCATION] of soft-deleted Key Vault [$K8S_KV_NAME]."
            else
                echo "[---fail------] Failed to retrieve the Location [$K8S_KV_LOCATION] of soft-deleted Key Vault [$K8S_KV_NAME]."
                echo "[---fail------] $K8S_KV_LOCATION."
                exit 2
            fi

            # Purging the soft-deleted Key Vault.
            PURGE_KV=$(az keyvault purge \
            --name $K8S_KV_NAME \
            --location $K8S_KV_LOCATION)

            if [ $? -eq 0 ]; then
                echo "[---success---] Purged soft-deleted Key Vault [$K8S_KV_NAME]."
            else
                echo "[---fail------] Failed to purge soft-deleted Key Vault [$K8S_KV_NAME]."
                echo "[---fail------] $PURGE_KV."
                exit 2
            fi
        else
            echo "[---info------] Key Vault [$K8S_KV_NAME] was not found soft-deleted."
        fi

        # Creating the Key Vault.
        CREATE_KV=$(/usr/bin/az keyvault create \
        --name "$K8S_KV_NAME" \
        --resource-group "$K8S_KV_RG_NAME" \
        --enabled-for-deployment \
        --enabled-for-template-deployment 2>&1 1>/dev/null)

        if [ $? -eq 0 ]; then
            echo "[---success---] Deployed the Key Vault [$K8S_KV_NAME] to Resource Group [$K8S_KV_RG_NAME]."
        else
            echo "[---fail------] Failed to deploy the Key Vault [$K8S_KV_NAME] to Resource Group [$K8S_KV_RG_NAME]."
            echo "[---fail------] $CREATE_KV."
            exit 2
        fi
    fi

    echo "[---info------] - check_key_vault --- END ---"
}