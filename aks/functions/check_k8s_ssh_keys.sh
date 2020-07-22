#!/bin/bash

check_k8s_ssh_keys () {

    K8S_SSH_PRIVATE_KEY_NAME=$1
    K8S_KEY_VAULT_NAME=$2

    echo "[---info------] - check_k8s_ssh_keys --- START ---"

    # Checking to see if the SSH Keys for the Kubernetes Cluster already exists in the Key Vault.
    SECRET_CHECK=$(/usr/bin/az keyvault secret show \
    --name "$K8S_SSH_PRIVATE_KEY_NAME" \
    --vault-name "$K8S_KEY_VAULT_NAME" \
    --output none 2>&1)

    if [ $? -eq 0 ]; then
        echo "[---info------] The SSH Private Key for the Kubernetes Cluster already exists in Key Vault [$K8S_KEY_VAULT_NAME]."
    else
        echo "[---info------] The SSH Private Key for the Kubernetes Cluster was not found in Key Vault [$K8S_KEY_VAULT_NAME]."

        # Generating a Password for the Kubernetes Cluster SSH Private Key.
        SSH_PRIVATE_KEY_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9'!#$%' | head -c 13 ; echo '' 2>&1 1>/dev/null)

        if [ $? -eq 0 ]; then
            echo "[---success---] Generated a password for the Kubernetes Cluster SSH Private Key [$K8S_SSH_PRIVATE_KEY_NAME]."
        else
            echo "[---fail------] Unable to generate a password for the Kubernetes Cluster SSH Private Key [$K8S_SSH_PRIVATE_KEY_NAME]."
            echo "[---fail------] $SSH_PRIVATE_KEY_PASSWORD"
            exit 2
        fi

        # Generating SSH Keys for the Kubernetes Cluster.
        GENERATE_SSH_KEYS=$(ssh-keygen -t rsa \
        -b 2048 \
        -C "$K8S_SSH_PRIVATE_KEY_NAME" \
        -f ./$K8S_SSH_PRIVATE_KEY_NAME \
        -N "$SSH_PRIVATE_KEY_PASSWORD" 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] SSH Keys for the Kubernetes Cluster have been generated."
        else
            echo "[---fail------] Failed to generate SSH Keys for the Kubernetes Cluster."
            echo "[---fail------] $GENERATE_SSH_KEYS"
            exit 2
        fi

        # Adding the Kubernetes SSH Private Key to the Azure Key Vault.
        ADD_TO_VAULT=$(/usr/bin/az keyvault secret set \
        --name "$K8S_SSH_PRIVATE_KEY_NAME" \
        --vault-name "$K8S_KEY_VAULT_NAME" \
        --file "./$K8S_SSH_PRIVATE_KEY_NAME" \
        --output none 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] The Kubernetes SSH Private Key has been added to Key Vault [$K8S_KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to add the Kubernetes SSH Private Key to Key Vault [$K8S_KEY_VAULT_NAME]."
            echo "[---fail------] $ADD_TO_VAULT"
            exit 2
        fi

        # Adding the Kubernetes SSH Private Key Password to the Azure Key Vault.
        ADD_TO_VAULT=$(/usr/bin/az keyvault secret set \
        --name "$K8S_SSH_PRIVATE_KEY_NAME-password" \
        --vault-name "$K8S_KEY_VAULT_NAME" \
        --value "$SSH_PRIVATE_KEY_PASSWORD" \
        --output none 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] The Kubernetes SSH Private Key Password has been added to Key Vault [$K8S_KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to add the Kubernetes SSH Private Key Password to Key Vault [$K8S_KEY_VAULT_NAME]."
            echo "[---fail------] $ADD_TO_VAULT"
            exit 2
        fi

        # Adding the Kubernetes SSH Public Key to the Azure Key Vault.
        ADD_TO_VAULT=$(/usr/bin/az keyvault secret set \
        --name "$K8S_SSH_PRIVATE_KEY_NAME-pub" \
        --vault-name "$K8S_KEY_VAULT_NAME" \
        --file "./$K8S_SSH_PRIVATE_KEY_NAME.pub" \
        --output none 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] The Kubernetes SSH Public Key has been added to Key Vault [$K8S_KEY_VAULT_NAME]."
        else
            echo "[---fail------] Failed to add the Kubernetes SSH Public Key to Key Vault [$K8S_KEY_VAULT_NAME]."
            echo "[---fail------] $ADD_TO_VAULT"
            exit 2
        fi

        # Removing the Kubernetes SSH Private Key locally.
        if [ -e "$K8S_SSH_PRIVATE_KEY_NAME" ]; then
            rm -f "$K8S_SSH_PRIVATE_KEY_NAME"

            if [ $? -eq 0 ]; then
                echo "[---success---] Removed the Kubernetes Cluster SSH Private Key locally."
            else
                echo "[---fail------] Failed to remove the Kubernetes Cluster SSH Private Key locally."
                exit 2
            fi
        fi

        # Removing the Kubernetes SSH Public Key locally.
        if [ -e "$K8S_SSH_PRIVATE_KEY_NAME.pub" ]; then
            rm -f "$K8S_SSH_PRIVATE_KEY_NAME.pub"

            if [ $? -eq 0 ]; then
                echo "[---success---] Removed the Kubernetes Cluster SSH Public Key locally."
            else
                echo "[---fail------] Failed to remove the Kubernetes Cluster SSH Public Key locally."
                exit 2
            fi
        fi
    fi

    echo "[---info------] - check_k8s_ssh_keys --- END ---"
}