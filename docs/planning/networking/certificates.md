# Certificates

> **Applies to:** every external-access mechanism · **Charts/values:** `kasm-helm.certificate.*`, `kasm-helm.trustedCaBundle.*`, `kasm-helm.ingress.tls`, `agent.sessionProxy.certificate.*`, `agent.sessionProxy.certSecretName`

**Read this before picking a mechanism.** Certificates are the one part of external access that is
the same work whichever of [Ingress](ingress.md), [Gateway API](gateway-api.md),
[OpenShift Route](openshift-route.md) or [a published Service](loadbalancer-nodeport.md) you
choose — and the part that most often turns a correct-looking install into a session that will not
start.

The two halves hold **separate** certificates, because they are separate hostnames. Getting one
right does not get the other right.

## Certificates

Browsers connect to the session proxy directly, so on any passthrough or direct-Service path its
certificate must be **publicly trusted** — a cluster-internal CA is not enough. Cover the public
hostname **and** its wildcard, because sessions are served on names beneath it:

> **A parent wildcard is not enough.** A TLS wildcard matches exactly one label, so
> `*.example.com` covers `sessions.example.com` but **not** `*.sessions.example.com`. One
> `*.example.com` certificate cannot serve both halves; list the names explicitly, or issue a
> certificate per half.

(On the proxied topology none of this applies to the *session proxy* — the browser never reaches it,
so its certificate can be self-signed. See
[Direct-connect or proxied](README.md#direct-connect-or-proxied). The **control plane's** certificate
still has to be trusted, because that is where the session WebSocket terminates.)

> **A self-signed certificate means a browser warning on every hostname involved.** Accept it, or
> issue certificates from a CA the browser already trusts. Note that a click-through exception *does*
> extend to `wss://` connections on the same origin — verified on Chrome 152 — so the warning itself
> is not what breaks session streaming.


```yaml
agent:
  sessionProxy:
    certificate:
      enabled: true
      issuerRef:
        kind: ClusterIssuer
        name: letsencrypt-prod
      dnsNames:
        - sessions.example.com
        - "*.sessions.example.com"
```

Bringing your own instead: create a `kubernetes.io/tls` Secret in the release namespace and set
`agent.sessionProxy.certSecretName`. Either way the Secret must exist — the proxy will not start
without it, even when TLS is terminated in front of it.

On the control-plane side, either supply `kasm-helm.certificate.secretName` or let cert-manager
issue it, keeping the wildcard on:

```yaml
kasm-helm:
  certificate:
    secretName: kasm-tls
    certManager:
      enabled: true
      addWildCard: true
      issuerName: letsencrypt-prod
      issuerKind: ClusterIssuer
```

## TLS is not optional for container sessions

Serving Kasm over plain HTTP does not work, and it is worth knowing exactly why before anyone tries
it: the control plane builds session URLs with a **hard-coded `https` scheme** for container /
KasmVNC workspace sessions. It is not derived from the page's origin, the `X-Forwarded-Proto`
header, or the zone's `proxy_port` — none of which change it.

Verified end to end: an install fronted by an HTTP-only ingress, browsed over `http://` (confirmed
from the proxy's access log), with `proxy_port: 80` on the zone and `X-Forwarded-Port: 80` reaching
the API, still handed the browser an `https://…` session URL.

The scheme *is* configurable for one family of sessions — RDP, VNC and SSH proxied through the
Guacamole connection proxy use the API's `internal_schema` setting (`SERVER_INTERNAL_SCHEMA`,
default `https`). Container sessions, which is what most deployments run, have no such switch.

**So every Kasm deployment needs a working certificate, and for sessions to start it must be one the
browser trusts** — see the callout above. There is no HTTP-only evaluation mode to fall back on.

## The control plane's certificate

The control plane's certificate covers `publicAddr`. Three ways to supply it:

| Values | Where the certificate comes from |
| ------ | -------------------------------- |
| `certificate.certManager.enabled=true` | cert-manager issues it from `issuerName`/`issuerKind`/`issuerGroup` into `certificate.secretName`. `addWildCard: true` (the default) adds `*.<publicAddr>` to the SANs. |
| `certificate.secretName` alone | You created the `kubernetes.io/tls` Secret yourself; the chart only references it. |
| Neither | Whatever fronts the cluster holds the certificate — a cloud load balancer's ACM/Key Vault certificate, or the OpenShift router's default. |

With an Ingress, `ingress.tls: true` wires the Secret into the Ingress. **With the Gateway API it
does not**, because a Gateway API route carries no certificate at all — see
[Gateway API](gateway-api.md#certificates-live-on-the-gateway-not-the-route).

Check what actually got issued rather than what you asked for:

```console
$ kubectl -n kasm get secret kasm-tls -o jsonpath='{.data.tls\.crt}' \
    | base64 -d | openssl x509 -noout -subject -ext subjectAltName -dates
subject=CN = kasm.example.com
X509v3 Subject Alternative Name:
    DNS:kasm.example.com, DNS:*.kasm.example.com
notBefore=Sep  8 10:14:00 2026 GMT
notAfter=Dec  7 10:13:59 2026 GMT
```

A missing `notAfter`, or a SAN list that does not contain the name the browser will use, is the
failure — not a warning.

## Multi-zone coverage

With `kasmZones` set, the control plane answers on `publicAddr` **and** on every zone's
`proxy_hostname`. One certificate has to cover all of them, or the zones users are routed to fail
while the primary works:

```yaml
kasm-helm:
  publicAddr: kasm.example.com
  kasmZones:
    - name: zonea
      proxy_hostname: zonea.kasm.example.com
      primary: true
    - name: zoneb
      proxy_hostname: zoneb.kasm.example.com
```

A wildcard on the shared parent (`*.example.com`) covers all three names at once, which is why the
hostname pair is chosen under one parent in the first place — see
[the hostname pair](README.md#the-hostname-pair-and-the-authorization-domain). Without a wildcard,
list every name explicitly in the Certificate's `dnsNames`.

## Internal CA bundles

Internal CAs **inside the cluster** go in with `kasm-helm.trustedCaBundle.enabled=true` and
`kasm-helm.trustedCaBundle.caCerts`. CA certificates *inside sessions* are a different mechanism
entirely — file mappings under `/usr/local/share/ca-certificates/` plus an `update-ca-certificates`
start command.
