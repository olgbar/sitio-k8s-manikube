#!/bin/bash

# Parámetros de configuración
PERFIL="minikube-website"
NAMESPACE="website-ns"
CONTEXT="website-ctx"
GIT_REPO="https://github.com/olgbar/static-website.git"

# Configurar rutas según entorno WSL
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    echo "Ejecutando en WSL - Configurando rutas..."
    # Usar rutas locales en WSL para evitar problemas de permisos con /mnt/c
    WEB_DIR="$(pwd)/website-content"
    K8S_DIR="$(pwd)/k8s-manifiestos"
else
    echo "Ejecutando en Linux nativo"
    WEB_DIR="$(pwd)/website-content"
    K8S_DIR="$(pwd)/k8s-manifiestos"
fi

# Función para abortar con mensaje de error
die() {
    echo "Error: $1"
    exit 1
}

# Limpieza de recursos previos
echo "Limpiando recursos previos (si existen)..."
kubectl delete deployment web-deploy --ignore-not-found=true
kubectl delete service web-service --ignore-not-found=true
kubectl delete pvc pvc-website --ignore-not-found=true
kubectl delete pv pv-website --ignore-not-found=true

# Crear directorios necesarios
mkdir -p "$WEB_DIR" "$K8S_DIR"

# Limpiar contenido existente del directorio web
if [[ -d "$WEB_DIR" ]]; then
    find "$WEB_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
    echo "Directorio web limpiado"
fi

# Clonar repositorio
echo "Clonando repositorio de contenido web..."
git clone "$GIT_REPO" "$WEB_DIR" || die "Error al clonar repositorio"

# Verificar contenido
echo "Verificando contenido web clonado:"
ls -la "$WEB_DIR"

if [ ! -f "$WEB_DIR/index.html" ]; then
    die "No se encontró index.html en $WEB_DIR. Verifica el repositorio."
else
    echo "Archivo index.html encontrado"
fi

# Asegurar permisos correctos
chmod -R 755 "$WEB_DIR"
find "$WEB_DIR" -type f -exec chmod 644 {} \;

# Iniciar Minikube
echo "Iniciando minikube con perfil $PERFIL..."
minikube start -p "$PERFIL" --driver=docker || die "No se pudo iniciar Minikube"

# Esperar a que el nodo esté listo
echo "Esperando a que el nodo esté listo..."
until kubectl get nodes &> /dev/null; do 
    echo "  Esperando al nodo..."
    sleep 2
done

echo "Estado del perfil Minikube:"
minikube status -p "$PERFIL"

# Crear namespace
echo "Verificando o creando namespace $NAMESPACE..."
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "  Namespace no encontrado, creándolo..."
    kubectl create namespace "$NAMESPACE" || die "Error creando namespace"
else
    echo "  Namespace $NAMESPACE ya existe."
fi

# Configurar contexto
echo "Configurando contexto Kubernetes..."
kubectl config set-context "$CONTEXT" --cluster="$PERFIL" --user="$PERFIL" --namespace="$NAMESPACE" || die "Error configurando contexto"
kubectl config use-context "$CONTEXT" || die "Error cambiando de contexto"

# Método más confiable: Usar initContainer para clonar directamente el repositorio
echo "Preparando despliegue con sitio web..."

# Crear manifiestos de Kubernetes
# 1. Deployment con initContainer
cat <<EOF > "$K8S_DIR/web-deployment.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deploy
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      initContainers:
      - name: git-clone
        image: alpine/git
        command:
        - /bin/sh
        - -c
        - git clone $GIT_REPO /tmp/web && cp -r /tmp/web/* /usr/share/nginx/html/
        volumeMounts:
        - name: web-content
          mountPath: /usr/share/nginx/html
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: web-content
          mountPath: /usr/share/nginx/html
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: web-content
        emptyDir: {}
EOF

# 2. Service
cat <<EOF > "$K8S_DIR/web-service.yaml"
apiVersion: v1
kind: Service
metadata:
  name: web-service
  namespace: $NAMESPACE
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
  type: NodePort
EOF

# Aplicar manifiestos
echo "Aplicando manifiestos Kubernetes..."
kubectl apply -f "$K8S_DIR/web-deployment.yaml" || die "Error aplicando deployment"
kubectl apply -f "$K8S_DIR/web-service.yaml" || die "Error aplicando service"

# Esperar a que el pod esté listo
echo "Esperando a que el pod esté listo..."
kubectl rollout status deployment/web-deploy -n "$NAMESPACE" --timeout=120s || echo "Timeout esperando el despliegue"

# Verificar el pod y su contenido
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=web -o jsonpath="{.items[0].metadata.name}")

if [[ -z "$POD_NAME" ]]; then
    echo "No se encontró ningún pod. Verificando estado del despliegue..."
    kubectl describe deployment web-deploy -n "$NAMESPACE"
    die "No se pudo encontrar el pod"
fi

# Verificar contenido
echo "Verificando archivos en el pod $POD_NAME:"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- ls -la /usr/share/nginx/html

# Verificar logs
echo "Logs del pod:"
kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=20

# Mostrar URL de acceso
echo -e "\nURL de acceso al sitio web:"
minikube -p "$PERFIL" service web-service -n "$NAMESPACE"

# Probar conexión
URL=$(minikube -p "$PERFIL" service web-service --url -n "$NAMESPACE")
echo -e "\nProbando conexión al sitio web..."
curl -s "$URL" | grep -q "<html" && echo "Sitio web accesible" || echo "No se pudo acceder al sitio web"

echo -e "\nDespliegue completado."
echo -e "Comandos útiles:"
echo "  - Acceder al pod: kubectl exec -it $POD_NAME -n $NAMESPACE -- sh"
echo "  - Ver logs: kubectl logs -f $POD_NAME -n $NAMESPACE"
echo "  - Eliminar despliegue: kubectl delete -f $K8S_DIR/"
