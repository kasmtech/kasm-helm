# Certificates

> **Applies to:** both halves

## Why this is needed

Serving Kasm over plain HTTP does not work: the control plane builds container-session URLs with a
hard-coded `https` scheme, whatever the page's origin or `X-Forwarded-Proto` says. So every
deployment has a control-plane certificate, and on direct-connect a session-proxy certificate
browsers trust as well. The two halves hold **separate** certificates, because they are separate
hostnames; getting one right does not get the other right.

## Before you start

- Know the topology. On the relayed default the browser never reaches the session proxy, so its
  certificate can be anything, the self-signed default included. Only the control plane's
  certificate is shown to browsers. On direct-connect both are.
- Know where TLS terminates for each half ([Networking](README.md)): at an Ingress, Gateway or
  edge Route the front end holds the certificate; on passthrough and published-Service paths the
  workload does.
- cert-manager with an `Issuer` or `ClusterIssuer`, if certificates are to be issued in-cluster.

> **Note.** With nothing configured, both halves generate self-signed certificates:
> `<release>-cert-manager` (CN = `publicAddr`, or `kasm.local`) and `kasm-session-proxy-tls`. They
> are reused across upgrades, regenerated on a hostname change, and never overwrite a Secret of the
> same name that somebody else created. Browsers warn on them, and a click-through does extend to
> the `wss://` session connection on the same origin, so they are enough for an evaluation.

## Steps

1. **The control plane's certificate covers `kasm-helm.publicAddr`.** Three ways to supply it:

   | Values | Where it comes from |
   | ------ | ------------------- |
   | `kasm-helm.certificate.certManager.enabled=true` | cert-manager issues it from `issuerName`, `issuerKind` and `issuerGroup` into `certificate.secretName`; `addWildCard: true` (the default) adds `*.<publicAddr>` |
   | `kasm-helm.certificate.secretName` alone | you created the `kubernetes.io/tls` Secret; the chart only references it |
   | neither | the self-signed default, into `<release>-cert-manager` |

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

   With an Ingress, `kasm-helm.ingress.tls: true` wires the Secret into the Ingress. With the
   Gateway API it does not, because a route carries no certificate; reference the Secret from the
   Gateway's listener ([Gateway API: HTTPRoute](gateway-api-httproute.md#certificates-live-on-the-gateway-not-the-route)).

2. **Direct-connect only: the session proxy's certificate covers `kasm-agent.agent.publicHostname`
   and its wildcard.** Sessions are served on names beneath the public hostname, so on passthrough
   and published-Service paths the certificate needs `sessions.example.com` **and**
   `*.sessions.example.com`, from a CA browsers trust.

   ```yaml
   kasm-agent:
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

   Bringing your own: create a `kubernetes.io/tls` Secret named `kasm-session-proxy-tls` (or
   whatever `agent.sessionProxy.certSecretName` says) in the release namespace **before the first
   install**; the chart leaves it untouched.

   > **Note.** The session proxy picks a new certificate up on its next restart, and the operator
   > does not restart it when the Secret changes: after a `publicHostname` change (which
   > regenerates the self-signed Secret), a cert-manager issue, or a renewal, the old certificate
   > is served until the pod is replaced. Run
   > `kubectl -n <ns> delete pod -l app.kubernetes.io/component=session-proxy` after each change, and plan
   > the same for cert-manager renewals until the operator handles it.

   > **Warning.** A parent wildcard is not enough. A TLS wildcard matches exactly one label, so
   > `*.example.com` covers `sessions.example.com` but **not** `*.sessions.example.com`. One
   > `*.example.com` certificate cannot serve both halves on those paths; list the names explicitly,
   > or issue a certificate per half. Behind an Ingress or HTTPRoute that terminates TLS, one
   > certificate covering both hostnames is enough.

3. **Multi-zone: cover every zone hostname.** With `kasm-helm.kasmZones` set, the control plane
   answers on `publicAddr` **and** on every zone's `proxy_hostname`; one certificate has to cover
   all of them, or the zones users are routed to fail while the primary works.
   `certManager.addWildCard: true` adds `*.<publicAddr>`, so `*.kasm.example.com`, which covers
   `zonea.kasm.example.com` and `zoneb.kasm.example.com` because those sit one label beneath
   `publicAddr`. Zone hostnames shaped any other way (`zonea.example.com` beside
   `kasm.example.com`) are not covered by that wildcard; list every name in `dnsNames` then.

4. **Internal CAs inside the cluster** go in with `kasm-helm.trustedCaBundle.enabled=true` and
   `kasm-helm.trustedCaBundle.caCerts`. CA certificates *inside sessions* are a different mechanism:
   a file mapping under `/usr/local/share/ca-certificates/` plus an `update-ca-certificates` start
   command.

## Verify

Check what was issued rather than what was asked for:

```console
kubectl -n kasm get secret kasm-tls -o jsonpath='{.data.tls\.crt}' \
    | base64 -d | openssl x509 -noout -subject -ext subjectAltName -dates
```

Expected:

```text
subject=CN = kasm.example.com
X509v3 Subject Alternative Name:
    DNS:kasm.example.com, DNS:*.kasm.example.com
notBefore=<issue date> GMT
notAfter=<expiry date> GMT
```

A SAN list that does not contain the name the browser will use is the failure. On direct-connect,
run the same check against `kasm-session-proxy-tls` in the agent namespace and expect both
`sessions.example.com` and `*.sessions.example.com`. Then compare what is **served** with what is
in the Secret, because the session proxy keeps the old one until restarted:

```console
kubectl -n kasm-agent get secret kasm-session-proxy-tls -o jsonpath='{.data.tls\.crt}' \
    | base64 -d | openssl x509 -noout -fingerprint -sha256
echo | openssl s_client -servername sessions.example.com -connect sessions.example.com:443 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256
```

Expected: the same fingerprint twice on a passthrough or published-Service path (behind an
Ingress or HTTPRoute the second one is the front end's certificate). Different fingerprints mean
the pod predates the Secret: restart it.

## Chart values

```yaml
kasm-helm:
  publicAddr: kasm.example.com
  certificate:
    secretName: kasm-tls
    certManager:
      enabled: true
      addWildCard: true
      issuerName: letsencrypt-prod
      issuerKind: ClusterIssuer

kasm-agent:                          # direct-connect only
  agent:
    publicHostname: sessions.example.com
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

Installing the charts directly, drop the `kasm-helm:` and `kasm-agent:` keys.

## Troubleshooting

[Troubleshooting](../../reference/troubleshooting.md). A browser certificate warning on the session
hostname is a certificate that does not cover it (or the self-signed default still in place); a
cert-manager Certificate stuck at `READY False` is almost always the ACME challenge, which
`kubectl describe certificate` names.

## Decisions

- [ ] Control-plane certificate: cert-manager, a Secret you created, or the self-signed default accepted for evaluation.
- [ ] Direct-connect only: session-proxy certificate publicly trusted, covering the hostname and its wildcard where browsers reach the proxy directly.
- [ ] Session-proxy pods restarted after every certificate change; renewals planned the same way.
- [ ] Multi-zone: one certificate covering `publicAddr` and every `proxy_hostname`.
- [ ] Gateway API: the Secret referenced from the listener, with a `ReferenceGrant` if namespaces differ.
- [ ] Internal CAs added through `trustedCaBundle`, and inside sessions through a file mapping.
