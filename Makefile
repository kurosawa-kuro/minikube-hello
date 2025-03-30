# Minikube + Express + Nginx 環境管理用 Makefile
# -----------------------------------------------
# 前提:
#   - Amazon Linux 2023 上で Docker / Minikube / kubectl / Node.js / Nginx が既にインストール済み
#   - 作業ディレクトリ: ~/dev/minikube-hello
#   - express-hello  配下に Node.js (Express) アプリ、Dockerfile
#   - k8s-manifests 配下に deployment.yaml, service.yaml
#   - セキュリティグループでポート80を開放済み

# 変数定義
MINIKUBE_IP := $(shell minikube ip 2>/dev/null || echo "not_running")
EXPRESS_APP_DIR := express-hello
K8S_MANIFESTS_DIR := k8s-manifests
DOCKER_IMAGE := express-hello-world:latest

# デフォルトターゲット
.PHONY: all
all: status

# ------------------------------------------------------------------------------
# Minikube関連
# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------
# Docker関連
# ------------------------------------------------------------------------------

.PHONY: build
build:
	@echo "Building Docker image..."
	# MinikubeのDockerデーモンを使ってビルド
	eval $$(minikube docker-env) && \
		docker build -t $(DOCKER_IMAGE) $(EXPRESS_APP_DIR)
	@echo "Docker image built successfully: $(DOCKER_IMAGE)"

# ------------------------------------------------------------------------------
# Kubernetes関連
# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------
# Nginx関連
# ------------------------------------------------------------------------------
# Minikube IP を Nginx のプロキシ先に設定 (EC2 内部でのリバースプロキシ)

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
	@echo "Nginx configuration updated (proxy_pass to $(MINIKUBE_IP):30080)"

# ------------------------------------------------------------------------------
# ステータス確認
# ------------------------------------------------------------------------------

.PHONY: status
status:
	@echo "=== Minikube Status ==="
	@minikube status 2>/dev/null || echo "Minikube is not running"
	@echo ""
	@echo "=== Kubernetes Pods ==="
	@kubectl get pods 2>/dev/null || echo "Kubernetes is not available"
	@echo ""
	@echo "=== Kubernetes Services ==="
	@kubectl get svc 2>/dev/null || echo "Kubernetes is not available"
	@echo ""
	@echo "=== Docker Images ==="
	@eval $$(minikube docker-env) && docker images | grep "$(DOCKER_IMAGE)" \
		|| echo "$(DOCKER_IMAGE) not found"

# ------------------------------------------------------------------------------
# クリーンアップ
# ------------------------------------------------------------------------------

.PHONY: clean
clean: undeploy stop delete
	@echo "Cleaning up Docker images..."
	# Minikube が停止していると local Docker に切り替わる場合あり → エラーでも続行
	docker rmi $(DOCKER_IMAGE) 2>/dev/null || true
	@echo "Cleanup completed"

# ------------------------------------------------------------------------------
# ヘルプ
# ------------------------------------------------------------------------------

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  start        - Start Minikube cluster"
	@echo "  stop         - Stop Minikube cluster"
	@echo "  delete       - Delete Minikube cluster"
	@echo "  build        - Build Docker image (via Minikube Docker daemon)"
	@echo "  deploy       - Deploy to Kubernetes (apply manifests)"
	@echo "  undeploy     - Undeploy from Kubernetes (delete manifests)"
	@echo "  nginx-config - Update Nginx configuration to proxy Minikube NodePort"
	@echo "  status       - Show current status of Minikube, K8s pods, services, Docker image"
	@echo "  clean        - Undeploy, stop, delete cluster, remove Docker image"
	@echo "  help         - Show this help message"
