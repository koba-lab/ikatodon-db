# Ubuntu 24でDocker Compose + PostgreSQL 16セットアップ

このAnsibleプレイブックは、Ubuntu 24サーバーでDocker ComposeとPostgreSQL 16を自動セットアップします。

## 前提条件

1. **Ansibleがインストールされていること**
   ```bash
   # Ubuntu/Debian
   sudo apt update
   sudo apt install ansible

   # macOS
   brew install ansible
   ```

2. **SSH接続が可能であること**
   - 新しいサーバーにSSHキーでアクセスできる
   - sudo権限があるユーザーでアクセスできる

## セットアップ手順

### 1. インベントリファイルの設定

`inventory.ini`を編集して、新しいサーバーの情報を設定：

```ini
[mastodon_servers]
new_server ansible_host=YOUR_SERVER_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/your_key.pem
```

### 2. データベースパスワードの設定（推奨）

セキュリティのため、Ansible Vaultを使用してパスワードを暗号化：

```bash
# Vaultファイルを作成
ansible-vault create group_vars/all/vault.yml

# 以下の内容を追加
vault_db_password: "your_secure_password_here"
```

### 3. 接続テスト

```bash
# サーバーへの接続をテスト
ansible all -m ping
```

### 4. Dockerのセットアップ

```bash
# Docker Composeをインストール・設定
ansible-playbook setup-docker.yml
```

このプレイブックは以下を実行します：
- Docker CEのインストール
- Docker Composeのインストール
- 必要なユーザーをdockerグループに追加
- PostgreSQL用ディレクトリの作成
- 本番環境向けDocker設定

### 5. PostgreSQL 16のデプロイ

```bash
# PostgreSQL 16をデプロイ
ansible-playbook deploy-postgres.yml
```

このプレイブックは以下を実行します：
- PostgreSQL 16コンテナの起動
- 設定ファイルの配置
- バックアップ・リストアスクリプトの作成
- 日次バックアップのcron設定

## 実行例

```bash
# 全体を一度に実行
ansible-playbook setup-docker.yml deploy-postgres.yml

# Vaultパスワードを使用する場合
ansible-playbook setup-docker.yml deploy-postgres.yml --ask-vault-pass

# 特定のタスクのみ実行
ansible-playbook deploy-postgres.yml --tags backup
```

## セットアップ後の確認

### Docker Composeの動作確認

```bash
# サーバーにSSH接続
ssh ubuntu@YOUR_SERVER_IP

# PostgreSQL 16の状態確認
cd /opt/mastodon
docker-compose -f docker-compose.postgres16.yml ps

# PostgreSQL接続テスト
docker exec mastodon_postgres16 psql -U mastodon -d mastodon_production -c "SELECT version();"
```

### ログの確認

```bash
# PostgreSQLログ
docker logs mastodon_postgres16

# Docker Composeログ
docker-compose -f docker-compose.postgres16.yml logs
```

## データ移行

### PostgreSQL 10からのダンプリストア

```bash
# 1. 旧サーバーでダンプ作成
pg_dump -h OLD_SERVER_IP -U mastodon -Fc mastodon_production > mastodon_backup.dump

# 2. 新サーバーにファイル転送
scp mastodon_backup.dump ubuntu@NEW_SERVER_IP:/opt/mastodon/

# 3. 新サーバーでリストア
ssh ubuntu@NEW_SERVER_IP
cd /opt/mastodon
./restore.sh mastodon_backup.dump
```

## 管理コマンド

### バックアップ

```bash
# 手動バックアップ
/opt/mastodon/backup.sh

# バックアップ一覧
ls -la /opt/mastodon/backups/
```

### リストア

```bash
# リストア（対話式）
/opt/mastodon/restore.sh /opt/mastodon/backups/mastodon_backup_YYYYMMDD_HHMMSS.dump
```

### PostgreSQL管理

```bash
# PostgreSQLコンテナに接続
docker exec -it mastodon_postgres16 psql -U mastodon -d mastodon_production

# データベース統計
docker exec mastodon_postgres16 psql -U mastodon -d mastodon_production -c "SELECT schemaname,tablename,n_tup_ins,n_tup_upd,n_tup_del FROM pg_stat_user_tables ORDER BY n_tup_ins DESC LIMIT 10;"
```

## トラブルシューティング

### よくある問題

1. **Docker権限エラー**
   ```bash
   # ユーザーをdockerグループに追加後、再ログインが必要
   sudo usermod -aG docker $USER
   # ログアウト・ログインまたは
   newgrp docker
   ```

2. **PostgreSQL接続エラー**
   ```bash
   # コンテナの状態確認
   docker ps
   docker logs mastodon_postgres16

   # ポート確認
   netstat -tlnp | grep 5432
   ```

3. **ディスク容量不足**
   ```bash
   # Docker使用量確認
   docker system df

   # 不要なイメージ・コンテナ削除
   docker system prune -a
   ```

## セキュリティ考慮事項

1. **ファイアウォール設定**
   ```bash
   # PostgreSQLポートを必要な範囲のみ開放
   sudo ufw allow from YOUR_APP_SERVER_IP to any port 5432
   ```

2. **SSL/TLS設定**
   - 本番環境では`postgresql.conf`で`ssl = on`に設定
   - 証明書ファイルを適切に配置

3. **定期的なセキュリティ更新**
   ```bash
   # Dockerイメージの更新
   docker pull postgres:16
   docker-compose -f docker-compose.postgres16.yml up -d
   ```

## ファイル構成

```
.
├── ansible.cfg              # Ansible設定
├── inventory.ini            # サーバー情報
├── setup-docker.yml        # Docker セットアップ
├── deploy-postgres.yml     # PostgreSQL デプロイ
├── docker-compose.postgres16.yml  # Docker Compose設定
├── postgresql.conf          # PostgreSQL設定
└── README-ansible.md        # このファイル
```
