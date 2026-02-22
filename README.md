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

## 動作要件

- Crystal 1.x
- 以下のシステムパッケージ

```
libvips-tools   # サムネイル生成
ffmpeg          # 動画サムネイル抽出
poppler-utils   # PDF サムネイル生成
cifs-utils      # Samba マウント
```

- Samba 共有が `mount -t cifs` でローカルパスにマウント済みであること

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

**クエリパラメータ（browse / api/files 共通）:**

| パラメータ | 値 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `sort` | `name` / `ctime` / `mtime` | `name` | ソートキー |
| `order` | `asc` / `desc` | `asc` | ソート方向 |
| `offset` | 整数 | `0` | ページングオフセット（api/files のみ） |
| `limit` | 整数（最大 100） | `50` | 取得件数（api/files のみ） |

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
