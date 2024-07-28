#!/bin/sh
source hostfilemanager.sh
# Installation variables
CLUSTER_DOMAIN=local.io
API_PORT=6550
HTTP_PORT=44134
HTTPS_PORT=6600
CLUSTER_NAME=target-ops
SERVERS=1
AGENTS=2
REGISTRY_PORT=7979

# Bold text 
bold=$(tput bold)
normal=$(tput sgr0)
yes_no="(${bold}Y${normal}es/${bold}N${normal}o)"

# Function definitions
countdown() {
    local OLD_IFS="${IFS}"
    IFS=":"
    local ARR=( $1 )
    local SECONDS=$((  (ARR[0] * 60 * 60) + (ARR[1] * 60) + ARR[2]  ))
    local START=$(date +%s)
    local END=$((START + SECONDS))
    local CUR=$START

    while [ $CUR -lt $END ]
    do
        CUR=$(date +%s)
        LEFT=$((END-CUR))
        printf "\r%02d:%02d:%02d" $((LEFT/3600)) $(( (LEFT/60)%60)) $((LEFT%60))
        sleep 1
    done
    IFS="${OLD_IFS}"
    echo "        "
}

read_value() {
    read -p "${1} [${bold}${2}${normal}]: " READ_VALUE
    READ_VALUE=${READ_VALUE:-$2}
}

header() {
    echo "\n\n${bold}${1}${normal}\n-------------------------------------"
}

footer() {
    echo "-------------------------------------"
}

isSelected() {
    case "$1" in
        [Yy]*)
            echo 1
            ;;
        *)
            echo 0
            ;;
    esac
}

configValues() {
    read_value "Cluster Name" "${CLUSTER_NAME}"
    CLUSTER_NAME=${READ_VALUE}
    read_value "Cluster Domain" "${CLUSTER_DOMAIN}"
    CLUSTER_DOMAIN=${READ_VALUE}
    read_value "API Port" "${API_PORT}"
    API_PORT=${READ_VALUE}
    read_value "Servers (Masters)" "${SERVERS}"
    SERVERS=${READ_VALUE}
    read_value "Agents (Workers)" "${AGENTS}"
    AGENTS=${READ_VALUE}
    read_value "LoadBalancer HTTP Port" "${HTTP_PORT}"
    HTTP_PORT=${READ_VALUE}
    read_value "LoadBalancer HTTPS Port" "${HTTPS_PORT}"
    HTTPS_PORT=${READ_VALUE}
    read_value "Registry Port" "${REGISTRY_PORT}"
    REGISTRY_PORT=${READ_VALUE}
}

checkDependencies() {
    local tools="docker k3d kubectl helm"
    for tool in $tools; do
        if ! command -v $tool > /dev/null 2>&1; then
            echo "$tool could not be found. Please install it and try again."
            exit 1
        fi
    done

    # Add default repos
    helm repo add stable https://charts.helm.sh/stable
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update
}


installCluster() {
    header "Creating PV local folder K3d"    
    mkdir -p k3dvol
    header "Creating K3D registry"
    k3d registry delete k3d-registry.${CLUSTER_DOMAIN} || k3d registry create registry.${CLUSTER_DOMAIN} --port ${REGISTRY_PORT}
    header "Creating K3D cluster"
    k3d cluster delete ${CLUSTER_NAME} 2>/dev/null
    k3d cluster create ${CLUSTER_NAME} \
        --servers ${SERVERS} \
        --agents ${AGENTS} \
        --api-port ${API_PORT} \
        --port "${HTTP_PORT}:80@loadbalancer" \
        --port "${HTTPS_PORT}:443@loadbalancer" \
        --k3s-arg "--disable=traefik@server:*" \
        --k3s-arg "--tls-san=127.0.0.1@server:0" \
        --registry-use k3d-registry.${CLUSTER_DOMAIN}:${REGISTRY_PORT} \
        --volume "$(pwd)/k3dvol:/k3dvol@all" \
        --wait

    kubectl config use-context k3d-${CLUSTER_NAME}
    kubectl cluster-info
    header "Creating PersistentVolume"
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: k3d-pv
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/k3dvol"  
EOF

    kubectl get pv
    footer
}

installIngress() {
    header "Installing Ingress"
    cat <<EOF | helm install --namespace ingress-nginx --create-namespace -f - ingress bitnami/nginx-ingress-controller
extraArgs:
  default-ssl-certificate: "ingress/nginx-server-certs"
EOF
    # helm upgrade --install ingress-nginx ingress-nginx \
    #     --repo https://kubernetes.github.io/ingress-nginx \
    #     --namespace ingress-nginx --create-namespace

        
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=120s
    footer
}

