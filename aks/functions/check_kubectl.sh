#/bin/bash

check_kubectl () {

    echo "[---info------] - check_kubectl --- START ---"

    # Checking to see if Kubectl is installed.
    if [ -e "/usr/local/bin/kubectl" ]; then
        echo "[---info------] kubectl is already installed."
    else
        echo "[---info------] kubectl is not installed."

        # Installing Kubectl.
        curl -s -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
        chmod +x ./kubectl && \
        mv ./kubectl /usr/local/bin/kubectl 2>&1

        # Retrieving the Kubectl Client Version.
        KUBECTL_VERSION_CHECK=$(kubectl version --client --short=true 2>&1)

        if [ $? -eq 0 ]; then
            echo "[---success---] Installed Kubectl [$KUBECTL_VERSION_CHECK]."
        else
            echo "[---fail------] Failed to install Kubectl."
            echo "[---fail------] $KUBECTL_VERSION_CHECK."
            exit 2
        fi
    fi

    echo "[---info------] - check_kubectl --- END ---"
}