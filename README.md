# Kasm on Kubernetes

Kasm has been modified to run inside Kubernetes. The service containers will automatically detect they are running in Kubernetes and they will talk directly to each other rather than assume they are talking through an NGINX server as is the case for a normal Kasm deployment. Additionally, components need to talk to the name of the service defined, not to individual containers. A Kubernetes service has a resolvable DNS name that all containers should be able to talk with. API containers will not talk to an individual rdp gateway or guac container, but rather be load balanced to all existing respective containers. The reverse is also true. The API servers have been modified to only return a single entry when guac or rdp gateways call to get a list of API servers. 

## Current Limitations/Work Remaining
The following limitations are still be worked out.
1. Database initialization is done by the API container, which means there can only be one API container when the database is first initialized. After the deployment is up and running, it should be possible to add more replicas. They will not initialize the database if the schema already exists, but starting the deployment with more than one API pod might result in race conditions with both attempting to deploy the database schema at the same time. We need to remove database initialization to something external, because we can't assume they will keep the db in kubernetes. So it needs to be changed from something that is automatic to something that is a manual prerequisite step, or optionally automatic.
2. The RDP Gateway component provides native RDP proxying for RDP clients. It is currently not exposed and would require 3389 to be defined in the ingress. We are currently working on an update that will support RDP over HTTPS, which is supported by most RDP clients. Therefore, this will not be required in the future.
3. Container based agents need to be external to Kubernetes. We are currently working on Kubevirt autoscaling. A kubernetes native agent would be needed to provide container desktops/apps and that is not currently being worked at this time.
4. This goes along with 3, we currently have values in the api.yaml file for default credentials, used for seeding the database. Those need removed.
5. Database and Redis credentials need moved to secrets.

## Helm

A helm chart is used to deploy Kasm. This project contains examples of deployments, there is a sub directory for each deployment example. For example, `kasm-single-zone`, contains a simple single zone deployment of Kasm.

### Prerequisites

**Create the Namespace**

```bash
kubectl create ns kasm-helm --dry-run=client -o yaml | kubectl apply -f -
```

**Edit values.yaml**
1. Change the namespace variable if desired.
2. Change the `host` variable to the hostname of the deployment that is resolvable by clients.

**Create Secrets**
Before you can deploy the helm chart, you must create the required secrets, substitute the namespace name if you have changed it in the values.yaml file.

```bash
# Create a cert and create secret, change hostname and IP as needed
HOST=matt.dev.kasmweb.net openssl req -x509 -newkey rsa:4096 -keyout keyfile.key -out certfile.crt -sha256 -days 365 -nodes -extensions san -config \
  <(echo "[req]";
    echo distinguished_name=req;
    echo "[san]";
    echo subjectAltName=DNS:$HOST,IP:8.67.53.09
    ) \
    -subj "/C=US/O=KASM/CN=$HOST" &> /dev/null
kubectl create secret tls nginx-ingress-cert --namespace "kasm-helm" --key keyfile.key --cert certfile.crt

# Create a cert for the RDP proxy component
openssl req -x509 -nodes -days 1825 -newkey rsa:2048 -keyout rdpproxy.key -out rdpproxy.crt -subj "/C=US/ST=VA/L=None/O=None/OU=DoFu/CN=$(hostname)/emailAddress=none@none.none"
kubectl create secret tls rdp-proxy-cert --namespace "kasm-helm" --key rdpproxy.key --cert rdpproxy.crt
```

### Deploy
The following will deploy Kasm in a single zone configuration.

```bash
helm install --replace kasmdemo kasm-single-zone
```