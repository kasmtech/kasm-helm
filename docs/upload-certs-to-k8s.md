---
title: Upload Certs to K8S
description: How to create and add TLS secrets to your Kubernetes cluster for Kasm.
author: Kasm Technologies
---

# Creating a TLS Secret in Kubernetes for Kasm

Kasm requires TLS for secure communication between its components. For your Kasm Kubernetes deployment to function correctly, you must create and add a certificate secret to the **Kasm namespace**. This guide covers the three most common methods for creating and managing your TLS secret.

---

## 🚦 Options for Creating Your Certificate Secret

1. [Use cert-manager (Recommended)](#using-cert-manager-recommended)
2. [Manually create a self-signed certificate](#manually-creating-a-self-signed-certificate)
3. [Upload a certificate from a Certificate Authority (CA)](#upload-a-certificate-from-a-different-certificate-authority-ca)

> **Before you begin:**
>
> * Ensure you know which Kubernetes namespace your Kasm deployment uses (`kasm-namespace` is used in this document).
> * Decide if you'll use cert-manager or manage your own certificate files.

---

## Using cert-manager (Recommended)

If your cluster has [cert-manager](https://cert-manager.io/docs/) installed, you can let cert-manager automatically create and manage your TLS secret. The Helm chart is already configured for this scenario.

1. Open your `values.yaml` file and locate the `certificate` block:

   ```yaml
   certificate:
     secretName: kasm-cert-secret
     certManager:
       enabled: true
       addWildCard: true
       issuerName: cert-issuer
       issuerKind: ""   # Defaults to Issuer
       issuerGroup: ""  # Defaults to cert-manager.io
       annotations: {}
       labels: {}
   ```
2. Adjust these values for your environment (issuer, secretName, etc).
3. Deploy or upgrade your Helm release as usual.

> See the [cert-manager documentation](https://cert-manager.io/docs/) for details on configuring [Issuers and ClusterIssuers](https://cert-manager.io/docs/concepts/issuer/).

---

## Manually Creating a Self-Signed Certificate

If you do not use cert-manager, you can generate a self-signed certificate and create a Kubernetes secret manually. There are two options:

* **A. Use the example script below** (copy-paste and run):

  ```bash

  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key -out tls.crt \
    -subj "/CN=kasm.example.com/O=Kasm Self-Signed"
  ```

* **B. Use the Kubernetes documentation guide:**

  [Generate Certificates Manually](https://kubernetes.io/docs/tasks/administer-cluster/certificates/)

**Filename requirements for this chart:**

* Certificate file: `tls.crt`
* Key file: `tls.key`
* CA certificate (optional, for custom CAs): `ca.crt`

---

## Upload a Certificate from a Different Certificate Authority (CA)

If you already have a certificate from your organization's CA or a public CA:

1. Obtain/export your certificate (`tls.crt`), key (`tls.key`), and optional CA certificate (`ca.crt`).
2. Continue to the [Adding the generated TLS secret to Kubernetes](#adding-the-generated-tls-secret-to-kubernetes) section below.

---

## Adding the Generated TLS Secret to Kubernetes

Run the following commands, substituting your values:

```bash
# Set your secret and namespace names
SECRET_NAME="kasm-cert-secret"
NAMESPACE="kasm-ns"

# Create a TLS secret (cert + key only):
kubectl create secret tls $SECRET_NAME \
  --cert=tls.crt \
  --key=tls.key \
  --namespace $NAMESPACE

# If you need to include a CA certificate as well:
kubectl create secret generic $SECRET_NAME \
  --from-file=tls.crt=/path/to/tls.crt \
  --from-file=tls.key=/path/to/tls.key \
  --from-file=ca.crt=/path/to/ca.crt \
  --namespace $NAMESPACE
```

> **Note:** The Helm chart expects the `certificate.secretName` in your `values.yaml` to match the secret you just created. You can also set this at install/upgrade time with:
>
> ```bash
> helm install kasm-helm ./charts/kasm \
>   --namespace $NAMESPACE \
>   --set certificate.secretName="$SECRET_NAME"
> ```

---

## Additional References

* [kubectl create secret tls](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_secret_tls/)
* [kubectl create secret generic](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_secret_generic/)
* [cert-manager documentation](https://cert-manager.io/docs/)
