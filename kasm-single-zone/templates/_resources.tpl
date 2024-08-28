{{/*
Return a resource request/limit object based on given presets
Example usage:
{{- include "resources.preset" (dict "node" "proxy" "size" "small") -}}
*/}}
{{- define "resources.preset" }}
  {{- $presetSizes := dict
    "proxy" (dict
      "small" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "250m" "memory" "128Mi" "ephemeral-storage" "1Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "192Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "750m" "memory" "512Mi" "ephemeral-storage" "5Gi")
      )
    )
    "proxy-processes" (dict
      "small" 2
      "medium" 6
      "large" 12
    )
    "db" (dict
      "small" (dict 
        "requests" (dict "cpu" "500m" "memory" "128Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "750m" "memory" "384Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "512m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1.5" "memory" "2048Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "512m" "memory" "2048Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "4.0" "memory" "8192Mi" "ephemeral-storage" "2Gi")
      )
    )
    "api" (dict
      "small" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "250m" "memory" "192Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "384Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "300m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1.0" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "manager" (dict
      "small" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "350m" "memory" "192Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "256Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "300m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1.0" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "guac" (dict
      "small" (dict 
        "requests" (dict "cpu" "250m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "memory" "256Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "500m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "750m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "memory" "768Mi" "ephemeral-storage" "2Gi")
      )
    )
    "rdp" (dict
      "small" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "200m" "memory" "128Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "300m" "memory" "256Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "share" (dict
      "small" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "200m" "memory" "128Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "300m" "memory" "256Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "200m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "400m" "memory" "384Mi" "ephemeral-storage" "2Gi")
      )
    )
    "redis" (dict
      "small" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "200m" "memory" "128Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "300m" "memory" "256Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
  }}
  {{- if hasKey $presetSizes .node }}
    {{- if hasKey (get $presetSizes .node) .size }}
      {{- dig .node .size "" $presetSizes | toYaml -}}
    {{- else }}
      {{- printf "ERROR: Preset key '%s' invalid. Allowed values are %s" .size (join "," (keys (get $presetSizes .node))) | fail }}
    {{- end }}
  {{- else }}
    {{- printf "ERROR: Preset key '%s' invalid. Allowed values are %s" .node (join "," (keys $presetSizes)) | fail }}
  {{- end }}
{{- end }}
