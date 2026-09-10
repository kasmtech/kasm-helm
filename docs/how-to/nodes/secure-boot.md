# Secure Boot: signing kernel modules

> **Applies to:** agent · the MOK keys have to be enrolled in each node's UEFI, a one-time manual step per node · **Charts/values:** `nodePrep.secureBoot.existingMokSecret`, `nodePrep.modules.v4l2loopback.kmm.sign.enabled`, `nodePrep.modules.v4l2loopback.kmm.sign.keySecret`, `nodePrep.modules.v4l2loopback.kmm.sign.certSecret`

## Why this is needed

On a node with UEFI Secure Boot enabled the kernel refuses to load an unsigned module. `v4l2loopback` (webcam passthrough) and an out-of-tree WireGuard are both freshly built out-of-tree modules, so on such a node `insmod` fails and `/dev/video*` never appears - no matter how correct the rest of the configuration is.

Two signing paths, matching the two module modes:

| | Where signing happens | Value |
| --- | --- | --- |
| `method: build` | On the node, after the compile, before `insmod`, with the kernel's `sign-file` helper | `nodePrep.secureBoot.existingMokSecret` |
| `method: kmm` | In the cluster, between build and push, so an unsigned `.ko` never reaches a node | `nodePrep.modules.v4l2loopback.kmm.sign.*` |

Both need the **same** thing out of band: the public key enrolled in each node's UEFI MOK database. No chart can do that.

## Before you start

- **Confirm Secure Boot is actually on.** If it is off, this entire page is a no-op - skip it.

  ```console
  mokutil --sb-state
  ```

  Expected on an affected node: `SecureBoot enabled`.
- Distro variants: this is overwhelmingly a **bare-metal and private-cloud** concern. **EKS, GKE and AKS** leave Secure Boot off on their default node images (GCE Shielded VMs can enable it; if you did, you own this page). **k3s / kubeadm** make no difference here - the gate is the node's firmware, not the distribution. **OpenShift**: KMM is the native path; the signing values below are the same.
- Console or out-of-band access to every node: MOK enrolment is confirmed in the **UEFI MOK Manager at boot**, not from `kubectl` or SSH.
- `openssl` and `mokutil` available on a workstation and on the nodes respectively.
- Build mode only: the builder image must carry `openssl` - the kernel's `sign-file` helper needs it. The stock `ubuntu:22.04` builder installs it at runtime; a pre-baked airgap image must include it (see [kasm-node-prep § Build and push the builder image](../../../charts/kasm-node-prep/README.md#build-and-push-the-builder-image)).
- KMM mode + airgap only: mirror the KMM **sign** image too - `make images-agent` lists it under `# KMM mode`, flagged as Secure Boot only.
- The namespace must already permit the `privileged` PSS: [privileged workloads and cluster policy](privileged-workloads.md).

## Steps

1. **Generate a Machine Owner Key pair** on a trusted workstation. The certificate needs the module-signing extensions, so drive `openssl req` from a config rather than the prompts:

   ```console
   cat > mok.cnf <<'EOF'
   [ req ]
   default_bits       = 4096
   distinguished_name = req_distinguished_name
   prompt             = no
   string_mask        = utf8only
   x509_extensions    = mok_ext

   [ req_distinguished_name ]
   CN = Kasm node-prep module signing key

   [ mok_ext ]
   basicConstraints       = critical,CA:FALSE
   keyUsage               = digitalSignature
   extendedKeyUsage       = codeSigning
   subjectKeyIdentifier   = hash
   authorityKeyIdentifier = keyid
   EOF

   openssl req -x509 -new -nodes -utf8 -sha256 -days 3650 \
     -config mok.cnf -outform DER -out MOK.der -keyout MOK.priv
   ```

   `MOK.priv` is a PEM private key; `MOK.der` is the DER certificate. Treat `MOK.priv` as a cluster-wide root secret: anything signed with it loads into ring 0 on every enrolled node.

