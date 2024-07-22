{{- define "db.podSecurity" }}
securityContext:
  runAsUser: 70
  runAsGroup: 70
  fsGroup: 70
  fsGroupChangePolicy: Always
{{- end }}

{{- define "db.containerSecurity" }}
securityContext:
  runAsUser: 70
  runAsGroup: 70
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
{{- end }}

{{- define "db.initContainer" }}
initContainers:
  - name: db-data-perms
    image: busybox
    command:
      - /bin/sh
      - -ec
    args:
      - |
        echo "Setting permissions and ownership on /var/lib/postgresql/data..." && mkdir -p /var/lib/postgresql/data/postgres && chown -R 70:70 /var/lib/postgresql/data && chmod -R 0700 /var/lib/postgresql/data
        echo "Setting permissions and ownership on /var/run/postgresql..." && chown -R 70:70 /var/run/postgresql && chmod -R 0700 /var/run/postgresql
        echo "Setting permissions and ownership on /tmp..." && mkdir -p /tmp/postgres && chmod -R 0700 /tmp/postgres && chmod -R 777 /tmp
        echo "Done"
    securityContext:
      runAsNonRoot: false
      runAsUser: 0
    volumeMounts:
      - name: kasm-db-data
        mountPath: /var/lib/postgresql/data
      - name: kasm-db-data
        mountPath: /tmp
{{- end }}

{{- define "db.podSecurity.mounts"}}
- name: kasm-db-data
  mountPath: /var/run/postgresql
{{- end }}
