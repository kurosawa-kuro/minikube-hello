以下の手順は **Amazon Linux 2023** 環境を前提とし、**Docker / Minikube / kubectl / Node.js / Nginx 等がすでにインストール済み**である状況を想定しています。  
また、作業ディレクトリは `~/dev/minikube-hello` を作成し、その中で進めていきます。  
セキュリティグループのポート80を開放済みであることも前提とします。

---

# Minikube + Node.js (Express) “Hello World” on Amazon Linux 2023

## 手順の概要

1. **作業ディレクトリの作成 (`~/dev/minikube-hello`)**  
2. **Node.js (Express) “Hello World” アプリ作成**  
3. **Minikube クラスタ起動**  
4. **Dockerfile 作成 & イメージビルド (Minikube Dockerデーモン)**  
5. **Kubernetes マニフェスト作成 & 適用**  
6. **Nginx リバースプロキシ設定**  
7. **動作確認**  
8. **Minikube クラスタ停止 & 削除** (任意)

> **前提**:  
> - Amazon Linux 2023 上で、Docker / Minikube / kubectl / Node.js / Nginx がインストール済み  
> - セキュリティグループで **ポート80** を開放  
> - EC2 インスタンスのユーザーは `ec2-user` (想定)

---

## 1. 作業ディレクトリの作成

本手順ではホームディレクトリの `~/dev/` 配下に `minikube-hello` というディレクトリを作り、そこをプロジェクトルートとします。

```bash
# ホームディレクトリへ移動
cd ~/

# devディレクトリへ移動 (なければ作成)
mkdir -p dev
cd dev

# プロジェクトディレクトリ作成
mkdir -p minikube-hello
cd minikube-hello

# Expressアプリ用ディレクトリ
mkdir express-hello

# Kubernetes マニフェスト用ディレクトリ
mkdir k8s-manifests
```

```
~/dev/minikube-hello/
  ├─ express-hello/
  └─ k8s-manifests/
```

---

## 2. Node.js (Express) “Hello World” アプリ作成

### 2-1. Express アプリのファイル構成

```bash
cd ~/dev/minikube-hello/express-hello

# 必要なファイルを一度に作成
touch index.js package.json Dockerfile
```

1. **index.js**

   ```bash
   cat << 'EOF' > index.js
   const express = require('express');
   const app = express();
   const PORT = process.env.PORT || 3000;

   app.get('/', (req, res) => {
     console.log("GET / へアクセスがありました");
     res.send('Hello World');
   });

   app.listen(PORT, () => {
     console.log(`Server is running on port ${PORT}`);
   });
   EOF
   ```

2. **package.json**

   ```bash
   cat << 'EOF' > package.json
   {
     "name": "express-hello-world",
     "version": "1.0.0",
     "scripts": {
       "start": "node index.js"
     },
     "dependencies": {
       "express": "^4.18.2"
     }
   }
   EOF
   ```

### 2-2. 依存パッケージのインストール

```bash
cd ~/dev/minikube-hello/express-hello
npm install
```

---

## 3. Minikube クラスタ起動

```bash
# プロジェクトルートに戻る (任意)
cd ~/dev/minikube-hello

# Minikube を起動 (ドライバ: Docker, メモリを約1800MBに制限)
minikube start --driver=docker --memory=1800mb

# 状況確認
minikube status
```

> - `t3.small` (メモリ2GB) の場合は `--memory=1800mb` のように少なめに割り当てるのが安定  
> - `minikube status` で `host: Running`, `kubelet: Running`, `apiserver: Running`, `kubeconfig: Configured` などが出ればOK

---

## 4. Dockerfile 作成 & イメージビルド

### 4-1. Dockerfile

上記ですでに空の `Dockerfile` を作っているので上書きします。

```bash
cd ~/dev/minikube-hello/express-hello
cat << 'EOF' > Dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["npm", "start"]
EXPOSE 3000
EOF
```

### 4-2. Minikube の Docker デーモンに接続してビルド

