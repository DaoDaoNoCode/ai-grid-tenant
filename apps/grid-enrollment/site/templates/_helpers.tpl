{{- define "grid-enrollment-site.siteName" -}}
{{- required "siteName is required" .Values.siteName -}}
{{- end -}}

{{- define "grid-enrollment-site.clusterName" -}}
{{- default (include "grid-enrollment-site.siteName" .) .Values.clusterName -}}
{{- end -}}

{{- define "grid-enrollment-site.slug" -}}
{{- $siteName := include "grid-enrollment-site.siteName" . -}}
{{- $slug := default $siteName .Values.siteSlug -}}
{{- if gt (len $slug) 43 -}}
{{- printf "%s-%s" (trunc 34 $slug) (sha256sum $slug | trunc 8) -}}
{{- else -}}
{{- $slug -}}
{{- end -}}
{{- end -}}

{{- define "grid-enrollment-site.isHub" -}}
{{- eq (include "grid-enrollment-site.siteName" .) .Values.hubClusterName -}}
{{- end -}}

{{- define "grid-enrollment-site.gatewayName" -}}
{{- printf "grid-gw-%s" (include "grid-enrollment-site.slug" .) -}}
{{- end -}}

{{- define "grid-enrollment-site.swimServiceName" -}}
{{- printf "grid-swim-%s" (include "grid-enrollment-site.slug" .) -}}
{{- end -}}

{{- define "grid-enrollment-site.signalsServiceName" -}}
{{- printf "grid-sig-%s" (include "grid-enrollment-site.slug" .) -}}
{{- end -}}