2. **Enrol the public key in each node's UEFI.** Copy `MOK.der` to the node, then:

   ```console
   sudo mokutil --import MOK.der      # prompts for a one-time enrolment password
   sudo reboot
   ```

   On the next boot the firmware drops into **MOK Manager**: choose *Enroll MOK* → *Continue* → *Yes* → enter the one-time password. This step is interactive and per node - the alternative is baking the enrolled key into the node image, which is what fleets do.

3. **Create the Secret(s)** in the release namespace.

   Build mode - one Secret, keys `mokPrivateKey` and `mokPublicKey`:

   ```console
   kubectl create secret generic kasm-mok-keys \
     --namespace kasm-agent \
     --from-file=mokPrivateKey=MOK.priv \
     --from-file=mokPublicKey=MOK.der
   ```

   KMM mode - two Secrets, with the exact data keys KMM expects (`key`, `cert`):

   ```console
   kubectl create secret generic kasm-mok-key  --namespace kasm-agent --from-file=key=MOK.priv
   kubectl create secret generic kasm-mok-cert --namespace kasm-agent --from-file=cert=MOK.der
   ```

4. **Point the chart at them and upgrade.**

   Build mode:

   ```console
   helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent -n kasm-agent \
     --set nodePrep.enabled=true \
     --set nodePrep.modules.v4l2loopback.enabled=true \
     --set nodePrep.secureBoot.existingMokSecret=kasm-mok-keys
   ```

   The Secret is mounted read-only at `/etc/kasm-mok` and every built `.ko` is signed before insertion.

   KMM mode:

   ```console
   helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent -n kasm-agent \
     --set nodePrep.enabled=true \
     --set nodePrep.modules.v4l2loopback.enabled=true \
     --set nodePrep.modules.v4l2loopback.method=kmm \
     --set nodePrep.modules.v4l2loopback.kmm.image.registry=registry.example.internal \
     --set nodePrep.modules.v4l2loopback.kmm.image.repository=kasm/v4l2loopback \
     --set nodePrep.modules.v4l2loopback.kmm.sign.enabled=true \
     --set nodePrep.modules.v4l2loopback.kmm.sign.keySecret=kasm-mok-key \
     --set nodePrep.modules.v4l2loopback.kmm.sign.certSecret=kasm-mok-cert
   ```

   Both sign Secrets are **required** when `nodePrep.modules.v4l2loopback.kmm.sign.enabled` is set; an empty one fails the render.

5. **Rotating or adding a key** means repeating steps 1–3 and re-enrolling. `secureBoot.existingMokSecret` applies only to modules this chart's DaemonSet builds; `nodePrep.modules.v4l2loopback.kmm.sign.enabled` applies only to KMM-built images. They are independent and can coexist on a fleet running both modes.

## Verify

1. The key is enrolled in the node's firmware:

   ```console
   mokutil --list-enrolled | grep -A2 'Kasm node-prep module signing key'
   ```

   Expected: the certificate's `Subject: CN=Kasm node-prep module signing key`. Absent means MOK Manager was never completed - re-run `mokutil --import` and finish the reboot prompt.

2. Build mode: the DaemonSet saw the keys, on startup  - 

   ```console
   kubectl -n kasm-agent logs -l app.kubernetes.io/component=node-prep | grep -i mok
   ```

   Expected: `Secure Boot MOK keys are mounted at /etc/kasm-mok; built modules will be signed before insertion`, and per build `Signing <path>/v4l2loopback.ko with the enrolled MOK key`.

3. The module actually loaded, and the kernel did not reject it:

   ```console
   lsmod | grep v4l2loopback
   dmesg | grep -i -e v4l2loopback -e 'module verification failed'
   ```

   Expected: `v4l2loopback` present in `lsmod`, and **no** `module verification failed: signature and/or required key missing` line. That message is the exact Secure Boot rejection signature.

4. The signature is attached to the module file:

   ```console
   modinfo v4l2loopback | grep -i -e sig_id -e signer
   ```

   Expected: a `sig_id`/`signer` line naming the MOK subject.

