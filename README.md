# ikatodon-db: ConoHa プライベートネットワーク対応 PostgreSQL 16 セットアップ

このプロジェクトは、ConoHaのプライベートネットワークを使用してUbuntu 24サーバーでPostgreSQL 16を自動セットアップします。

## ConoHaプライベートネットワークの利点

1. **セキュリティ**: インターネットからの直接アクセスを遮断
2. **パフォーマンス**: 内部ネットワークによる高速通信
3. **コスト**: 内部通信は転送量課金対象外
4. **分離**: アプリケーションサーバーとDBサーバーの分離

## ファイル構成

```
ikatodon/ikatodon-db/
├── conoha-startup.sh               # ConoHaスタートアップスクリプト
├── ansible.cfg                     # Ansible設定
├── inventory.ini                   # サーバー情報とネットワーク設定
├── inventory-template.ini          # スタートアップスクリプト用テンプレート
├── setup-docker.yml               # Docker環境セットアップ（従来版）
├── deploy-postgres.yml            # PostgreSQL 16デプロイ（従来版）
├── simplified-setup.yml           # 簡略化版セットアップ
├── docker-compose.postgres16.yml  # Docker Compose設定
├── postgresql.conf                 # PostgreSQL設定
└── README.md                       # このファイル
```

## セットアップ方法

### 方法1: ConoHaスタートアップスクリプト使用（推奨）

#### 1. ConoHaでサーバー作成時の設定

1. **サーバー作成画面で「スタートアップスクリプト」を選択**
2. **`conoha-startup.sh`の内容をコピー&ペースト**
3. **サーバーを作成**

スタートアップスクリプトが以下を自動実行：
- システムパッケージの更新
- Ansibleのインストール
- mastodonユーザーの作成（sudo権限付き）
- SSH設定（`ssh mastodon@{ip}`で接続可能）
- Docker & Docker Composeのインストール
- セキュリティ設定（ファイアウォール、fail2ban）
- 便利なスクリプトとエイリアスの設定

#### 2. サーバー作成後の設定

```bash
# 1. サーバーにSSH接続
ssh mastodon@YOUR_SERVER_IP

# 2. プライベートネットワークの設定
sudo ./setup-private-network.sh 192.168.0.10

# 3. Ansibleファイルのダウンロード
git clone https://github.com/your-repo/ikatodon-db.git
cd ikatodon-db

# 4. インベントリファイルの設定
cp inventory-template.ini inventory.ini
# inventory.iniを編集してIPアドレスを設定

# 5. PostgreSQL 16のデプロイ
ansible-playbook simplified-setup.yml
```

### 方法2: 従来のAnsible方式

#### 前提条件

**ConoHa側の設定:**
1. プライベートネットワークの作成（サブネット例: `192.168.0.0/24`）
2. DBサーバーをプライベートネットワークに接続

**必要なソフトウェア:**
```bash
# Ansibleのインストール
sudo apt update
sudo apt install ansible
```

#### セットアップ手順

```bash
# 1. インベントリファイルの設定
# inventory.iniを編集してIPアドレスを設定

# 2. データベースパスワードの設定
ansible-vault create group_vars/all/vault.yml

# 3. 接続テスト
ansible all -m ping

# 4. 実行
ansible-playbook setup-docker.yml deploy-postgres.yml
```

## 主な機能

### Docker セットアップ (`setup-docker.yml`)
- Docker CE、Docker Composeのインストール
- `/etc/netplan/11-localnetwork.yaml`の自動作成
- プライベートネットワークの設定
- ファイアウォール設定
- 管理ツールのインストール

### PostgreSQL デプロイ (`deploy-postgres.yml`)
- PostgreSQL 16コンテナの起動
- プライベートネットワーク対応設定
- 自動バックアップ・リストアスクリプト
- 監視スクリプトの作成
- 日次バックアップのcron設定

## ネットワーク設定

### netplan設定 (`/etc/netplan/11-localnetwork.yaml`)

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens4:
      addresses:
        - 192.168.0.10/24
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

### PostgreSQL接続設定

```yaml
# Docker Compose設定
services:
  postgres16:
    ports:
      - "192.168.0.10:5432:5432"  # プライベートIPでバインド
```

