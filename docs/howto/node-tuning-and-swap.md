# Node tuning and swap

> **Applies to:** no numbered feature-matrix row — this is the node-side half of [kasm-agent § Workspace node best practices](../../charts/kasm-agent/README.md#workspace-node-best-practices), the tuning Kasm's Docker-agent installer performs on a host and a Kubernetes node never gets. It underpins session stability for rows **1** (core workspace) and **18** (node targeting / pool assignment) · **Charts/values:** `nodePrep.tuning.swap.enabled`, `nodePrep.tuning.swap.sizeMib`, `nodePrep.tuning.swap.hostPath`, `nodePrep.tuning.swap.swappiness`, `nodePrep.tuning.swap.force`, `nodePrep.tuning.sysctls.enabled`, `nodePrep.tuning.sysctls.values`

## Why this is needed

Kasm's own agent installer creates a swapfile on every Docker agent host and the documentation is blunt about why: *"it is imperative to a have a swap file for Kasm to be stable"* — without it, *"user desktops being destroyed when RAM is over subscribed"*. Swap lets the kernel park the memory of **idle and stopped** sessions on disk instead of the OOM killer taking out a live one.

A Kubernetes node never runs that installer. `nodePrep.tuning` is the replacement, and it is **off by default** because, unlike loading a module, it changes how the node itself behaves:

- **`tuning.swap`** — a swapfile of `0.5 × RAM` clamped to `[4096, 16384]` MiB, plus `vm.swappiness`.
- **`tuning.sysctls`** — inotify limits, which desktop sessions consume disproportionately (the kernel's `max_user_instances` limit of 128 is **per UID**, and all workspace sessions on a node share one).

Nothing is written to `/etc/fstab` or `/etc/sysctl.d`. The reconcile loop re-asserts the state every pass, which is what makes it survive a reboot and what makes backing it out a values change.

**Swap has a hard prerequisite the chart cannot satisfy.** A kubelet running with the default `failSwapOn: true` **refuses to start** while the node has swap active. Enabling swap under such a kubelet looks fine until the next kubelet restart or node reboot — possibly weeks later — and then the node goes `NotReady`. `kasm-node-prep` therefore **refuses to create swap** until it can read the kubelet's swap tolerance off the node's disk.

## Before you start

- Read [kasm-node-prep § Node tuning](../../charts/kasm-node-prep/README.md#node-tuning) and the fully commented [`examples/kasm-agent/k3s-node-swap-config.yaml`](../../examples/kasm-agent/k3s-node-swap-config.yaml). Nothing in that example file is applied by any chart — they are node files.
- Requirements: **cgroup v2** (every current distribution), and Kubernetes ≥ 1.30 for `LimitedSwap` in beta (`NodeSwap` is stable as of 1.36).
- A node disk with room for the swapfile at `tuning.swap.hostPath` (default `/var/lib/kasm-node-prep`). **ext4 and xfs work**; btrfs needs a `nodatacow` file; overlayfs and tmpfs never will.
- **The order is not negotiable:** kubelet first, `swap.enabled` second. Rolling back reverses it.
- Distro variants:
  - **k3s** — `kubelet-arg: [fail-swap-on=false, config=/etc/rancher/k3s/kubelet.yaml]` in `/etc/rancher/k3s/config.yaml` (or a `config.yaml.d/*.yaml` drop-in), with a standalone `KubeletConfiguration` at the referenced path. Restart `k3s` (servers) / `k3s-agent` (agents).
  - **kubeadm / vanilla** — set `failSwapOn: false` and `memorySwap.swapBehavior: LimitedSwap` in `/var/lib/kubelet/config.yaml`, then `systemctl restart kubelet`.
  - **Managed (EKS / AKS / GKE)** — you may not be able to set `failSwapOn` at all. Each provider exposes only a subset of kubelet configuration through its own node-pool mechanism, and the node-prep check reads only `/etc/rancher/k3s/…` and `/var/lib/kubelet/config.yaml`. Prove the setting is live with `configz` (below) before enabling swap; if you cannot make it, **do not enable swap** — leave `tuning.sysctls` on and stop there.
  - **OpenShift** — kubelet configuration is a `KubeletConfig` MachineConfig object; the node reboots to apply it. Same ordering rule.
- The namespace must permit the `privileged` PSS: [privileged workloads and cluster policy](privileged-workloads-and-policies.md).

## Steps

1. **Sysctls first — they have no prerequisite.** Safe to turn on immediately:

   ```console
   helm upgrade --install kasm-agent charts/kasm-agent -n kasm-agent \
     --set nodePrep.enabled=true \
     --set nodePrep.tuning.sysctls.enabled=true
   ```

   The map **merges** with the chart defaults (`fs.inotify.max_user_instances: 1024`, `fs.inotify.max_user_watches: 524288`), so adding a key keeps them; set a key to `null` to drop one.

2. **Configure the node's kubelet for swap.** *k3s* — write both files on every workspace node:

   `/etc/rancher/k3s/config.yaml` (or `/etc/rancher/k3s/config.yaml.d/10-kasm-workspace-node.yaml`):

   ```yaml
   kubelet-arg:
     - fail-swap-on=false
     - config=/etc/rancher/k3s/kubelet.yaml
   ```

   `/etc/rancher/k3s/kubelet.yaml`:

   ```yaml
   apiVersion: kubelet.config.k8s.io/v1beta1
   kind: KubeletConfiguration
   failSwapOn: false
   memorySwap:
     swapBehavior: LimitedSwap
   ```

   Both keys matter: `failSwapOn: false` lets the kubelet start, `LimitedSwap` is what actually hands pods any of it. The example file also carries the four kubelet settings worth changing on a workspace node (`imageGCHighThresholdPercent: 90` / `imageGCLowThresholdPercent: 80`, `containerLogMaxSize`/`containerLogMaxFiles`, `podPidsLimit: 8192`) — see [kasm-agent § Settings this chart cannot make for you](../../charts/kasm-agent/README.md#settings-this-chart-cannot-make-for-you).

   *kubeadm:* put `failSwapOn: false` and the same `memorySwap` block in `/var/lib/kubelet/config.yaml`.

3. **Restart the kubelet and confirm the node came back.**

   ```console
   sudo systemctl restart k3s          # k3s servers
   sudo systemctl restart k3s-agent    # k3s agents
   sudo systemctl restart kubelet      # kubeadm and most others

   kubectl get node <node>             # must be Ready before continuing
   ```

4. **Only now enable swap in the chart:**

   ```console
   helm upgrade --install kasm-agent charts/kasm-agent -n kasm-agent \
     --set nodePrep.enabled=true \
     --set nodePrep.tuning.sysctls.enabled=true \
     --set nodePrep.tuning.swap.enabled=true
   ```

   Leave `nodePrep.tuning.swap.sizeMib` at `0` for the auto rule (half of `MemTotal`, clamped to 4–16 GiB) unless you have a better number. The next reconcile pass — within `nodePrep.reconcileIntervalSeconds` (300s default) — picks it up; no rollout needed after fixing a node.

5. **Keep workspace pods Burstable.** `LimitedSwap` gives swap **only** to Burstable pods, proportionally:

   ```text
   pod swap limit = (pod memory request / node MemTotal) × total node swap
   ```

   A default workspace (2768Mi) on a 16 GiB node with an 8 GiB swapfile gets ≈ 1384 MiB. A **Guaranteed** workspace (memory request == limit) and a BestEffort one both get **zero**. Do not pin workspace memory requests to their limits if swap is the point.

6. **`nodePrep.tuning.swap.force` is the escape hatch, and it is dangerous.** It skips the safety check entirely. Use it only when the kubelet is configured somewhere the script cannot read (a systemd drop-in, a cloud-init unit) **and** you have verified `failSwapOn: false` via `configz`.

7. **Rolling back, in reverse order:** set `nodePrep.tuning.swap.enabled=false` and upgrade *first* (so the loop stops re-activating swap), then on each node `sudo swapoff /var/lib/kasm-node-prep/kasm.swap && sudo rm -f /var/lib/kasm-node-prep/kasm.swap`, and only then remove the kubelet setting and restart. Removing the kubelet setting while swap is still active is the same footgun in reverse.

## Verify

1. The kubelet really has the settings (this is the authoritative check, and the only one that works on managed node pools):

   ```console
   kubectl get --raw "/api/v1/nodes/<node>/proxy/configz" | jq '.kubeletconfig | {failSwapOn, memorySwap}'
   ```

   Expected:

   ```json
   { "failSwapOn": false, "memorySwap": { "swapBehavior": "LimitedSwap" } }
   ```

2. The chart confirmed it, in the pod log:

   ```console
   kubectl -n kasm-agent logs -l app.kubernetes.io/component=node-prep | grep -i swap
   ```

   Expected — and the refusal message must be **gone**:

   ```text
   kubelet swap support confirmed: /etc/rancher/k3s/config.yaml carries fail-swap-on=false
   Creating a 8192 MiB swapfile at /var/lib/kasm-node-prep/kasm.swap
   Swap is active: /var/lib/kasm-node-prep/kasm.swap (8192 MiB)
   ```

   (kubeadm nodes log `kubelet swap support confirmed: /var/lib/kubelet/config.yaml sets failSwapOn: false`.)

3. On the node:

   ```console
   swapon --show
   ```

   ```text
   NAME                            TYPE SIZE USED PRIO
   /var/lib/kasm-node-prep/kasm.swap file   8G   0B   -2
   ```

4. Sysctls applied:

   ```console
   sysctl fs.inotify.max_user_watches fs.inotify.max_user_instances
   ```

   Expected: `fs.inotify.max_user_watches = 524288` and `fs.inotify.max_user_instances = 1024`.

5. A settled pass reports the node is where you asked:

   ```text
   --- reconcile pass complete: the node is in the requested state ---
   ```

## Chart values

Umbrella (`kasm-agent`) form:

```yaml
nodePrep:
  enabled: true
  tuning:
    sysctls:
      enabled: true
      values:
        # Merges with the chart defaults; set a key to null to drop one.
        fs.inotify.max_user_instances: 1024
        fs.inotify.max_user_watches: 524288
    swap:
      enabled: true          # ONLY after the node's kubelet tolerates swap
      sizeMib: 0             # 0 = half of MemTotal, clamped to [4096, 16384]
      hostPath: /var/lib/kasm-node-prep
      swappiness: 80
      force: false           # skips the kubelet safety check — dangerous
```

Under [kasm-platform](../../charts/kasm-platform/README.md), nest the block under `kasm-agent:` (`kasm-agent.nodePrep.tuning.swap.enabled`). Installing `charts/kasm-node-prep` standalone drops the alias: `tuning.swap.*` and `tuning.sysctls.*` at the top level.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Pod log: `tuning.swap.enabled is set, but this node's kubelet could not be confirmed to tolerate swap: neither /etc/rancher/k3s/config.yaml nor … carries 'fail-swap-on=false', and /var/lib/kubelet/config.yaml does not set 'failSwapOn: false'` — no swapfile is created | The safety check did its job: the kubelet is not (readably) configured for swap | Apply the kubelet config for your distro, restart the kubelet, and wait one reconcile pass. No Helm rollout needed |
| Kubelet is configured, but via a systemd drop-in or a cloud-init unit, and the log still refuses | The check reads only `/etc/rancher/k3s/config.yaml{,.d/*.yaml}` and `/var/lib/kubelet/config.yaml` | Verify `failSwapOn: false` via `configz`, then set `nodePrep.tuning.swap.force=true` |
| Node went `NotReady` at its next reboot, weeks after enabling swap | Swap was activated under a kubelet still defaulting to `failSwapOn: true` — typically via `force` without verifying | On the node: `swapoff -a`, bring the kubelet up, then fix the kubelet config before re-enabling swap |
| `swapon --show` shows the swapfile, but sessions never use any of it | Either `memorySwap.swapBehavior` is not `LimitedSwap` (the kubelet tolerates swap but grants none), or the workspace pods are Guaranteed/BestEffort | Set `swapBehavior: LimitedSwap` in the kubelet config; keep workspace memory request below its limit so the pod is Burstable |
| Swapfile creation fails on the chosen path | `hostPath` is on overlayfs, tmpfs, or a btrfs volume without `nodatacow` | Point `nodePrep.tuning.swap.hostPath` at an ext4/xfs directory on a real node disk with room for `sizeMib` |
| Sysctls and swap are gone after a node reboot, then reappear | Nothing is persisted to `/etc/sysctl.d` or `/etc/fstab` by design — the reconcile loop is the persistence mechanism | Expected. The gap is at most `nodePrep.reconcileIntervalSeconds` (300s); lower it if the window matters |
| `helm uninstall` leaves swap active and sysctls raised | `tuning.*` changes **node-wide** state that outlives the pod | Follow the rollback order in step 7 (`swapoff` + `rm`), or reboot the node — nothing was persisted |
| Changing `sizeMib` appears to do nothing | An already-**active** swapfile is not replaced mid-flight; only an inactive one of the wrong size is recreated | `swapoff` the file on the node and let the next pass rebuild it at the new size |

## Checklist

- [ ] `tuning.sysctls.enabled=true` — no prerequisites, do this first.
- [ ] cgroup v2 and Kubernetes ≥ 1.30 confirmed.
- [ ] Kubelet configured **before** the chart: `failSwapOn: false` **and** `memorySwap.swapBehavior: LimitedSwap`.
- [ ] Kubelet restarted; node back `Ready`.
- [ ] `configz` shows both settings live.
- [ ] Only then `nodePrep.tuning.swap.enabled=true`.
- [ ] `hostPath` on ext4/xfs with room for the swapfile.
- [ ] Workspace pods left **Burstable** (memory request < limit), or accept zero swap for them.
- [ ] Pod log shows `kubelet swap support confirmed…` and `Swap is active: …`; the refusal message is gone.
- [ ] `swapon --show` and `sysctl fs.inotify.max_user_watches` confirm on the node.
- [ ] `tuning.swap.force` left `false` unless the kubelet config is genuinely unreadable *and* verified via `configz`.
- [ ] Rollback order understood: chart off → `swapoff` + `rm` → kubelet setting removed.
