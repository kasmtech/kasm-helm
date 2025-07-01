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
| affinity | object | `{}` | Configure node affinity settings for Kasm pods -  [Kubernetes Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/). Kasm is not guaranteed to work with Affinity settings - use caution if you must configuring these settings. The below, optional object passes in raw Affinity rules for Pods, Nodes, etc. for your environment. Make sure you use the correct values below as this Helm chart will not do any error checking for you.  |
| annotations.certSecret | object | `{}` | Additional certSecret annotations to apply to resources created by this chart |
| annotations.configMap | object | `{}` | Additional configMap annotations to apply to resources created by this chart |
| annotations.deployment | object | `{}` | Additional deployment annotations to apply to resources created by this chart |
| annotations.pod | object | `{}` | Additional pod annotations to apply to resources created by this chart |
| annotations.secret | object | `{}` | Additional secret annotations to apply to resources created by this chart |
| annotations.service | object | `{}` | Additional service annotations to apply to resources created by this chart |
| annotations.statefulSet | object | `{}` | Additional statefulSet annotations to apply to resources created by this chart |
| applyHealthChecks | bool | `true` | Add Pod/Container healthchecks settings for Kasm resources  |
| applySecurity | bool | `true` | Apply Pod/Container security settings for Kasm resources  |
| certificate.certManager | object | `{"addWildCard":true,"enabled":true,"issuerGroup":"","issuerKind":"","issuerName":""}` | For additional cert-manager configuration/deployment information refer to the online documentation [Cert Manager Docs](https://cert-manager.io/v1.1-docs/installation/kubernetes/).   NOTE: If you do not enable `cert-manager`, you must generate your own certificates and add them as a Kubernetes secret. Refer to [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/), and  [Kubernetes TLS Secret](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_secret_tls/) for more information.  |
| certificate.secretName | string | `""` | Set the secret name where the certificate is stored. This secret name will store a certificate created by `cert-manager` if you set `cert-manager.enabled` to true  |
| clusterDomain | string | `"cluster.local"` | Cluster-wide Kubernetes DNS domain name  |
| components.api.annotations | object | `{}` | Custom annotations to add to the Kasm api Deployment |
| components.api.image | object | `{"repository":"kasmweb/api","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.  |
| components.api.labels | object | `{}` | Custom labels to add to the Kasm api Deployment |
| components.api.resources | object | `{}` | Manually configure the Kasm api Deployment resources. This overrides the pre-defined `deploymentSize` values. |
| components.guac.annotations | object | `{}` | Custom annotations to add to the Kasm Guac Deployment |
| components.guac.enabled | bool | `true` | Use this setting to enable/disable deployment of the Kasm Guacamole web RDP service -  [Kasm Guac Service](https://kasmweb.com/docs/latest/guide/connection_proxies.html#guacamole-guac).  |
| components.guac.image | object | `{"repository":"kasmweb/kasm-guac","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.  |
| components.guac.labels | object | `{}` | Custom labels to add to the Kasm Guac Deployment |
| components.guac.resources | object | `{}` | Manually configure the Kasm Guac Deployment resources. This overrides the pre-defined `deploymentSize` values. |
| components.manager.annotations | object | `{}` | Custom annotations to add to the Kasm Manager Deployment |
| components.manager.image | object | `{"repository":"kasmweb/manager","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.  |
| components.manager.labels | object | `{}` | Custom labels to add to the Kasm Manager Deployment |
| components.manager.resources | object | `{}` | Manually configure the Kasm Manager Deployment resources. This overrides the pre-defined `deploymentSize` values. |
| components.proxy.annotations | object | `{}` | Custom annotations to add to the Kasm Proxy Deployment |
| components.proxy.image | object | `{"repository":"kasmweb/proxy","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.  |
| components.proxy.labels | object | `{}` | Custom labels to add to the Kasm Proxy Deployment |
| components.proxy.resources | object | `{}` | Manually configure the Kasm Proxy Deployment resources. This overrides the pre-defined `deploymentSize` values. |
| components.rdpGateway.annotations | object | `{}` | Custom annotations to add to the Kasm RDP Gateway Deployment |
| components.rdpGateway.enabled | bool | `true` | Use this setting to enable/disable deployment of the Kasm RDP Gateway service -  [Kasm RDP Gateway](https://kasmweb.com/docs/latest/guide/connection_proxies.html#rdp-gateway).  |
| components.rdpGateway.image | object | `{"repository":"kasmweb/rdp-gateway","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.  |
| components.rdpGateway.labels | object | `{}` | Custom labels to add to the Kasm RDP Gateway Deployment |
| components.rdpGateway.resources | object | `{}` | Manually configure the Kasm RDP Gateway Deployment resources. This overrides the pre-defined `deploymentSize` values. |
| components.rdpHttpsGateway.annotations | object | `{}` | Custom annotations to add to the Kasm RDP HTTPS Gateway Deployment |
| components.rdpHttpsGateway.enabled | bool | `true` | Use this setting to enable/disable deployment of the Kasm RDP HTTPS Gateway service. This service allows users to use native RDP clients via HTTPS connections rather than exposing 3389 -  [Kasm RDP HTTPS Gateway](https://kasmweb.com/docs/latest/guide/connection_proxies.html#rdp-https-gateway).  |
| components.rdpHttpsGateway.image | object | `{"repository":"kasmweb/rdp-https-gateway","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.  |
| components.rdpHttpsGateway.labels | object | `{}` | Custom labels to add to the Kasm RDP HTTPS Gateway Deployment |
| components.rdpHttpsGateway.resources | object | `{}` | Manually configure the Kasm RDP HTTPS Gateway Deployment resources. This overrides the pre-defined `deploymentSize` values. |
| components.redis.annotations | object | `{}` | Custom annotations to add to the Kasm Redis Deployment |
| components.redis.image | object | `{"repository":"redis","tag":"5-alpine"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.  |
| components.redis.labels | object | `{}` | Custom labels to add to the Kasm Redis Deployment |
| components.redis.resources | object | `{}` | Manually configure the Kasm Redis Deployment resources. This overrides the pre-defined `deploymentSize` values. |
| components.share.annotations | object | `{}` | Custom annotations to add to the Kasm Share Deployment |
| components.share.enabled | bool | `true` | Use this setting to enable/disable deployment of the Kasm Share and associated Redis services -  [Kasm Share Service](https://kasmweb.com/docs/latest/guide/session_sharing.html).  |
| components.share.image | object | `{"repository":"kasmweb/share","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.  |
| components.share.labels | object | `{}` | Custom labels to add to the Kasm Share Deployment |
| components.share.resources | object | `{}` | Manually configure the Kasm Share Deployment resources. This overrides the pre-defined `deploymentSize` values. |
| database.annotations | object | `{}` | Custom annotations to add to the Kasm DB StatefulSet |
| database.hostname | string | `"kasm-db"` | The hostname used to connect to the database server. If you use the Kasm DB StatefulSet this will be the name of the DB service, if you use an external DB, you need to replace this value with the hostname or IP or your DB server.  |
| database.image | object | `{"repository":"kasmweb/postgres","tag":"1.17.0"}` | Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.  |
| database.initialize_db | bool | `true` | Setting `initialize_db` to true assumes you want a newly initialized Kasm deployment. Setting this to false is useful for deployment if running Kasm upgrades, or if you previously initialized Kasm, retained the data, and wish to redeploy.  |
| database.kasmDbName | string | `"kasm"` | The name of the database where Kasm is to be initialized and that Kasm services are to connect  |
| database.kasmDbUser | string | `"kasmapp"` | The name of the Kasm database User with READ/WRITE permission to the Kasm database  |
| database.labels | object | `{}` | Custom labels to add to the Kasm DB StatefulSet |
| database.port | int | `5432` | The port Kasm will use to connect to the PostgreSQL DB server  |
| database.postgresMasterUser | object | `{}` | An object defining the PostgreSQL DB Master user and the Kubernetes secret and key values for the Master DB password. These credentials are only used by the `db-init-job` to create the `kasmDbName` database, the `kasmDbUser` user account, set permissions for the user account, and initialize and pre-seed the Kasm Database.  |
| database.resources | object | `{}` | Manually configure the Kasm DB StatefulSet resources. This overrides the pre-defined `deploymentSize` values. |
| database.standalone | bool | `false` | Setting standalone to true will prevent the deployment of the Kasm DB StatefulSet and requires the user to have a self-hosted PostgreSQL Database v14 server already setup and awaiting connections. Use the below database configuration values to connect to your external DB.  |
| database.storage.retentionPolicy | object | `{"whenDeleted":"Delete","whenScaled":"Retain"}` | Configure how the DB volume should be retained or deleted throughout the DB's lifecycle  |
| database.storage.storageClassName | string | `""` | Set the storage class to attach to the DB for storage. NOTE: Leaving this blank will use the cluster-default storage class  |
| deploymentSize | string | `"small"` | Define the estimated size of the Kasm deployment in expected session load.  small  = Up to 10-15 sessions  medium = Up to 25-30 sessions  large  = Up to 50+ sessions  |
| extraLabels.certSecret | object | `{}` | Additional statefulSet labels to apply to resources created by this chart |
| extraLabels.configMap | object | `{}` | Additional configMap labels to apply to resources created by this chart |
| extraLabels.deployment | object | `{}` | Additional deployment labels to apply to resources created by this chart |
| extraLabels.job | object | `{}` | Additional job labels to apply to resources created by this chart |
| extraLabels.jobPod | object | `{}` | Additional jobPod labels to apply to resources created by this chart |
| extraLabels.pod | object | `{}` | Additional pod labels to apply to resources created by this chart |
| extraLabels.secret | object | `{}` | Additional secret labels to apply to resources created by this chart |
| extraLabels.service | object | `{}` | Additional service labels to apply to resources created by this chart |
| extraLabels.statefulSet | object | `{}` | Additional statefulSet labels to apply to resources created by this chart |
| imagePullCredentials | object | `{}` | Create a dockerconfigjson secret as an image pull credential. Useful for offline or self-hosted repos, or dev builds.  |
| imagePullPolicy | string | `"IfNotPresent"` | Configure global image pull policy  |
| imagePullSecrets | string | `""` | Use credentials for custom images or image repositories. Useful for offline or self-hosted repos, or dev builds.  |
| ingress | object | `{"annotations":{},"enabled":false,"ingressClassName":"","labels":{}}` | Configure an Ingress for your Kasm deployment.   |
| ingress.enabled | bool | `false` | Set the enabled value to `true` to use a pre-defined Ingress service to expose Kasm |
| ingress.ingressClassName | string | `""` | Define the ingress Class to use for your Kasm ingress |
| labels | object | `{}` | Custom labels to apply to all deployed resources  |
| nodeSelector | object | `{}` | Configure node selector settings for your Kasm pods -  [Kubernetes Node Selector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector).  |
| proxyService | object | `{"annotations":{},"labels":{},"type":"LoadBalancer"}` | Configure the external-facing service type to use.  Allowed service types: ClusterIP or LoadBalancer.   The service.annotations defined here only apply to the `proxy` service (`proxy-service-external.yaml` file). If you wish to apply annotations to all services, use the annotations.service value at the bottom of this chart.  NOTE: If ingress.enabled or route.enabled set to `true` service.type MUST be set to `ClusterIP`.  |
| publicAddr | string | `""` |  |
| restartPolicy | string | `"Always"` | Configure global Pod restart policy for Kasm resources  |
| route | object | `{"annotations":{},"enabled":false,"labels":{},"tls":{}}` | Configure an OpenShift Route for your Kasm deployment.   |
| route.enabled | bool | `false` | Set the enabled value to `true` to use a pre-defined Route service to expose Kasm |
| route.tls | object | `{}` | Object to define the TLS configuration for your OpenShift Route -  [Configuring Secure Routes](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/networking/configuring-routes#configuring-default-certificate).  |
