---
title: GCP Cloud SQL
description: Deploy Kasm in GCP using GCP Cloud SQL
author: Kasm Technologies
---

# GCP Cloud SQL

This guide explains how to deploy **Kasm** into **Google Cloud Platform (GCP) GKE** (Google Kubernetes Engine) using the GCP Cloud SQL. 

> ⚠️ **Notice:** \
> Ensure you have already provisioned a PostgreSQL v14 instance via GCP Cloud SQL, and that it is fully configured to accept connections.
> The database must be network-accessible from your target Kubernetes cluster where the Kasm Helm chart will be deployed.
Refer to [Creating a PostgreSQL instance in GCP](https://cloud.google.com/sql/docs/postgres/create-instance) for setup instructions.

---

## Option 1: Deploying the Helm Chart Using the PostgreSQL Master User
The most straightforward way to deploy the Kasm Helm chart with a standalone PostgreSQL database is by supplying the PostgreSQL master user credentials. These credentials are used only once by the db-init-job to:
1. Create the target database (kasmDbName)
2. Create the Kasm database user (kasmDbUser)
3. Assign appropriate permissions to the user
4. Initialize and seed the Kasm database with required data

Refer to the sample configuration file [gcp-cloud-sql-master-user.yaml](./gcp-cloud-sql-master-user.yaml) for a ready-to-use values.yaml to help you get started with the deployment.

### Step 1: Create a Kubernetes Namespace
Create the namespace where you plan to deploy the Kasm Helm chart:

```bash
kubectl create ns {namespace}
```

Replace `{namespace}` with the name of your target Kubernetes namespace.

### Step 2: Create a Secret for the PostgreSQL Master User
Generate a Kubernetes secret containing the PostgreSQL master user's password. This credential is used by the Helm chart's `db-init-job` to create and initialize the Kasm database:

```bash
kubectl -n {namespace} create secret generic postgres-secret --from-literal=db-password='YOUR_DB_USER_PASSWORD' 
```

Replace `{namespace}` with the same namespace used above and 'YOUR_DB_USER_PASSWORD' with the actual password for your PostgreSQL master user.

### Step 3: Configure the values.yaml
Ensure the database section in your values.yaml is configured correctly for your external PostgreSQL instance.

| Variable                      | Value        | Description                                                                                                                               |
|-------------------------------|--------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| `publicAddr`                  | *your value* | The URL used to access the Kasm deployment, which can be a private address, must be resolvable by the systems that interface with Kasm.   |
| `certificate.secretName`      | *your value* | Name of the Kubernetes secret holding the TLS certificate.                                                                                |
| `database.standalone`         | `true`       | Set to true to disable Kasm's internal database deployment and use your own external PostgreSQL v14 instance.                             |
| `database.hostname`           | *your value* | The hostname or IP address of your PostgreSQL server.                                                                                     |
| `database.port`               | *your value* | The port number used to connect to the PostgreSQL server.                                                                                 |
| `database.kasmDbName`         | *your value* | You can keep this value default `kasm`. Name of the Kasm database to create and use.                                                      |
| `database.kasmDbUser`         | *your value* | You can keep this value default `kasmapp`. Username to create that Kasm will use to access the database.                                  |
| `database.kasmDbSecret`       | *your value* | You can keep this field empty `{}` for deploying Kasm Helm chart with Postgres master user.                                               |
| `database.postgresMasterUser` | *your value* | An object defining the PostgreSQL DB Master user and the Kubernetes secret and key values for the Master DB password.                     |


Example Configuration:

```yaml
standalone: true
hostname: "YOUR_DB_HOSTNAME"
port: "YOUR_DB_PORT"
kasmDbName: kasm
kasmDbUser: kasmapp
kasmDbSecret: {}
postgresMasterUser:
 username: postgres
 secret:
   name: postgres-secret
   key: db-password
```

Note: Be sure your PostgreSQL instance is configured to allow network connections from your Kubernetes cluster, and that the correct firewall rules or private service access settings are in place.

## Option 2: Deploying Helm Chart with Manually Created DB and DB User
If you are unable or prefer not to provide PostgreSQL master user credentials, you can manually create the required database and user ahead of time.

In this approach, the Kasm Helm chart will connect to the pre-created database using the credentials you provide.

Refer to the sample configuration file [gcp-cloud-sql.yaml](./gcp-cloud-sql.yaml)  for a ready-to-use `values.yaml` to jump-start your Helm deployment using a manually provisioned database.

### Step 1: Create the Database and User
Manually create the PostgreSQL database (e.g., kasm) and user (e.g., kasmapp) in GCP Cloud SQL.

Refer to the official GCP documentation for detailed steps:
- [Create a PostgreSQL Database](https://cloud.google.com/sql/docs/postgres/create-manage-databases#create)
- [GCP Cloud Postgres Create User](https://cloud.google.com/sql/docs/postgres/create-manage-users#creating)


### Step 2: Connect to the Database and Create Extension
Use the psql client to connect to your PostgreSQL instance:
```bash
psql -h {HOSTNAME} -U {USER} -d {DB}
```

Replace:
- `{HOSTNAME}` with your Cloud SQL instance's IP
- `{USERNAME}` with the database user you created (e.g., kasmapp)
- `{DATABASE}` with the database name (e.g., kasm)

Once connected, execute the following SQL command to create the required UUID extension:
```
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

After the extension is successfully created, type:
```
exit;
```
to exit the psql session.


### Step 3: Create a Kubernetes Namespace
Create the namespace where you plan to deploy the Kasm Helm chart:

```bash
kubectl create ns {namespace}
```

Replace `{namespace}` with the name of your target Kubernetes namespace.

### Step 4: Create the Database Password Secret
Store the manually created database user's password in a Kubernetes secret:

```bash
kubectl -n {namespace} create secret generic kasm-db-secret --from-literal=kasm-db-secret-key='YOUR_PASSWORD' 
```

- Replace `{namespace}` with the Kubernetes namespace used in previous steps.
- Replace `YOUR_PASSWORD` with the password of the manually created PostgreSQL user.


### Step 5: Configure the values.yaml
Ensure the database section in your values.yaml is configured correctly for your external PostgreSQL instance.

| Variable                      | Value        | Description                                                                                                                              |
|-------------------------------|--------------|------------------------------------------------------------------------------------------------------------------------------------------|
| `publicAddr`                  | *your value* | The URL used to access the Kasm deployment, which can be a private address, must be resolvable by the systems that interface with Kasm.  |
| `certificate.secretName`      | *your value* | Name of the Kubernetes secret holding the TLS certificate.                                                                               |
| `database.standalone`         | `true`       | Set to true to disable Kasm's internal database deployment and use your own external PostgreSQL v14 instance.                            |
| `database.hostname`           | *your value* | The hostname or IP address of your PostgreSQL server.                                                                                    |
| `database.port`               | *your value* | The port number used to connect to the PostgreSQL server.                                                                                |
| `database.kasmDbName`         | *your value* | You can keep this value default `kasm`. Name of the Kasm database to create and use.                                                     |
| `database.kasmDbUser`         | *your value* | You can keep this value default `kasmapp`. Username to create that Kasm will use to access the database.                                 |
| `database.kasmDbSecret`       | *your value* | Name and key of the Kubernetes secret that holds the password for kasmDbUser.                                                            |
| `database.postgresMasterUser` | `{}`         | Keep this field empty `{}` for deploying Kasm Helm chart without Postgres master user.                                                   |


See example below.

```yaml
standalone: true
hostname: "YOUR_DB_HOSTNAME"
port: "YOUR_DB_PORT"
kasmDbName: kasm
kasmDbUser: kasmapp
kasmDbSecret:
  name: kasm-db-secret
  key: kasm-db-secret-key
postgresMasterUser: {}
```