installDashboard() {
    header "Installing Dashboard"
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
        --namespace kubernetes-dashboard --create-namespace \
        --set service.type=ClusterIP \
        --set protocolHttp=true \
        --set enableInsecureLogin=true
    
    kubectl create serviceaccount dashboard-admin-sa
    kubectl create clusterrolebinding dashboard-admin-sa --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:dashboard-admin-sa
    
    header "Dashboard Access Token:"
    kubectl -n kubernetes-dashboard create token dashboard-admin-sa
    echo "Access URL: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
    footer
}

installArgoCD() {
    header "Installing ArgoCD"
    # helm upgrade --install argocd argo/argo-cd \
    #     --namespace argocd --create-namespace \
    #     --set server.insecure=true \
    #     --set server.service.type=ClusterIP \
    #     --set server.ingress.enabled=false
  helm upgrade --install argocd argo/argo-cd --create-namespace -f ./argo_insecure.yml -n argocd #overide with insecure set
  cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-http-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
    host: argocd.${CLUSTER_DOMAIN}
EOF
    kubectl -n argocd wait --for=condition=available deployment -l app.kubernetes.io/name=argocd-server --timeout=300s
#     cat <<EOF | kubectl apply -f -
# apiVersion: networking.k8s.io/v1
# kind: Ingress
# metadata:
#   name: argocd-server-http-ingress
#   namespace: argocd
#   annotations:
#     kubernetes.io/ingress.class: "nginx"
#     nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
#     nginx.ingress.kubernetes.io/ssl-redirect: "false"
#     nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
# spec:
#   rules:
#   - host: argocd.${CLUSTER_DOMAIN}
#     http:
#       paths:
#       - path: /
#         pathType: Prefix
#         backend:
#           service:
#             name: argocd-server
#             port:
#               number: 80
# EOF

    echo "ArgoCD URL: http://argocd.${CLUSTER_DOMAIN}:${HTTP_PORT}"
    echo "ArgoCD Initial Password:"
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    echo
    footer
}
installPrometheus() {
    # kubernetes.io/ingress.class: "nginx"
    # nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    # nginx.ingress.kubernetes.io/ssl-redirect: "false"
    # nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    
    header "Installing Prometheus & Grafana"
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring --create-namespace \
        --set grafana.ingress.enabled=true \
        --set grafana.annotations."nginx.ingress.kubernetes.io/force-ssl-redirect"="false" \
        --set grafana.ingress.annotations."nginx.ingress.kubernetes.io/ssl-redirect"="false" \
        --set grafana.
        --set grafana.ingress.hosts[0]=grafana.${CLUSTER_DOMAIN} \
        --set prometheus.ingress.enabled=true \
        --set prometheus.ingress.hosts[0]=prometheus.${CLUSTER_DOMAIN}
    echo "Grafana URL: https://grafana.${CLUSTER_DOMAIN}"
    echo "Prometheus URL: https://prometheus.${CLUSTER_DOMAIN}"
    echo "Grafana admin password:"
    kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
    footer
}

installAddons() {
    read_value "Install Ingress? ${yes_no}" "Yes"
    [ "$(isSelected ${READ_VALUE})" = "1" ] && installIngress

    read_value "Install Dashboard? ${yes_no}" "Yes"
    [ "$(isSelected ${READ_VALUE})" = "1" ] && addhost dashboard.${CLUSTER_DOMAIN} && installDashboard

    read_value "Install ArgoCD? ${yes_no}" "Yes"
    [ "$(isSelected ${READ_VALUE})" = "1" ] && addhost argocd.${CLUSTER_DOMAIN} && installArgoCD

    read_value "Install Prometheus & Grafana? ${yes_no}" "Yes"
    [ "$(isSelected ${READ_VALUE})" = "1" ] && addhost prometheus.${CLUSTER_DOMAIN} && addhost grafana.${CLUSTER_DOMAIN} && installPrometheus
}

showUrls() {
    header "Local K3d cluster endpoints:"
    echo "Kubernetes Dashboard: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
    echo "ArgoCD: http://argocd.${CLUSTER_DOMAIN}:${HTTP_PORT}"
    echo "Grafana: http://grafana.${CLUSTER_DOMAIN}:${HTTP_PORT}"
    echo "Prometheus: http://prometheus.${CLUSTER_DOMAIN}:${HTTP_PORT}"
    footer
}

# Main execution
checkDependencies
configValues
installCluster
installAddons
showUrls

echo "Setup complete. Don't forget to add the necessary entries to your /etc/hosts file."
echo "Registry is available at: registry.${CLUSTER_DOMAIN}:${REGISTRY_PORT}"