```bash
cd ~/dev/minikube-hello/express-hello

# Minikube が持つ Docker へ接続
eval $(minikube docker-env)

# Docker イメージをビルド (タグ: express-hello-world:latest)
docker build -t express-hello-world:latest .

# イメージ一覧を確認
docker images
```

> **注意**: `eval $(minikube docker-env)` を忘れると、ホスト側Dockerにビルドされ、Minikubeからイメージが見えず `ErrImagePull` になる可能性があります。

---

## 5. Kubernetes マニフェスト作成 & 適用

Minikube 上にアプリをデプロイするために、Deployment と Service (NodePort) を作成します。

### 5-1. ファイル作成

```bash
cd ~/dev/minikube-hello/k8s-manifests

touch deployment.yaml service.yaml
```

1. **deployment.yaml**

   ```bash
   cat << 'EOF' > deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: express-hello-deployment
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: express-hello
     template:
       metadata:
         labels:
           app: express-hello
       spec:
         containers:
           - name: express-hello-container
             image: express-hello-world:latest
             imagePullPolicy: IfNotPresent
             ports:
               - containerPort: 3000
   EOF
   ```

2. **service.yaml**

   ```bash
   cat << 'EOF' > service.yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: express-hello-service
   spec:
     selector:
       app: express-hello
     type: NodePort
     ports:
       - port: 3000
         targetPort: 3000
         nodePort: 30080
   EOF
   ```

### 5-2. Kubernetes へデプロイ

```bash
cd ~/dev/minikube-hello/k8s-manifests
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# 状況確認
kubectl get pods
kubectl get svc
```

- Pod が `Running` になり、Service が `NodePort (30080)` で公開されていればOK

---

## 6. Nginx リバースプロキシ設定

Minikubeの NodePort (例えば `192.168.49.x:30080`) は EC2外部IP に直接バインドされません。  
そこで、EC2上の Nginx を使い **外部(ポート80) -> Minikube NodePort** にプロキシします。

### 6-1. Minikube IP の確認

```bash
minikube ip
# 例: 192.168.49.2
```

### 6-2. Nginx 設定ファイル

```bash
sudo dnf install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx

nginx -v
```

```bash
sudo tee /etc/nginx/conf.d/k8s-proxy.conf > /dev/null <<EOF
server {
    listen 80;
    location / {
        proxy_pass http://192.168.49.2:30080;
    }
}
EOF

# 設定反映
sudo systemctl restart nginx
```

> **注意**: 既存の `/etc/nginx/conf.d/default.conf` と競合する場合はコメントアウト・削除してください。

---

## 7. 動作確認

### 7-1. EC2 パブリックIP へアクセス

```bash
curl http://<EC2_PUBLIC_IP>/
# => "Hello World"
```

- ブラウザで `http://<EC2_PUBLIC_IP>/` にアクセスしても同様に確認できます。

---

## 8. Minikube クラスタ停止 & 削除 (任意)

学習や検証が終わってリソースを解放したい場合は、以下を実行します。

```bash
# クラスタを停止
minikube stop

# クラスタを削除 (作成されたVMや設定が削除される)
minikube delete
```

---

# ディレクトリ構成まとめ

本手順で作成したファイルの最終構成は下記の通りです。

```
~/dev/minikube-hello/
  ├─ express-hello/
  │    ├─ index.js
  │    ├─ package.json
  │    └─ Dockerfile
  └─ k8s-manifests/
       ├─ deployment.yaml
       └─ service.yaml
```

---

# まとめ

- **Amazon Linux 2023** で **Docker / Minikube / kubectl / Node.js / Nginx** が既に導入済みの環境を利用  
- `~/dev/minikube-hello` 以下に **Express アプリ** と **Kubernetes マニフェスト** を配置  
- **Minikube** でシングルノードKubernetesを起動  
- **Dockerfile** をビルドし **Deployment & NodePort Service** でコンテナを稼働  
- **Nginx** をリバースプロキシとしてパブリックIP(80) から Minikube の NodePort(30080) へ転送  
- 確認後は `minikube stop` / `minikube delete` で停止・削除可能  

これで **Node.js (Express) の “Hello World”** を簡単に Kubernetes で動かすデモ環境が構築できます。ぜひお試しください。