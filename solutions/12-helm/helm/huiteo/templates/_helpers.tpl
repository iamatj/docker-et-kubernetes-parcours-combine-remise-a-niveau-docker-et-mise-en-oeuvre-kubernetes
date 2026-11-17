{{/* Étiquettes communes à tous les objets du chart. */}}
{{- define "huiteo.labels" -}}
partie-de: huiteo
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* Image complète d'un composant : {{ include "huiteo.image" .Values.api }} */}}
{{- define "huiteo.image" -}}
{{ .image.repository }}:{{ .image.tag }}
{{- end -}}
