# Kasm Workspaces Control Plane

This chart installs the Kasm Workspaces control plane: the web UI and API, the manager, the session
proxy, the connection proxy (Guacamole, RDP Gateway and RDP HTTPS Gateway) and a bundled PostgreSQL
database. An external PostgreSQL can be used instead of the bundled one.

It is the control plane only. Sessions run on agents, which this chart does not deploy: install the
`kasm-agent` chart alongside it, or install `kasm-platform`, which bundles both.

Three settings matter on first install:

- **Public hostname** (`publicAddr`): the DNS name users open and the certificate is issued for.
- **Exposure**: a `LoadBalancer` Service by default, or an Ingress. Installed from Rancher the default is a `NodePort` Service instead, because RKE2 ships no LoadBalancer implementation; `proxyService.type` sets it explicitly. The chart also supports the
  Gateway API and OpenShift Routes through the YAML editor.
- **Certificate**: a generated self-signed certificate by default, an existing TLS Secret, or
  cert-manager.

After the install, log in as `admin@kasm.local`. The password is generated and stored in the Secret
`<release>-secrets` under the key `admin-password`; the `manager-token` key in the same Secret is the
token agents present when they register.

Source and issues: https://github.com/kasmtech/kasm-helm. Product documentation: https://kasm.com/docs
