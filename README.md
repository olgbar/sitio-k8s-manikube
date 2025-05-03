# Índice:  
1. [Trabajo 0311AT](#0311at---despliegue-de-sitio-web-statico)
2. [Trabajo 0505AT](#0505at---script-de-despliegue)

***

# 0311AT - Despliegue de sitio web statico

## Clonar el fork
git clone https://github.com/olgbar/static-website.git
cd static-website

## Abrir para modificar HTML
code .

## Commit inicial
git add .
git commit -m "Contenido personalizado del sitio web"
git push origin master

## Iniciar Minikube
minikube start -p 0311at
minikube status -p 0311at
minikube profile 0311at

## Configurar Kubernetes
kubectl create namespace k8s-web-dev

kubectl config set-context web-dev-context \
  --cluster=0311at \
  --user=0311at \
  --namespace=k8s-web-dev

kubectl config use-context web-dev-context
kubectl config get-contexts

## Preparar manifiestos
cd ..
mkdir manifiestos-k8s
cd manifiestos-k8s
git init

## Dejar esta terminal abierta y en otra montar el volumen como admin:
minikube -p 0311at mount C:\Users\barbi\0311at\static-website:/mnt/static-website

### Aplicar PV y PVC  
1. Aplicar: pv.yml  
kubectl apply -f pv.yml

2. Aplicar: pvc.yml  
kubectl apply -f pvc.yml

### Verificar  

kubectl get pv
kubectl get pvc -n k8s-web-dev

### Aplicar configmap.yml

kubectl apply -f configmap.yml  

### Verificar ConfigMap
kubectl get configmap -n k8s-web-dev
kubectl describe configmap sitio-config -n k8s-web-dev

### Aplicar deployment.yml  

kubectl apply -f deployment.yml

### Aplicar service.yml

kubectl apply -f service.yml

### Verificar
kubectl describe service nginx-sitio -n k8s-web-dev
kubectl get pods -n k8s-web-dev

### Ver dentro del pod (ajustar el nombre si cambia)
POD_NAME=$(kubectl get pods -n k8s-web-dev -o jsonpath="{.items[0].metadata.name}")
kubectl exec -it $POD_NAME -n k8s-web-dev -- ls /usr/share/nginx/html
kubectl exec -it $POD_NAME -n k8s-web-dev -- printenv

## Acceder al sitio
minikube -p 0311at service nginx-sitio -n k8s-web-dev

*** 

# 0505AT - Script de Despliegue

En este trabajo se busca generar un script automatizado para poder desplegar el trabajo 0311AT realizado con anterioridad.  
Este trabajo 0505AT, a diferencia del anterior, se realizó mediante un entorno WSL. Por lo tanto se decidió no utilizar PV y PVC para evitar errores que ya fueron comprobados durante el proceso de desarrollo. Ya que usar volúmenes persistentes en WSL suele causar conflictos por diferencias entre sistemas de archivos.  
Está optimizado para evitar errores comunes como el 403 Forbidden que suele aparecer al usar volúmenes persistentes en WSL.  
Los archivos del sitio se clonan directamente dentro del pod debido al uso de un initContainer.  
  
- **Requisitos previos**:
  ```md
  - Docker Desktop
  - Minikube
  - kubectl
  - Git
  ```
## Preparar el Entorno  

1. Clonar el repositorio:  
  git clone https://github.com/tu-usuario/k8s-static-website-deploy.git  
  cd k8s-static-website-deploy  
  
2. Otorgar permisos de ejecución al script:
   chmod +x deploy-website.sh

3. De manera opcional, podés editar variables al inicio del script para personalizar:
   - PERFIL: nombre del perfil de Minikube
   - NAMESPACE: namespace donde se desplegará
   - CONTEXT: contexto de Kubernetes a usar
   - GIT_REPO: URL del repositorio con el sitio web

## Para la Ejecución del Script  

Una vez listos los pasos anteriores, ejecutar el script:  
  ./deploy-website.sh

- **Proceso que va a realizar el Script**:
- Detectar si se está en WSL
- Limpiar recursos anteriores
- Clonar el repositorio del sitio
- Iniciar Minikube con un perfil determinado
- Crear el namespace
- Configurar el contexto de K8S
- Desplegar el sitio usando NGINX
- Verificar que todo funcione
- Mostrar la URL de acceso al sitio. Esta URL debe copiarse y pegarse en el navegador

## Para eliminar todo lo que se creó:
kubectl delete namespace website-ns  
minikube delete -p minikube-website

### Bárbara Olguin - ITU Desarrollo de Software