## セットアップ後の確認

### 1. ネットワーク設定の確認

```bash
# プライベートネットワークの確認
ip addr show ens4
```

### 2. PostgreSQL接続テスト

```bash
# DBサーバーで
cd /opt/mastodon
./monitor.sh

# PostgreSQL接続テスト
docker exec mastodon_postgres16 psql -U mastodon -d mastodon_production -c "SELECT version();"
```

### 3. 他のサーバーからの接続テスト

```bash
# アプリケーションサーバーから
psql -h 192.168.0.10 -U mastodon -d mastodon_production
```

## Mastodonアプリケーション側の設定

### .env.production の設定

```bash
# データベース接続設定
DB_HOST=192.168.0.10
DB_PORT=5432
DB_NAME=mastodon_production
DB_USER=mastodon
DB_PASS=your_secure_password
```

## データ移行

### PostgreSQL 10からの移行

```bash
# 1. 旧サーバーでダンプ作成
pg_dump -h OLD_DB_SERVER -U mastodon -Fc mastodon_production > mastodon_backup.dump

# 2. 新サーバーにファイル転送
scp mastodon_backup.dump ubuntu@NEW_DB_SERVER:/opt/mastodon/

# 3. 新サーバーでリストア
ssh ubuntu@NEW_DB_SERVER
cd /opt/mastodon
./restore.sh mastodon_backup.dump
```

## 管理コマンド

### バックアップ・リストア

```bash
# 手動バックアップ
/opt/mastodon/backup.sh

# リストア
/opt/mastodon/restore.sh /opt/mastodon/backups/mastodon_backup_YYYYMMDD_HHMMSS.dump

# 監視
/opt/mastodon/monitor.sh
```

## トラブルシューティング

### よくある問題

1. **プライベートネットワークに接続できない**
   ```bash
   # netplan設定確認・適用
   sudo netplan apply
   ```

2. **PostgreSQLに接続できない**
   ```bash
   # コンテナ状態確認
   docker ps
   netstat -tlnp | grep 5432
   ```

3. **ファイアウォール問題**
   ```bash
   # ファイアウォール確認
   sudo ufw status
   ```

## セキュリティ考慮事項

- プライベートネットワークのみからのアクセス許可
- 強力なデータベースパスワードの設定
- 定期的なセキュリティ更新

## パフォーマンス最適化

- SSD最適化設定
- メモリ設定の調整
- 並列処理の最適化

## ConoHaスタートアップスクリプトの使用方法

### 1. スタートアップスクリプトの設定

1. **ConoHaコントロールパネルにログイン**
2. **「サーバー追加」をクリック**
3. **「スタートアップスクリプト」タブを選択**
4. **`conoha-startup.sh`の内容をコピー&ペースト**
5. **サーバーを作成**

### 2. サーバー作成後の確認

```bash
# SSH接続（mastodonユーザーで直接接続可能）
ssh mastodon@YOUR_SERVER_IP

# システム情報の確認（自動表示される）
# または手動実行
./system-info.sh

# プライベートネットワークの設定
sudo ./setup-private-network.sh 192.168.0.10
```

### 3. PostgreSQL 16のデプロイ

```bash
# Ansibleファイルの準備
git clone https://github.com/your-repo/ikatodon-db.git
cd ikatodon-db

# インベントリファイルの設定
cp inventory-template.ini inventory.ini
vim inventory.ini  # IPアドレスを実際の値に変更

# PostgreSQL 16のデプロイ
ansible-playbook simplified-setup.yml
```

## スタートアップスクリプトの利点

1. **ワンクリックセットアップ**: サーバー作成と同時に環境構築
2. **自動ユーザー作成**: `ssh mastodon@{ip}`で即座に接続可能
3. **セキュリティ強化**: ファイアウォール、fail2ban自動設定
4. **便利ツール**: PostgreSQL管理用エイリアスとスクリプト
5. **ログ管理**: セットアップ過程の完全ログ記録

この設定により、ConoHaのプライベートネットワークを活用した安全で高性能なPostgreSQL 16環境を構築できます。
