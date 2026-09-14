# Egress installer: node prerequisites

> **Applies to:** agent · **Charts/values:** `egressInstaller.enabled`, `egressInstaller.distro`, `egressInstaller.cniBinDir`, `egressInstaller.cniConfDirs`, `egressInstaller.socketDir`, `egressInstaller.excludedCIDRs`, `egressInstaller.priorityClassName`, `egressInstaller.updateStrategy`

## Why this is needed

`kasm-egress-installer` is a chained-CNI design. The daemon:

1. installs its bundled `kasm-egress-cni` shim binary into the node's **CNI plugin bin dir**;
2. patches every active `.conflist` in `egressInstaller.cniConfDirs` to chain that shim into the plugin list, backing each file up **once** to a sibling `.kasm-egress.bak`;
3. from then on proxies every pod's CNI `ADD` on that node through the shim, passing ordinary pods through unchanged and `nsenter`-ing a session's netns to bring up an OpenVPN / WireGuard / Ziti tunnel when its annotations ask for one.

Two node facts decide whether that works, and neither is a chart concern:

- **The bin dir must be the one your runtime actually loads plugins from.** Install it anywhere else and the runtime never invokes the shim - nothing errors, the DaemonSet stays `Running`, the conflists still look patched, and sessions get no egress tunnel. This is the chart's one silent-failure knob.
- **The runtime must honour chained CNI plugins.** Verified live on k3s, and on containerd 2.2 under kubeadm with Cilium 1.20 (after the Cilium preparation below); RKE2's containerd is the other known-good runtime. **CRI-O is known-bad** (1.32, Cilium 1.20): when it loads a conflist it probes every plugin with the CNI `VERSION` command, the shim forwards that probe to its daemon, the daemon rejects it (`missing CNI_CONTAINERID`), and CRI-O drops the whole conflist. From then on every pod sandbox on that node fails with `no CNI configuration file in /etc/cni/net.d/`, not only Kasm's. Leave `egressInstaller.enabled=false` on CRI-O nodes until the shim answers `VERSION` itself; the installer's cleanup restores the conflist when it is disabled again.

