# SMB Media Viewer

ローカルネットワーク上の Samba 共有に保存されたメディアファイル（画像・動画・PDF）を、ブラウザから閲覧するための軽量 Web ビューア。

自宅のミニ PC で常時稼働させ、古いスマホから Wi-Fi 経由でアクセスすることを想定して設計されています。SPA フレームワークは使用せず、フロントエンドは素の HTML + CSS + Vanilla JS のみで構成されています。

## 機能

- **ディレクトリブラウジング** — サムネイルグリッドでファイルを一覧表示
- **ソート** — 名前・作成日時・更新日時の3キー × 昇順/降順で並び替え（URL クエリパラメータで管理、ブックマーク可能）
- **無限スクロール** — 追加バッチを `/api/files/*` から自動フェッチ
- **ファイルビューア** — 画像・動画・PDF をブラウザネイティブで表示、前/次ナビゲーション付き
- **サムネイル自動生成** — vipsthumbnail / ffmpeg / pdftoppm でサムネイルを生成してディスクキャッシュ
- **Range request 対応** — 動画のシークバーが正常動作
- **REST API v1** — 同一ネットワーク内の別サーバー（openclaw など）からファイル一覧・実体・詳細情報を取得可能
- **MCP サーバー** — AI エージェントがツール経由でメディアを探索できる `/mcp` エンドポイント

## 動作要件

- Crystal 1.x
- 以下のシステムパッケージ

```
libvips-tools   # サムネイル生成
ffmpeg          # 動画サムネイル抽出
poppler-utils   # PDF サムネイル生成
cifs-utils      # Samba マウント
```

