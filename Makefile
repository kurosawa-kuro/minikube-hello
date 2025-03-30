# Minikube + Express + Nginx 環境管理用 Makefile

# 変数定義
MINIKUBE_IP := $(shell minikube ip 2>/dev/null || echo "not_running")
EXPRESS_APP_DIR := express-hello
K8S_MANIFESTS_DIR := k8s-manifests
DOCKER_IMAGE := express-hello-world:latest

# デフォルトターゲット
.PHONY: all
all: status

# Minikube関連
.PHONY: start
start:
	@echo "Starting Minikube cluster..."
	minikube start --driver=docker --memory=1800mb
	@echo "Minikube cluster started successfully"

.PHONY: stop
stop:
	@echo "Stopping Minikube cluster..."
	minikube stop
	@echo "Minikube cluster stopped"

.PHONY: delete
delete:
	@echo "Deleting Minikube cluster..."
	minikube delete
	@echo "Minikube cluster deleted"

# Docker関連
.PHONY: build
build:
	@echo "Building Docker image..."
	eval $$(minikube docker-env) && \
	docker build -t $(DOCKER_IMAGE) $(EXPRESS_APP_DIR)
	@echo "Docker image built successfully"

# Kubernetes関連
.PHONY: deploy
deploy:
	@echo "Deploying to Kubernetes..."
	kubectl apply -f $(K8S_MANIFESTS_DIR)/deployment.yaml
	kubectl apply -f $(K8S_MANIFESTS_DIR)/service.yaml
	@echo "Deployment completed"

.PHONY: undeploy
undeploy:
	@echo "Undeploying from Kubernetes..."
	kubectl delete -f $(K8S_MANIFESTS_DIR)/service.yaml
	kubectl delete -f $(K8S_MANIFESTS_DIR)/deployment.yaml
	@echo "Undeployment completed"

# Nginx関連
.PHONY: nginx-config
nginx-config:
	@echo "Updating Nginx configuration..."
	@if [ "$(MINIKUBE_IP)" = "not_running" ]; then \
		echo "Error: Minikube is not running. Please start Minikube first."; \
		exit 1; \
	fi
	@sudo tee /etc/nginx/conf.d/k8s-proxy.conf > /dev/null <<EOF
	server {
		listen 80;
		location / {
			proxy_pass http://$(MINIKUBE_IP):30080;
		}
	}
	EOF
	sudo systemctl restart nginx
	@echo "Nginx configuration updated"

# ステータス確認
.PHONY: status
status:
	@echo "=== Minikube Status ==="
	@minikube status 2>/dev/null || echo "Minikube is not running"
	@echo "\n=== Kubernetes Pods ==="
	@kubectl get pods 2>/dev/null || echo "Kubernetes is not available"
	@echo "\n=== Kubernetes Services ==="
	@kubectl get svc 2>/dev/null || echo "Kubernetes is not available"
	@echo "\n=== Docker Images ==="
	@docker images | grep $(DOCKER_IMAGE) || echo "Docker image not found"

# クリーンアップ
.PHONY: clean
clean: undeploy stop delete
	@echo "Cleaning up Docker images..."
	docker rmi $(DOCKER_IMAGE) 2>/dev/null || true
	@echo "Cleanup completed"

# ヘルプ
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  start        - Start Minikube cluster"
	@echo "  stop         - Stop Minikube cluster"
	@echo "  delete       - Delete Minikube cluster"
	@echo "  build        - Build Docker image"
	@echo "  deploy       - Deploy to Kubernetes"
	@echo "  undeploy     - Undeploy from Kubernetes"
	@echo "  nginx-config - Update Nginx configuration"
	@echo "  status       - Show current status"
	@echo "  clean        - Clean up all resources"
	@echo "  help         - Show this help message"