Read [kasm-egress-installer § Read this before installing](../../../charts/kasm-egress-installer/README.md#read-this-before-installing) before going further - the no-daemon failure window described there is a real operational decision, not boilerplate.

## Before you start

- **The namespace must permit `privileged` *and* host namespaces.** This DaemonSet runs `hostPID: true` and `hostNetwork: true`, so a blanket `disallow-host-namespaces` Kyverno/OPA rule rejects it even in a `privileged` namespace. Settle that first: [privileged workloads and cluster policy](../nodes/privileged-workloads.md).
- **Accept the no-daemon window.** The shim hard-fails CNI `ADD` when it cannot reach the daemon's socket, and a failing chained plugin fails **every** pod sandbox on that node, not only Kasm's. Normally that window is a DaemonSet restart; a sustained crash-loop blocks all new scheduling on that node. Keep `egressInstaller.priorityClassName: system-node-critical` (the default).
- **Know your CNI bin dir:**

  | `egressInstaller.distro` | Bin dir it derives | Use for |
  | --- | --- | --- |
  | `vanilla` (default) | `/opt/cni/bin` | kubeadm, and most managed distributions |
  | `k3s` | `/var/lib/rancher/k3s/data/cni` | k3s |
  | anything else | none - `cniBinDir` is then **required** | RKE2 (its bin dir varies by version), OpenShift/Multus layouts, everything else |

  An unrecognized `distro` with no `cniBinDir` **fails template rendering** on purpose - a wrong directory is silent at runtime, so the chart would rather not install.
- Distro variants: **kubeadm / vanilla** - take the default. **k3s** - `distro: k3s`. **Managed (EKS / AKS / GKE)** - normally `/opt/cni/bin` (the default), but whether the managed CNI honours a chained plugin is a per-cluster fact: verify with the test pod in *Verify* before relying on it (GKE Autopilot cannot run this workload at all). **RKE2 / OpenShift** - set `cniBinDir` explicitly from the runtime's own config.
- `egressInstaller.cniConfDirs` and `egressInstaller.containerdConfigPaths` already cover the k3s / RKE2 / vanilla layouts as a **union** (`/etc/containerd/config.toml` and `/etc/containerd` included); entries that do not exist on a node are skipped, not errors. There is no matching `distro` choice for those. The daemon's image tag follows the chart's `appVersion`; `image.tag` overrides it.
- **On Cilium, prepare the CNI config first.** The Cilium agent rewrites its own `05-cilium.conflist` on any change under `/etc/cni/net.d`, so it undoes the egress shim's patch within about a second. Install Cilium with `cni.customConf=true` and `cni.exclusive=false`, then restart its agents - Cilium does not roll them on a config change by default:

  ```console
  kubectl -n kube-system rollout restart ds/cilium
  ```

  Verified on Cilium 1.20. Without both settings the DaemonSet looks healthy and the chaining never sticks.

## Steps

1. **Find the bin dir your runtime really reads.** The authoritative source is the containerd CNI section, not a guess:

   ```console
   # k3s
   sudo grep -n 'bin_dir\|conf_dir' /var/lib/rancher/k3s/agent/etc/containerd/config.toml
   # RKE2
   sudo grep -n 'bin_dir\|conf_dir' /var/lib/rancher/rke2/agent/etc/containerd/config.toml
   # kubeadm / managed
   sudo grep -rn 'bin_dir\|conf_dir' /etc/containerd/config.toml
   ```

   Cross-check that the directory actually holds plugin binaries:

   ```console
   ls /var/lib/rancher/k3s/data/cni    # k3s
   ls /opt/cni/bin                     # kubeadm / most managed
   ```

2. **Set `distro` (or `cniBinDir`) to match** and install. The default, `vanilla`, is
   `/opt/cni/bin`; on k3s say so:

   ```console
   helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent -n kasm-agent \
     --set egressInstaller.enabled=true \
     --set egressInstaller.distro=k3s
   ```

   For anything not `k3s` or `vanilla`, override outright:

   ```console
   helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent -n kasm-agent \
     --set egressInstaller.enabled=true \
     --set egressInstaller.distro=rke2 \
     --set egressInstaller.cniBinDir=/var/lib/rancher/rke2/bin
   ```

3. **Pin the daemon to the nodes that run sessions.** Every pod scheduled on a selected node depends on this daemon once it is installed, so narrowing `egressInstaller.nodeSelector` is a blast-radius decision, not only a placement one. Use the same selector as `nodePrep`/`videoDevicePlugin`.

4. **Leave `egressInstaller.socketDir` alone** unless you have a reason. It must stay a host path (`/var/run/kasm-egress`): the shim runs directly on the host, outside any pod, and has to reach the same path from there.

5. **Optional:** list CIDRs that should bypass the tunnel and use the pod's original default gateway in `egressInstaller.excludedCIDRs` (empty by default - nothing bypassed).

6. **Configure egress on the control plane, as on any Kasm.** Egress providers, gateways and
   credentials, and their assignment to users, groups and workspaces, are control-plane
   configuration and work the same on Kubernetes. Follow
   [Egress in the Kasm documentation](https://www.kasmweb.com/docs/latest/guide/egress.html); nothing there is Kubernetes-specific. The
   only Kubernetes-specific part is this page: the daemon on the nodes, which brings the assigned
   gateway's tunnel up inside the session's network namespace when the session starts.

7. **Uninstall gracefully, always.** `helm uninstall`, a `helm upgrade` that sets `egressInstaller.enabled=false`, a rolling update or a plain pod delete all take the cleanup path: each patched `.conflist` is restored from its `.kasm-egress.bak` and the shim binary is removed. The default 30s grace period is ample - cleanup takes well under a second. A **hard crash** skips that path; the chain stays patched until the replacement pod re-installs and re-verifies it.

## Verify

1. The daemon installed and chained itself - the three lines to look for:

   ```console
   kubectl -n kasm-agent logs -l app.kubernetes.io/component=egress-installer | \
     grep -E 'installed CNI shim|CNI conflist file|verified kasm-egress-cni'
   ```

   Expected, in order (the bin dir is the one `distro` derives; `/var/lib/rancher/k3s/data/cni` for
   `k3s`):

   ```text
   installed CNI shim at /opt/cni/bin/kasm-egress-cni
   updated 1 CNI conflist file(s) with kasm-egress-cni plugin
   verified kasm-egress-cni chaining in 1 conflist file(s) across 3 config dir(s)
   ```

   **The path in the first line is the check that matters**, and it is the only path the daemon
   logs: if it is not the directory step 1 found, the shim will never be invoked. A repeating
   `[ERROR] initial chained config ensure failed: kasm-egress-cni not present in any active CNI conflist`
   instead of the third line is the Cilium rewrite from *Before you start*.

2. The daemon's own status view (the image ships `curl`, not `wget`):

   ```console
   kubectl exec -n kasm-agent <pod> -- \
     curl -sS --unix-socket /var/run/kasm-egress/daemon.sock http://unix/status
   ```

   Expected: JSON with `"configured": true`, a `containerd` block whose `detected` is `true` when
   one of `containerdConfigPaths` exists on the node, and `detectedCniConfDirs` naming the
   directory the conflist lives in.

3. On the node - the shim binary, the patched conflist, and the backup beside it:

   ```console
   ls -l /var/lib/rancher/k3s/data/cni/kasm-egress-cni
   sudo grep -o 'kasm-egress-cni' /var/lib/rancher/k3s/agent/etc/cni/net.d/*.conflist
   ls -l /var/lib/rancher/k3s/agent/etc/cni/net.d/*.kasm-egress.bak
   ```

   Expected: the binary exists, `kasm-egress-cni` appears in the conflist, and exactly one `.kasm-egress.bak` sits beside each patched file.

4. **Pod networking still works** - the single most important check, because a broken chain fails every pod on the node, not only Kasm's:

   ```console
   kubectl run cni-probe --image=busybox --restart=Never --command -- sleep 300
   kubectl wait --for=condition=Ready pod/cni-probe --timeout=60s
   kubectl get pod cni-probe -o jsonpath='{.status.podIP}{"\n"}'
   kubectl delete pod cni-probe
   ```

   Expected: the pod reaches `Ready` and prints an IP.

5. **A session with a gateway assigned leaves through it.** Launch a session for a user or group
   that has an egress gateway assigned, then from inside it browse to an IP-echo site and compare
   the address with the gateway's location. From outside, the tunnel interface is visible in the
   session pod's network namespace:

   ```console
   kubectl -n kasm-agent exec <session pod> -- ip -brief link
   ```

   Expected: a `tun0` or `wg0` interface `UP` beside `eth0`, and the default route through it in
   `ip route`. Sessions without an assigned gateway show `eth0` only and are untouched.

   > **Note.** This end-to-end path, manager-assigned gateway to a tunnelled Kubernetes session, has
   > not been exercised in this repository's test runs yet; the CNI chaining has. Treat the check
   > above as the acceptance test for your own deployment.

6. After a graceful uninstall, re-run checks 3 and 4: the shim binary is gone, `kasm-egress-cni` no longer appears in any conflist, and a fresh test pod still gets an IP.

## Chart values

Umbrella (`kasm-agent`) form:

```yaml
egressInstaller:
  enabled: true
  distro: vanilla                 # vanilla (default) | k3s | anything else => set cniBinDir
  # cniBinDir: /var/lib/rancher/rke2/bin   # required when distro is not k3s/vanilla
  socketDir: /var/run/kasm-egress          # must stay a host path
  excludedCIDRs: []
  priorityClassName: system-node-critical
  updateStrategy: RollingUpdate
  nodeSelector:
    kasm.com/workspaces: "true"
```

Under [kasm-platform](../../../charts/kasm-platform/README.md), nest the block under `kasm-agent:` (`kasm-agent.egressInstaller.distro`). Installing `charts/kasm-egress-installer` standalone drops the alias: `distro`, `cniBinDir`, `cniConfDirs` at the top level.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| All pods on a node fail with `no CNI configuration file in /etc/cni/net.d/` as soon as the shim is chained (CRI-O) | CRI-O validates each plugin with a `VERSION` probe and discards a conflist whose plugin fails it; the shim forwards the probe to the daemon | Disable `egressInstaller` on CRI-O nodes; the cleanup restores the conflist, or restore it from `.kasm-egress.bak` |
| Conflist is patched, then reverts to stock a second later (Cilium) | The Cilium agent rewrites `05-cilium.conflist` whenever `/etc/cni/net.d` changes | Set `cni.customConf=true` and `cni.exclusive=false` on the Cilium install, then `kubectl -n kube-system rollout restart ds/cilium` |
| DaemonSet is `Running`, conflists look patched, sessions get **no** egress tunnel and nothing errors anywhere | The shim was installed into a directory the runtime does not read plugins from - the chart's silent-failure mode | Compare the `installed CNI shim at …` log line against the containerd `bin_dir` from step 1; set `egressInstaller.distro` correctly or override `egressInstaller.cniBinDir` |
| `helm install`/`template` fails: unrecognized `distro` with no `cniBinDir` | Deliberate - the chart refuses to guess a path whose wrongness would be silent | Set `egressInstaller.cniBinDir` explicitly |
| Pods on the node are stuck `ContainerCreating` with a CNI plugin error; **all** pods, not only Kasm's | No daemon is running, and the chained shim hard-fails CNI `ADD` when it cannot reach its socket. Normally a restart window; a crash-loop makes it permanent | Fix or scale the DaemonSet back up. Manual recovery: restore each `.conflist` from its sibling `.kasm-egress.bak` on the affected node |
| After a node reboot mid-uninstall (or an evicted, unrescheduled pod), the conflists are still patched | A hard crash skips the graceful cleanup path by design | The replacement pod re-installs and re-verifies on start; if no daemon is coming back, restore from `.kasm-egress.bak` by hand |
| Egress installer pods are rejected at admission while `nodePrep` pods are admitted | `hostPID` + `hostNetwork` are beyond the `privileged` PSS label and are gated by a separate policy engine | Scope a `PolicyException` for this namespace/ServiceAccount, or accept the workload outside the baseline set - see [privileged workloads and cluster policy](../nodes/privileged-workloads.md) |
| Ziti tunnels fail with `no installed ziti binary matches controller major.minor version` | The image bundles three pinned Ziti CLI versions; the controller runs a newer minor | Align the controller version with a bundled one, or track [kasm-egress-installer § Ziti version support](../../../charts/kasm-egress-installer/README.md#ziti-version-support) |
| Every tunnel on a node drops at once, and pod scheduling on that node briefly stops | The daemon was OOMKilled - all tunnel processes live in its cgroup, and the restart reopens the no-daemon window | Raise `egressInstaller.resources.limits.memory` on nodes hosting many egress sessions |
| A `helm upgrade` unrelated to egress briefly disturbs node scheduling | `updateStrategy: RollingUpdate` restarts the daemon, which is the no-daemon window | Expected. Use `updateStrategy: OnDelete` to control exactly when that happens |

## Decisions

- [ ] Egress providers, gateways and credentials configured on the control plane per Kasm's documentation.

- [ ] Namespace permits `privileged` **and** host namespaces (`hostPID`, `hostNetwork`) - policy exception decided and recorded.
- [ ] The no-daemon failure window explicitly accepted; `priorityClassName: system-node-critical` left in place.
- [ ] Runtime honours chained CNI plugins (k3s/RKE2 containerd verified; CRI-O known-bad; anything else proven with a test pod).
- [ ] On Cilium: `cni.customConf=true`, `cni.exclusive=false`, and the Cilium agents restarted after setting them.
- [ ] CNI bin dir determined from the runtime's containerd config, not guessed.
- [ ] `egressInstaller.distro` set (`k3s` / `vanilla`) or `egressInstaller.cniBinDir` overridden.
- [ ] `egressInstaller.socketDir` left as a host path.
- [ ] `nodeSelector` scoped to session nodes, matching the other node-level DaemonSets.
- [ ] Log shows `installed CNI shim at …`, `updated N CNI conflist file(s) with kasm-egress-cni plugin`, `verified kasm-egress-cni chaining in N conflist file(s) …`, and the shim path matches the runtime's bin dir.
- [ ] A `.kasm-egress.bak` exists beside each patched conflist.
- [ ] A throwaway test pod still gets an IP.
- [ ] Uninstall path rehearsed: graceful shutdown restores the conflists and removes the shim.