- Samba 共有が `mount -t cifs` でローカルパスにマウント済みであること（詳細は [Samba 共有のマウント](#samba-共有のマウント) を参照）

## Samba 共有のマウント

本アプリケーションは、ローカルパスにマウントされたディレクトリをスキャンします。Samba 共有をマウントするには、`cifs-utils` を使用します。

### 一時的なマウント

```bash
sudo mount -t cifs -o username=<ユーザー名>,password=<パスワード>,ro,iocharset=utf8 //192.168.x.x/share /mnt/nas/media
```

### 恒久的なマウント (/etc/fstab)

`/etc/fstab` に以下の行を追加することで、起動時に自動的にマウントされます。パスワードを直接記述したくない場合は `credentials` オプションの使用を検討してください。

```
//192.168.x.x/share /mnt/nas/media cifs username=<ユーザー名>,password=<パスワード>,ro,iocharset=utf8,x-systemd.automount 0 0
```

> **セキュリティ上の注意:** 読み取り専用 (`ro`) オプションでのマウントを強く推奨します。

## インストール

```bash
git clone <repo-url>
cd smb-media-viewer
shards install
crystal build src/app.cr --release -o media-viewer
```

## 設定

プロジェクトルートに `config.yml` を作成します（省略時はすべてデフォルト値を使用）。

```yaml
media_root: /mnt/nas/media      # メディアファイルのルートディレクトリ
cache_dir: ~/.cache/media-viewer # サムネイルキャッシュの保存先
port: 3000                       # リッスンポート
thumbnail_size: 200              # サムネイルの最大辺（px）
items_per_page: 50               # 1バッチあたりの読み込み件数（最大 100）
```

## 起動

```bash
./media-viewer
```

ブラウザで `http://<サーバーIP>:3000` を開くとルートディレクトリの一覧が表示されます。

## 使い方

### ディレクトリを開く

トップページにはメディアルート直下のディレクトリとファイルがサムネイルグリッドで表示されます。ディレクトリカード（📁 アイコン）をクリックすると、そのディレクトリに移動します。

### ファイルを閲覧する

ファイルカードをクリックするとビューアページに遷移します。

| メディア種別 | 表示方法 |
|-------------|---------|
| 画像（jpg, png, gif, webp など） | `<img>` タグで表示 |
| 動画（mp4, webm, mkv など） | `<video controls>` でブラウザ内蔵プレイヤー再生 |
| PDF | ブラウザ内蔵 PDF ビューアで表示 |

ビューアページには **前へ / 次へ** ナビゲーションリンクがあり、同じディレクトリ内のファイルを順に閲覧できます。「一覧に戻る」リンクで元のディレクトリに戻ります。

### ソートを変更する

ディレクトリ一覧ページのグリッド上部にソートコントロールが表示されます。

- **並び替えキー** — `名前`（デフォルト）/ `作成日時` / `更新日時` から選択
- **順序** — `昇順`（デフォルト）/ `降順` から選択
- **並替** ボタンを押すとページが再読み込みされ、選択したソート順で一覧が表示されます

ソート設定は URL クエリパラメータ（`?sort=mtime&order=desc`）として保持されるため、ブックマークや URL 共有でソート状態を再現できます。

```
# 例: 更新日時の新しい順
http://server:3000/browse/photos?sort=mtime&order=desc

# 例: 名前の Z→A 順
http://server:3000/browse/?sort=name&order=desc
```

> ディレクトリは常にファイルより先に表示されます（ソートキーに関わらず）。

### 無限スクロール

ページ末尾までスクロールすると、次のバッチが自動的に読み込まれます。現在のソート設定が引き継がれるため、全バッチにわたって一貫した順序が保たれます。

## HTTP ルート一覧

| メソッド | パス | 説明 |
|---------|------|------|
| GET | `/browse/` | ルートディレクトリ一覧（HTML） |
| GET | `/browse/*path` | サブディレクトリ一覧（HTML） |
| GET | `/api/files/` | ルートディレクトリのファイル一覧（JSON） |
| GET | `/api/files/*path` | サブディレクトリのファイル一覧（JSON） |
| GET | `/view/*path` | ファイルビューアページ（HTML） |
| GET | `/raw/*path` | ファイル本体の配信（Range request 対応） |
| GET | `/thumbnail/*path` | サムネイル画像（JPEG） |
| GET | `/api/v1/list/*path` | ディレクトリ・ファイル一覧（JSON、REST API v1） |
| GET | `/api/v1/info/*path` | ファイル/ディレクトリ詳細情報（JSON、REST API v1） |
| GET | `/api/v1/content/*path` | ファイル実体の配信（REST API v1、Range request 対応） |
| POST | `/mcp` | MCP サーバー（JSON-RPC 2.0） |

**クエリパラメータ（browse / api/files 共通）:**

| パラメータ | 値 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `sort` | `name` / `ctime` / `mtime` | `name` | ソートキー |
| `order` | `asc` / `desc` | `asc` | ソート方向 |
| `offset` | 整数 | `0` | ページングオフセット（api/files のみ） |
| `limit` | 整数（最大 100） | `50` | 取得件数（api/files のみ） |

## REST API v1

同一ネットワーク内の別サーバー（openclaw など）からの API 通信用エンドポイントです。すべて JSON で応答し、エラーは `{"error": "<message>"}`（400 / 404 / 405）で返します。パスは `media_root` からの相対パスで指定します。

### 一覧取得 — `GET /api/v1/list/<path>`

指定パス配下のディレクトリ・ファイル一覧を返します。ディレクトリが先、その後ファイルの順で、隠しファイルと非対応ファイルは含まれません。

```bash
curl "http://server:3000/api/v1/list/photos?offset=0&limit=50&sort=mtime&order=desc"
```

```json
{
  "path": "photos",
  "offset": 0,
  "limit": 50,
  "total": 123,
  "entries": [
    {"name": "trip", "path": "photos/trip", "is_dir": true, "size": 0, "mtime": "...", "media_type": "unknown"},
    {"name": "a.jpg", "path": "photos/a.jpg", "is_dir": false, "size": 12345, "mtime": "...", "media_type": "image"}
  ]
}
```

クエリパラメータ: `offset`（デフォルト 0）/ `limit`（デフォルト 50、最大 100）/ `sort`（`name` / `ctime` / `mtime`）/ `order`（`asc` / `desc`）

### 詳細情報取得 — `GET /api/v1/info/<path>`

ファイルまたはディレクトリの詳細情報を返します。PNG 画像に AI 生成メタデータ（Stable Diffusion / NovelAI / ComfyUI）が埋め込まれている場合は `ai_metadata` として展開されます。

```bash
curl "http://server:3000/api/v1/info/photos/a.png"
```

```json
{
  "name": "a.png",
  "path": "photos/a.png",
  "is_dir": false,
  "size": 123456,
  "mtime": "2026-01-01T00:00:00Z",
  "mtime_unix": 1767225600,
  "media_type": "image",
  "content_type": "image/png",
  "extension": "png",
  "ai_metadata": {"prompt": "...", "settings": {"Steps": "20"}, "source": "stable-diffusion"}
}
```

ディレクトリの場合は `media_type: "directory"` となり、`content_type` / `extension` / `ai_metadata` は含まれません。

### ファイル実体取得 — `GET /api/v1/content/<path>`

ファイル本体を適切な Content-Type 付きで返します。Range request に対応しているため、大きな動画の部分取得も可能です。

```bash
curl -O "http://server:3000/api/v1/content/videos/clip.mp4"
curl -H "Range: bytes=0-1023" "http://server:3000/api/v1/content/videos/clip.mp4"
```

## MCP サーバー

AI エージェントが API の使い方を自律的に理解してメディアを探索できるよう、`POST /mcp` に MCP（Model Context Protocol）サーバーを実装しています。Streamable HTTP トランスポートのステートレス形態（素の JSON 応答、SSE・セッション管理なし）です。

MCP クライアント（Claude Code など）への登録例:

```json
{
  "mcpServers": {
    "smb-media-viewer": {
      "type": "http",
      "url": "http://server:3000/mcp"
    }
  }
}
```

### 提供ツール

| ツール | 引数 | 説明 |
|--------|------|------|
| `list_files` | `path`, `offset`, `limit`, `sort`, `order` | ディレクトリ・ファイル一覧（REST の `/api/v1/list/` 相当） |
| `get_file_info` | `path` | ファイル詳細情報。PNG の AI 生成メタデータを含む（`/api/v1/info/` 相当） |
| `read_file` | `path` | ファイル実体。画像は MCP image コンテンツ、その他は base64 リソースとして返す |

`read_file` は 10 MiB を超えるファイルを拒否し、代わりに `/api/v1/content/` の URL を案内します（大容量ファイルは HTTP で直接取得してください）。

## 対応メディア

| 種別 | 拡張子 |
|------|--------|
| 画像 | jpg, jpeg, png, gif, webp, bmp, svg |
| 動画 | mp4, webm, mkv, avi, mov |
| PDF  | pdf |

上記以外のファイルおよび隠しファイル（`.` 始まり）は一覧に表示されません。

## 開発・テスト

Docker を使ったテスト実行:

```bash
# テスト実行
docker compose run --rm app crystal spec

# リリースビルド
docker compose run --rm app crystal build src/app.cr
```

## systemd によるデーモン化

`media-viewer.service` を `/etc/systemd/system/` に配置して自動起動を設定します。

```bash
sudo cp media-viewer.service /etc/systemd/system/
sudo systemctl enable --now media-viewer
```

リソース制限の推奨設定（`media-viewer.service` 内）:

```ini
MemoryMax=256M
CPUQuota=50%
```

## セキュリティ

- パストラバーサル攻撃を防ぐため、すべてのファイルアクセスは `media_root` 内に制限されています
- ローカルネットワーク内での利用を前提としており、認証機能はありません
- Samba マウントは読み取り専用（`ro`）オプションを推奨します
