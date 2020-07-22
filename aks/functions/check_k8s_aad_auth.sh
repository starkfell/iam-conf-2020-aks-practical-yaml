#!/bin/bash

check_k8s_aad_auth () {

    K8S_CLUSTER_SP_USERNAME=$1
    K8S_KEY_VAULT_NAME=$2

    echo "[---info------] - check_k8s_aad_auth --- START ---"

    # Checking to see if the Server AAD Application already exists in the Azure Subscription.
    SERVER_AAD_APP_CHECK=$(/usr/bin/az ad app list --all 2>&1 \
    | jq --arg DISPLAY_NAME "$K8S_CLUSTER_SP_USERNAME-aad-apisrv" '.[] | select(.displayName == $DISPLAY_NAME).displayName' \
    | tr -d '"')

    if [ ! -z "${SERVER_AAD_APP_CHECK}" ]; then
        echo "[---info------] The Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv] already exists."
    else
        echo "[---info------] The Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv] was not found."

        # Creating the Server AAD Application.
        CREATE_AAD_SRV_APP=$(/usr/bin/az ad app create \
        --display-name $K8S_CLUSTER_SP_USERNAME-aad-apisrv \
        --identifier-uris http://$K8S_CLUSTER_SP_USERNAME-aad-apisrv \
        --homepage http://$K8S_CLUSTER_SP_USERNAME-aad-apisrv \
        --native-app false 2>&1 1>/dev/null)

        if [ $? -eq 0 ]; then
            echo "[---success---] Created the Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv] for the Kubernetes Cluster."
        else
            echo "[---fail------] Failed to create the Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv] for the Kubernetes Cluster."
            echo "[---fail------] $CREATE_AAD_SRV_APP"
            exit 2
        fi

        # Creating the Service Principal for the Server AAD Application.
        CREATE_AAD_SRV_SP=$(/usr/bin/az ad sp create \
        --id http://$K8S_CLUSTER_SP_USERNAME-aad-apisrv 2>&1 1>/dev/null)

        if [ $? -eq 0 ]; then
            echo "[---success---] Created the Service Principal for the Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv]."
        else
            echo "[---fail------] Failed to create the Service Principal for the Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv]."
            echo "[---fail------] $CREATE_AAD_SRV_SP"
            exit 2
        fi

        # Changing the groupMembershipClaims property to 'All' for the Server AAD Application.
        UPDATE_AAD_SRV_APP=$(/usr/bin/az ad app update \
        --id http://$K8S_CLUSTER_SP_USERNAME-aad-apisrv \
        --set groupMembershipClaims=All 2>&1 1>/dev/null)

        if [ $? -eq 0 ]; then
            echo "[---success---] Changed the groupMembershipClaims property to 'All' for the Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv]."
        else
            echo "[---fail------] Failed to change the groupMembershipClaims property to 'All' for the Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv]."
            echo "[---fail------] $UPDATE_AAD_SRV_APP"
            exit 2
        fi

        # Updating the Server AAD Application Manifest from the 'aks/aks-engine-aad-manifests/k8s-apisrv-manifest.json' file. 
        UPDATE_AAD_SRV_APP_MANIFEST=$(/usr/bin/az ad app update \
        --id http://$K8S_CLUSTER_SP_USERNAME-aad-apisrv \
        --required-resource-accesses "aks/aks-engine-aad-manifests/k8s-apisrv-manifest.json" 2>&1 1>/dev/null)

        if [ $? -eq 0 ]; then
            echo "[---success---] Updated the Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv] Manifest from the [k8s-apisrv-manifest.json] file."
            echo "[---info------] Waiting 30 seconds before continuing."
            sleep 30
        else
            echo "[---fail------] Failed to update the Server AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apisrv] Manifest from the [k8s-apisrv-manifest.json] file."
            echo "[---fail------] $UPDATE_AAD_SRV_APP_MANIFEST"
            exit 2
        fi

        # Retrieving the Access Token of the Management Service Principal.
        ACCESS_TOKEN=$(az account get-access-token \
        --resource https://graph.microsoft.com \
        --query accessToken \
        --output tsv 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the Access Token of the Management Service Principal."
        else
            echo "[---fail------] Failed to retrieve the Access Token of the Management Service Principal."
            echo "[---fail------] $ACCESS_TOKEN"
            exit 2
        fi

        # Retrieving the Graph API Service Principal Object ID in the Azure Subscription. (This is unique to each Azure Subscription).
        GRAPH_API_SP_OBJECT_ID=$(az ad sp show \
        --id 00000003-0000-0000-c000-000000000000 \
        --query objectId \
        --output tsv 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the Graph API Service Principal Object ID [$GRAPH_API_SP_OBJECT_ID] in the Azure Subscription."
        else
            echo "[---fail------] Failed to retrieve the Graph API Service Principal Object ID in the Azure Subscription."
            echo "[---fail------] $GRAPH_API_SP_OBJECT_ID"
            exit 2
        fi

        # Retrieving the Service Principal Object ID of the Server AAD Application.
        AAD_SRV_APP_SP_OBJECT_ID=$(az ad sp show \
        --id http://$K8S_CLUSTER_SP_USERNAME-aad-apisrv \
        --query objectId \
        --output tsv 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the Service Principal Object ID [$AAD_SRV_APP_SP_OBJECT_ID] of the Server AAD Application."
        else
            echo "[---fail------] Failed to retrieve the Service Principal Object ID [$AAD_SRV_APP_SP_OBJECT_ID] of the Server AAD Application."
            echo "[---fail------] $AAD_SRV_APP_SP_OBJECT_ID"
            exit 2
        fi

        # Retrieving the ID of the 'Directory.Read.All' App Role in the Azure Graph Service Principal.
        DIRECTORY_READ_ALL_APP_ROLE_ID=$(az ad sp show \
        --id 00000003-0000-0000-c000-000000000000 \
        | jq '.appRoles[] | select(.value|test("^"+"Directory.Read.All")).id' \
        | tr -d '"')

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the ID [$DIRECTORY_READ_ALL_APP_ROLE_ID] of the [Directory.Read.All] App Role in the Azure Graph API Service Principal."
        else
            echo "[---fail------] Failed to retrieve the ID of the [Directory.Read.All] App Role in the Azure Graph API Service Principal."
            echo "[---fail------] $DIRECTORY_READ_ALL_APP_ROLE_ID"
            exit 2
        fi

        # Granting Admin Consent for the 'Directory.Read.All' App Role Assigment on the Server AAD Application.
        GRANT_APP_ROLE_ASSIGNMENT=$(curl --request POST \
        "https://graph.microsoft.com/beta/servicePrincipals/$AAD_SRV_APP_SP_OBJECT_ID/appRoleAssignedTo" \
        --header "Authorization: Bearer $ACCESS_TOKEN" \
        --header "Content-Type: application/json" \
        --data-raw '{
        "principalId": "'"$AAD_SRV_APP_SP_OBJECT_ID"'",
        "resourceId": "'"$GRAPH_API_SP_OBJECT_ID"'",
        "appRoleId": "'"$DIRECTORY_READ_ALL_APP_ROLE_ID"'"
        }' 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Granted Admin Consent for the [Directory.Read.All] App Role Assigment on the Server AAD Application."
            echo "[---info------] $GRANT_APP_ROLE_ASSIGNMENT"
            echo "[---info------] Waiting 10 seconds before continuing."
            sleep 10
        else
            echo "[---fail------] Failed to grant Admin Consent for the [Directory.Read.All] App Role Assigment on the Server AAD Application."
            echo "[---fail------] $GRANT_APP_ROLE_ASSIGNMENT"
            exit 2
        fi

        # Granting delegated Admin Consent for the 'Directory.Read.All' Oauth2 Permission on the Server AAD Application. (Expiration set for January 2050).
        GRANT_DELEGATED_ASSIGNMENT=$(curl --request POST 'https://graph.microsoft.com/beta/oauth2PermissionGrants' \
        --header "Authorization: Bearer $ACCESS_TOKEN" \
        --header 'Content-Type: application/json' \
        --data-raw '{
            "clientId": "'"$AAD_SRV_APP_SP_OBJECT_ID"'",
            "consentType": "AllPrincipals",
            "expiryTime": "2050-01-01T20:00:00",
            "principalId": null,
            "resourceId": "'"$GRAPH_API_SP_OBJECT_ID"'",
            "scope": "Directory.Read.All"
        }' 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Granted delegated Admin Consent for the [Directory.Read.All] Oauth2 Permission on the Server AAD Application."
            echo "[---info------] $GRANT_DELEGATED_ASSIGNMENT"
            echo "[---info------] Waiting 10 seconds before continuing."
            sleep 10
        else
            echo "[---fail------] Failed to grant delegated Admin Consent for the [Directory.Read.All] Oauth2 Permission on the Server AAD Application."
            echo "[---fail------] $GRANT_DELEGATED_ASSIGNMENT"
            exit 2
        fi

        # Retrieving the Server AAD Application's App ID.
        K8S_APISRV_APP_ID=$(/usr/bin/az ad app show \
        --id http://$K8S_CLUSTER_SP_USERNAME-aad-apisrv \
        --query appId \
        --output tsv 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the Server AAD Application's App ID."
        else
            echo "[---fail------] Failed to retrieve the Server AAD Application's App ID."
            echo "[---fail------] $K8S_APISRV_APP_ID"
            exit 2
        fi

        # Creating a Secret for the Server AAD Application.
        CREATE_SECRET=$(az ad sp credential reset \
        --name $K8S_APISRV_APP_ID \
        --credential-description "aad-api-creds" \
        --query password \
        -o tsv 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Created a Secret for the Server AAD Application."
        else
            echo "[---fail------] Failed to create a Secret for the Server AAD Application."
            echo "[---fail------] $CREATE_SECRET"
            exit 2
        fi

        # Adding the Server AAD Application Secret to the Azure Key Vault.
        ADD_TO_VAULT=$(/usr/bin/az keyvault secret set \
        --name "$K8S_CLUSTER_SP_USERNAME-aad-apisrv-password" \
        --vault-name "$K8S_KEY_VAULT_NAME" \
        --value "$CREATE_SECRET" \
        --output none 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Added the Server AAD Application to Key Vault [$K8S_KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to add the Server AAD Application to Key Vault [$K8S_KEY_VAULT_NAME]."
            echo "[---fail------] $ADD_TO_VAULT"
            exit 2
        fi
    fi

    # Retrieving the Server AAD Application's App ID.
    K8S_APISRV_APP_ID=$(/usr/bin/az ad app show \
    --id http://$K8S_CLUSTER_SP_USERNAME-aad-apisrv \
    --query appId \
    --output tsv 2>&1)

    if [ $? -eq 0 ]; then
        echo "[---success---] Retrieved the Server AAD Application's App ID."
    else
        echo "[---fail------] Failed to retrieve the Server AAD Application's App ID."
        echo "[---fail------] $K8S_APISRV_APP_ID"
        exit 2
    fi

    # Retrieving the Server AAD Application's OAUTH2 Permissions ID.
    K8S_APISRV_OAUTH2_PERMISSIONS_ID=$(/usr/bin/az ad app show \
    --id http://$K8S_CLUSTER_SP_USERNAME-aad-apisrv \
    --query oauth2Permissions[].id \
    --output tsv 2>&1)

    if [ $? -eq 0 ]; then
        echo "[---success---] Retrieved the Server AAD Application's OAUTH2 Permissions ID."
    else
        echo "[---fail------] Failed to retrieve the Server AAD Application's OAUTH2 Permissions ID."
        echo "[---fail------] $K8S_APISRV_OAUTH2_PERMISSIONS_ID"
        exit 2
    fi

    # Checking to see if the Client AAD Application already exists in the Azure Subscription.
    CLIENT_AAD_APP_CHECK=$(/usr/bin/az ad app list --all 2>&1 \
    | jq --arg DISPLAY_NAME "$K8S_CLUSTER_SP_USERNAME-aad-apicli" '.[] | select(.displayName == $DISPLAY_NAME).displayName' \
    | tr -d '"')

    if [ ! -z "${CLIENT_AAD_APP_CHECK}" ]; then
        echo "[---info------] The Client AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apicli] already exists."
    else
        echo "[---info------] The Client AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apicli] was not found."

        # Creating the Client AAD Application.
        DEPLOY_K8S_APICLI_APP=$(/usr/bin/az ad app create \
        --display-name $K8S_CLUSTER_SP_USERNAME-aad-apicli \
        --reply-urls http://$K8S_CLUSTER_SP_USERNAME-aad-apicli \
        --homepage http://$K8S_CLUSTER_SP_USERNAME-aad-apicli --native-app true)

        if [ $? -eq 0 ]; then
            echo "[---success---] Created the Client AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apicli]."
        else
            echo "[---fail------] Failed to create the Client AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apicli]."
            exit 2
        fi

        # Retrieving the Client AAD Application App ID.
        K8S_APICLI_APP_ID=$(/usr/bin/az ad app list --all 2>&1 \
        | jq --arg DISPLAY_NAME "$K8S_CLUSTER_SP_USERNAME-aad-apicli" '.[] | select(.displayName == $DISPLAY_NAME).appId' \
        | tr -d '"')

        if [ $? -eq 0 ]; then
            echo "[---success---] Retrieved the Client AAD Application App ID."
        else
            echo "[---fail------] Failed to retreive the Client AAD Application App ID."
            echo "[---fail------] $K8S_APICLI_APP_ID"
            exit 2
        fi

        # Creating a Service Principal for the Client AAD Application.
        CREATE_AAD_CLI_SP=$(/usr/bin/az ad sp create \
        --id $K8S_APICLI_APP_ID 2>&1 1>/dev/null)

        if [ $? -eq 0 ]; then
            echo "[---success---] Created the Service Principal for the Client AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apicli]."
        else
            echo "[---fail------] Failed to create the Service Principal for the Client AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apicli]."
            echo "[---fail------] $CREATE_AAD_CLI_SP"
        fi

        # Concatenating the contents of 'aks/aks-engine-aad-manifests/k8s-apicli-template-manifest.json' file to the 'aks/aks-engine-aad-manifests/k8s-apicli-manifest.json' file.
        cat aks/aks-engine-aad-manifests/k8s-apicli-template-manifest.json > aks/aks-engine-aad-manifests/k8s-apicli-manifest.json

        if [ $? -eq 0 ]; then
            echo "[---success---] Concatenated the contents of 'k8s-apicli-template-manifest.json' file to the 'k8s-apicli-manifest.json' file."
        else
            echo "[---fail------] Failed to concatenate the contents of 'k8s-apicli-template-manifest.json' file to the 'k8s-apicli-manifest.json' file."
            exit 2
        fi

        # Adding the Server AAD Application's App ID to the 'aks/aks-engine-aad-manifests/k8s-apicli-manifest.json' file.
        ADD_APP_ID=$(sed -i -e "s/{K8S_APISRV_APP_ID}/$K8S_APISRV_APP_ID/g" aks/aks-engine-aad-manifests/k8s-apicli-manifest.json 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Added the Server AAD Application's App ID to the [k8s-apicli-manifest.json] file."
        else
            echo "[---fail------] Failed to add the Server AAD Application's App ID to the [k8s-apicli-manifest.json] file."
            echo "[---fail------] $ADD_APP_ID"
            exit 2
        fi

        # Adding the Server AAD Application's OAUTH2 Permissions ID to the 'aks/aks-engine-aad-manifests/k8s-apicli-manifest.json' file.
        ADD_OAUTH2=$(sed -i -e "s/{K8S_APISRV_OAUTH2_PERMISSIONS_ID}/$K8S_APISRV_OAUTH2_PERMISSIONS_ID/" aks/aks-engine-aad-manifests/k8s-apicli-manifest.json 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Added the Server AAD Application's OAUTH2 Permissions ID to the [k8s-apicli-manifest.json] file."
        else
            echo "[---fail------] Failed to add the Server AAD Application's OAUTH2 Permissions ID to the [k8s-apicli-manifest.json] file."
            echo "[---fail------] $ADD_OAUTH2"
            exit 2
        fi

        # Updating the Client AAD Application Manifest from the 'aks/aks-engine-aad-manifests/k8s-apicli-manifest.json' file.
        UPDATE_AAD_CLI_APP_MANIFEST=$(/usr/bin/az ad app update \
        --id $K8S_APICLI_APP_ID \
        --required-resource-accesses "aks/aks-engine-aad-manifests/k8s-apicli-manifest.json" 2>&1 1>/dev/null)

        if [ $? -eq 0 ]; then
            echo "[---success---] Updated the Client AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apicli] Manifest from the [k8s-apicli-manifest.json] file."
        else
            echo "[---fail------] Failed to update the Client AAD Application [$K8S_CLUSTER_SP_USERNAME-aad-apicli] Manifest from the [k8s-apicli-manifest.json] file."
            echo "[---fail------] $UPDATE_AAD_CLI_APP_MANIFEST"
            exit 2
        fi
    fi

    echo "[---info------] - check_k8s_aad_auth --- END ---"
}