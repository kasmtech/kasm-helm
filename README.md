# Kasm on Kubernetes

# kasm-single-zone

![Version: 1.17.0](https://img.shields.io/badge/Version-1.17.0-informational?style=flat-square) ![AppVersion: 1.17.0](https://img.shields.io/badge/AppVersion-1.17.0-informational?style=flat-square)

Kasm is a platform specializing in providing secure browser-based workspaces for a wide range of applications and industries. Its main goal is to provide isolated and secure environments that can be accessed via web browsers, ensuring that users can perform tasks without risking the security of their local systems.

**Homepage:** <https://kasmweb.com>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

**Non-Release branches are not intended for production**

Kasm has been modified to run inside Kubernetes. The service containers will automatically detect they are running in Kubernetes and they will talk directly to each other rather than assume they are talking through an NGINX server as is the case for a normal Kasm deployment. Additionally, components need to talk to the name of the service defined, not to individual containers. A Kubernetes service has a resolvable DNS name that all containers should be able to talk with. API containers will not talk to an individual rdp gateway or guac container, but rather be load balanced to all existing respective containers. The reverse is also true. The API servers have been modified to only return a single entry when guac or rdp gateways call to get a list of API servers.

## Branches

This project will contain a branch that matches the release version of the corresponding Kasm Workspaces release. For example, Kasm Workspaces 1.16.0 will have a branch `release/1.16.0` within this project. **Non-release branches should not be used for production.** Be sure to checkout the branch on this project that matches the version of Kasm Workspaces you intend to deploy. Use the default `develop` branch to deploy the [developer preview](https://kasmweb.com/docs/latest/developers/builds.html#developer-preview-builds) build of Kasm Workspaces.

## Installing the Chart

To install the chart with the release name `kasm-helm`:

```console
$ helm repo add kasm https://helm.kasmweb.com
$ helm install kasm-helm kasm/kasm-single-zone --namespace kasm-namespace
```

## Chart value settings in `values.yaml`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| annotations.certSecret | object | `{}` | Additional certSecret annotations to apply to resources created by this chart |
| annotations.configMap | object | `{}` | Additional configMap annotations to apply to resources created by this chart |
| annotations.deployment | object | `{}` | Additional deployment annotations to apply to resources created by this chart |
| annotations.ingress | object | `{}` | Additional ingress annotations to apply to resources created by this chart |
| annotations.pod | object | `{}` | Additional pod annotations to apply to resources created by this chart |
| annotations.secret | object | `{}` | Additional secret annotations to apply to resources created by this chart |
| annotations.service | object | `{}` | Additional service annotations to apply to resources created by this chart |
| annotations.statefulSet | object | `{}` | Additional statefulSet annotations to apply to resources created by this chart |
| applyHealthChecks | bool | `true` | Add Pod/Container healthchecks settings for Kasm resources |
| applySecurity | bool | `true` | Apply Pod/Container security settings for Kasm resources |
| certificate.certManager.addWildCard | bool | `true` | Setting addWildCard to true will automatically add *.<publicAddr> as a hostname served by the Ingress, as well as adding it to the list of domains to generate a certificate for. |
| certificate.certManager.enabled | bool | `true` |  |
| certificate.certManager.issuerGroup | string | `""` | Provide the group of Issuer that cert-manager should use, defaults to 'cert-manager.io' which is the default Issuer group. |
| certificate.certManager.issuerKind | string | `""` | Provide the kind of certificate to use, defaults to `Issuer` for security to scope the certificate to the Kasm namespace. |
| certificate.certManager.issuerName | string | `"some-issuer"` | Name of the Issuer/ClusterIssuer to use for certs NOTE: You will always need to create this yourself when `certManager.enabled` is true. |
| certificate.secretName | string | `""` | Set the secret name where the certificate is stored This secret name will store a certificate created by `cert-manager` if you set `cert-manager.enabled` to true  |
| clusterDomain | string | `"cluster.local"` | Cluster-wide Kubernetes DNS domain name |
| components.api.annotations | object | `{}` |  |
| components.api.image | object | `{"repository":"kasmweb/api","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. |
| components.api.labels | object | `{}` |  |
| components.api.resources | object | `{}` |  |
| components.guac.annotations | object | `{}` |  |
| components.guac.enabled | bool | `true` | Use this setting to enable/disable deployment of the Kasm Guacamole web RDP service https://kasmweb.com/docs/latest/guide/connection_proxies.html#guacamole-guac |
| components.guac.image | object | `{"repository":"kasmweb/kasm-guac","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. |
| components.guac.labels | object | `{}` |  |
| components.guac.resources | object | `{}` |  |
| components.manager.annotations | object | `{}` |  |
| components.manager.image | object | `{"repository":"kasmweb/manager","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. |
| components.manager.labels | object | `{}` |  |
| components.manager.resources | object | `{}` |  |
| components.proxy.annotations | object | `{}` |  |
| components.proxy.image | object | `{"repository":"kasmweb/proxy","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. |
| components.proxy.labels | object | `{}` |  |
| components.proxy.resources | object | `{}` |  |
| components.rdpGateway.annotations | object | `{}` |  |
| components.rdpGateway.enabled | bool | `true` | Use this setting to enable/disable deployment of the Kasm RDP Gateway service https://kasmweb.com/docs/latest/guide/connection_proxies.html#rdp-gateway |
| components.rdpGateway.image | object | `{"repository":"kasmweb/rdp-gateway","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. |
| components.rdpGateway.labels | object | `{}` |  |
| components.rdpGateway.resources | object | `{}` |  |
| components.rdpHttpsGateway.annotations | object | `{}` |  |
| components.rdpHttpsGateway.enabled | bool | `true` | Use this setting to enable/disable deployment of the Kasm RDP HTTPS Gateway service. This service allows users to use native RDP clients via HTTPS connections rather than exposing 3389. https://kasmweb.com/docs/latest/guide/connection_proxies.html#rdp-https-gateway |
| components.rdpHttpsGateway.image | object | `{"repository":"kasmweb/rdp-https-gateway","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. |
| components.rdpHttpsGateway.labels | object | `{}` |  |
| components.rdpHttpsGateway.resources | object | `{}` |  |
| components.redis.annotations | object | `{}` |  |
| components.redis.image | object | `{"repository":"redis","tag":"5-alpine"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. |
| components.redis.labels | object | `{}` |  |
| components.redis.resources | object | `{}` |  |
| components.share.annotations | object | `{}` |  |
| components.share.enabled | bool | `true` | Use this setting to enable/disable deployment of the Kasm Share and associated Redis services https://kasmweb.com/docs/latest/guide/session_sharing.html |
| components.share.image | object | `{"repository":"kasmweb/share","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. |
| components.share.labels | object | `{}` |  |
| components.share.resources | object | `{}` |  |
| database.annotations | object | `{}` |  |
| database.image.repository | string | `"kasmweb/postgres"` |  |
| database.image.tag | string | `"1.17.0"` |  |
| database.initialize_db | bool | `true` |  |
| database.labels | object | `{}` |  |
| database.resources | object | `{}` |  |
| database.storage.retentionPolicy.whenDeleted | string | `"Delete"` |  |
| database.storage.retentionPolicy.whenScaled | string | `"Retain"` |  |
| database.storage.storageClassName | string | `""` |  |
| deploymentSize | string | `"small"` | Define the estimated size of the Kasm deployment in expected session load.      small  = Up to 10-15 sessions      medium = Up to 25-30 sessions      large  = Up to 50+ sessions |
| extraLabels.certSecret | object | `{}` | Additional statefulSet labels to apply to resources created by this chart |
| extraLabels.configMap | object | `{}` | Additional configMap labels to apply to resources created by this chart |
| extraLabels.deployment | object | `{}` | Additional deployment labels to apply to resources created by this chart |
| extraLabels.ingress | object | `{}` | Additional ingress labels to apply to resources created by this chart |
| extraLabels.job | object | `{}` | Additional job labels to apply to resources created by this chart |
| extraLabels.jobPod | object | `{}` | Additional jobPod labels to apply to resources created by this chart |
| extraLabels.pod | object | `{}` | Additional pod labels to apply to resources created by this chart |
| extraLabels.secret | object | `{}` | Additional secret labels to apply to resources created by this chart |
| extraLabels.service | object | `{}` | Additional service labels to apply to resources created by this chart |
| extraLabels.statefulSet | object | `{}` | Additional statefulSet labels to apply to resources created by this chart |
| imagePullCredentials | object | `{}` | Create a dockerconfigjson secret as an image pull credential. Useful for offline or self-hosted repos, or dev builds. |
| imagePullPolicy | string | `"IfNotPresent"` | Configure global image pull policy |
| imagePullSecrets | string | `""` | Use credentials for custom images or image repositories. Useful for offline or self-hosted repos, or dev builds. |
| ingress | object | `{"annotations":{},"enabled":true,"ingressClassName":"","labels":{}}` | Configure Ingress for your Kasm deployment.   |
| labels | object | `{}` | Custom labels to apply to all deployed resources |
| nodeSelector | object | `{}` | Configure node selector settings for resource assignment https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector |
| publicAddr | string | `""` |  |
| restartPolicy | string | `"Always"` | Configure global Pod restart policy for Kasm resources |
| service | object | `{"annotations":{},"type":"ClusterIP"}` | Configure the external-facing service type to use. Allowed service types: ClusterIP or LoadBalancer  The service.annotations defined here only apply to the `proxy` service. If you wish to apply annotations to all services, use the annotations.service value at the bottom of this chart.  NOTE: If ingress.enabled set to `true` service.type value MUST be set to `ClusterIP`.  |