5. KMM mode: signing is a KMM stage, so read it there  - 

   ```console
   kubectl describe module kasm-agent-kasm-node-prep-v4l2loopback
   kubectl logs -n kmm-operator-system deploy/kmm-operator-controller
   ```

## Chart values

Umbrella (`kasm-agent`) form - build mode:

```yaml
nodePrep:
  enabled: true
  modules:
    v4l2loopback:
      enabled: true
  secureBoot:
    existingMokSecret: kasm-mok-keys   # data keys: mokPrivateKey (PEM), mokPublicKey (DER)
```

KMM mode:

```yaml
nodePrep:
  enabled: true
  modules:
    v4l2loopback:
      enabled: true
      method: kmm
      kmm:
        image:
          registry: registry.example.internal
          repository: kasm/v4l2loopback
        sign:
          enabled: true
          keySecret: kasm-mok-key      # data key: key   (PEM private key)
          certSecret: kasm-mok-cert    # data key: cert  (DER certificate)
```

Under [kasm-platform](../../../charts/kasm-platform/README.md), nest either block under `kasm-agent:` (`kasm-agent.nodePrep.secureBoot.existingMokSecret`). Installing `charts/kasm-node-prep` standalone drops the alias: `secureBoot.existingMokSecret` and `modules.v4l2loopback.kmm.sign.*` at the top level.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Module builds successfully, then `insmod` fails; `dmesg` shows `module verification failed: signature and/or required key missing` | Secure Boot is on and the module is unsigned, or was signed with a key that is not enrolled | Set `nodePrep.secureBoot.existingMokSecret` (build) or `nodePrep.modules.v4l2loopback.kmm.sign.enabled` (KMM), and confirm the *same* certificate appears in `mokutil --list-enrolled` |
| `mokutil --import` was run, but `mokutil --list-enrolled` still does not show the key | Enrolment is only committed in the UEFI MOK Manager at the next boot; the reboot was skipped or the prompt was not completed | Reboot with console access and complete *Enroll MOK* → *Continue* → password |
| Signing fails in build mode on a pre-baked builder image | `openssl` is missing - the kernel's `sign-file` helper needs it, and the presence check looks for it whenever Secure Boot signing is configured | Add `openssl` (with `build-essential kmod libelf1`) to the builder image |
| Render fails with `nodePrep.modules.v4l2loopback.kmm.sign.enabled: true` | `keySecret` and `certSecret` are both required when signing is enabled | Set both, with the data keys `key` and `cert` respectively |
| KMM sign stage fails to start on an airgapped cluster | The KMM **sign** image was not mirrored - it is only pulled when signing is enabled, so it is easy to miss | `make images-agent` lists it under `# KMM mode`; mirror it and re-run `make kmm-install-mirrored KMM_IMAGE_REGISTRY=<mirror>` |
| Everything is configured, but nothing needed signing | Secure Boot is off on these nodes (`mokutil --sb-state` reports `SecureBoot disabled`) - the default on EKS/GKE/AKS node images | Leave `secureBoot.existingMokSecret` empty; the row does not apply |

## Decisions

- [ ] `mokutil --sb-state` confirms Secure Boot is actually enabled (otherwise stop here).
- [ ] MOK key pair generated with the module-signing x509 extensions (`codeSigning`, `CA:FALSE`).
- [ ] `MOK.priv` stored as a cluster-root-grade secret.
- [ ] `mokutil --import MOK.der` run **and** the reboot MOK Manager prompt completed on every node (or the key baked into the node image).
- [ ] `mokutil --list-enrolled` shows the certificate on each node.
- [ ] Secret(s) created in the release namespace with the exact data keys: `mokPrivateKey`/`mokPublicKey` (build) or `key`/`cert` (KMM).
- [ ] `nodePrep.secureBoot.existingMokSecret` set, or `nodePrep.modules.v4l2loopback.kmm.sign.enabled` + both sign Secrets set.
- [ ] Builder image carries `openssl` (build mode, pre-baked images).
- [ ] Airgap + KMM: the KMM sign image mirrored.
- [ ] `dmesg` shows the module loading with no `module verification failed` line.
