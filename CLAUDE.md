# Media Viewer — 仕様・アーキテクチャ

## 概要

ローカルネットワーク上のSambaサーバーに保存されたメディアファイル（画像・動画・PDF）を、ブラウザから閲覧するための軽量Webビューア。

## 動作環境と制約

### サーバー（ホスト）

- 自宅のミニPC上で常時稼働させる
- リソース（CPU・メモリ）の消費を最小限に抑える
- Sambaの共有ディレクトリは `mount -t cifs` でローカルパスとしてマウント済みの前提（SMBクライアントライブラリは使わない）
- マウントによりカーネルレベルのキャッシュが効くため、レイテンシが最小になる

### クライアント

- SIMの挿さっていない古いスマホからWiFi経由でアクセスする
- ブラウザが古い可能性があるため、フロントエンドはできる限り軽量・シンプルにする
- SPAフレームワークは使わない

## 技術スタック

| レイヤー | 技術 | 理由 |
|---------|------|------|
| 言語 | Crystal | コンパイル済みバイナリが軽量。常時稼働に適する |
| Webフレームワーク | Kemal | Crystal向けの軽量フレームワーク。必要十分 |
| テンプレート | ECR（Crystal標準） | 追加依存なし |
| フロントエンド | 素のHTML + CSS + vanilla JS | フレームワーク不使用。JSは必要最小限 |
| サムネイル生成 | libvips（vipsthumbnailコマンド） | ImageMagickより省メモリ |
| 動画サムネイル | ffmpeg | 先頭付近のフレーム抽出 |
| PDFサムネイル | poppler-utils（pdftoppm） | 1ページ目を画像化 |
| 設定 | YAML（Crystal標準ライブラリ） | 追加shard不要 |
| プロセス管理 | systemd | ミニPCの起動時に自動起動 |

### Crystal shards の依存

- `kemal` のみ。それ以外は極力Crystal標準ライブラリで賄う。

### 必要なシステムパッケージ

- `libvips-tools`
- `ffmpeg`
- `poppler-utils`
- `cifs-utils`

## 対応メディア種別

| 種別 | 拡張子 | サムネイル生成 | ビューア表示 |
|------|--------|-------------|------------|
| 画像 | jpg, jpeg, png, gif, webp, bmp, svg | vipsthumbnail | `<img>` |
| 動画 | mp4, webm, mkv, avi, mov | ffmpeg → vipsthumbnail | `<video>` (ブラウザネイティブ) |
| PDF | pdf | pdftoppm → vipsthumbnail | `<object>` または `<iframe>` (ブラウザ内蔵ビューア) |

上記以外のファイル・隠しファイル（`.`始まり）は一覧に表示しない。

## ルーティング

```
GET /                        → /browse/ にリダイレクト
GET /browse/                 → ルートディレクトリ一覧（SSR HTML）
GET /browse/*path            → 指定ディレクトリの一覧（SSR HTML、初回バッチ分）
GET /api/files/*path         → ファイル一覧JSON（無限スクロール用）
                               クエリパラメータ: offset (default: 0), limit (default: 50, max: 100)
GET /view/*path              → 個別ファイルのビューアページ（SSR HTML）
GET /raw/*path               → ファイル本体の配信（適切なContent-Type付き）
GET /thumbnail/*path         → サムネイル画像の配信（キャッシュ付き）
```

## ディレクトリ構成

```
media-viewer/
├── shard.yml
├── config.yml
├── media-viewer.service       # systemd用
├── src/
│   ├── app.cr                 # エントリポイント、Kemalルーティング定義
│   ├── config.cr              # 設定の読み込み（YAML）
│   ├── services/
│   │   ├── mime.cr            # 拡張子→Content-Type / MediaType判定
│   │   ├── file_browser.cr    # ディレクトリ走査、パス安全性検証、ページング
│   │   └── thumbnail.cr       # サムネイル生成・ディスクキャッシュ管理
│   └── views/
│       ├── layout.ecr         # 共通HTMLレイアウト
│       ├── directory.ecr      # ディレクトリ一覧（グリッド表示）
│       └── viewer.ecr         # 個別ファイルビューア
└── public/
    ├── style.css
    └── app.js                 # 遅延読み込み + 無限スクロール
```

## 各モジュールの責務

### config.cr

- `config.yml` からYAMLで設定を読み込む
- ファイルが存在しない場合はデフォルト値を使用
- `include YAML::Serializable` を使う（`YAML.mapping` は非推奨）

#### 設定項目

| キー | 型 | デフォルト | 説明 |
|------|-----|-----------|------|
| `media_root` | String | `/mnt/nas/media` | メディアファイルのルートディレクトリ |
| `cache_dir` | String | `~/.cache/media-viewer` | サムネイルキャッシュの保存先 |
| `port` | Int32 | `3000` | サーバーのリッスンポート |
| `thumbnail_size` | Int32 | `200` | サムネイルの最大辺（px） |
| `items_per_page` | Int32 | `50` | 1バッチあたりの読み込み件数 |

### services/mime.cr

- ファイル拡張子からContent-Type文字列を返す
- ファイル拡張子からMediaType（Image / Video / Pdf / Unknown）を判定する
- 対応拡張子かどうか（一覧に表示するか）を判定する

### services/file_browser.cr

- 指定ディレクトリの中身を走査し、`FileEntry` の配列として返す
- ソート順: ディレクトリが先、その後ファイル。それぞれアルファベット順（大文字小文字無視）
- 隠しファイル（`.`始まり）は除外
- 非対応ファイルは除外（ディレクトリは常に表示）
- offset / limit によるページング対応
- **パストラバーサル防止**: 相対パスを正規化し、`media_root` の外にアクセスできないことを保証する

#### FileEntry の構造

```
name       : String          # ファイル名
path       : String          # media_root からの相対パス
is_dir     : Bool
size       : Int64           # ディレクトリの場合は0
mtime      : Time
media_type : String          # "image", "video", "pdf", "unknown"
```

### services/thumbnail.cr

- ソースファイルのパスを受け取り、サムネイル画像（JPEG）のパスを返す
- サムネイルはディスク上にキャッシュする
- キャッシュキー: `SHA256(ファイルの絶対パス + ":" + mtimeのunixタイムスタンプ)` → `.jpg`
  - ファイルが更新されるとmtimeが変わるため自動的に再生成される
- 生成に失敗した場合は `nil` を返す（呼び出し側でフォールバック画像を返す）

#### メディア種別ごとの生成方法

1. **画像**: `vipsthumbnail <source> --size <SIZE>x<SIZE> -o <dest>[Q=80]`
2. **動画**: `ffmpeg` で1秒地点のフレームを一時ファイルに抽出 → `vipsthumbnail` でリサイズ → 一時ファイル削除
3. **PDF**: `pdftoppm` で1ページ目をJPEG化 → `vipsthumbnail` でリサイズ → 一時ファイル削除

## フロントエンド設計

### 方針

- CSSフレームワーク不使用。素のCSSでグリッドレイアウト（CSS Grid）
- JSフレームワーク不使用。vanilla JSのみ
- ダークテーマ基調
- 全体で CSS 2-3KB、JS 3-4KB 程度に収める

### ディレクトリ一覧ページ

- 初回表示はSSR（サーバーサイドレンダリング）でHTMLを返す。最初のバッチ分（items_per_page件）を含む
- 2バッチ目以降はJSから `/api/files/*` をfetchしてDOMに追記する**無限スクロール**方式
- スクロール検知には `IntersectionObserver` でページ末尾の番兵要素を監視する

### サムネイル遅延読み込み

- `<img>` の `src` は空にし、`data-src` に実際のURLを持たせる
- `IntersectionObserver` で画面に入ったら `src = data-src` で読み込む
- **画面外に出たら `src = ""` にして画像メモリを解放する**（DOMは残す）
- `IntersectionObserver` 非対応ブラウザではフォールバックとして全件 `src` を設定する

### 個別ビューアページ

- ページ遷移ベース（SPAではない）
- 前/次ファイルへのナビゲーションリンクを表示する（同ディレクトリ内のファイル順）
- 一覧に戻るリンクを表示する
- 画像: `<img>` で表示
- 動画: `<video controls>` で表示（ブラウザネイティブのプレイヤーに委ねる）
- PDF: `<object>` でブラウザ内蔵ビューアに委ねる。非対応ブラウザにはダウンロードリンクをフォールバック表示

### 動画のRange request対応

- `/raw/*` での動画配信時、HTTPのRangeヘッダーに対応する
- これによりブラウザのシークバーが正しく動作する
- Range指定がある場合は206 Partial Contentで該当バイト範囲のみ返す

## セキュリティ考慮事項

- パストラバーサル防止を必ず実装する（`..` や絶対パスで `media_root` の外に出られないこと）
- ローカルネットワーク内での利用を前提とし、認証機能は設けない
- Sambaマウントは読み取り専用（`ro`）を推奨

## デプロイ

### ビルド

```bash
shards install
crystal build src/app.cr --release -o media-viewer
```

### 実行

```bash
./media-viewer
```

### systemdによるデーモン化

ユニットファイルを `/etc/systemd/system/` に配置し、`systemctl enable --now media-viewer` で自動起動。リソース制限として `MemoryMax=256M`, `CPUQuota=50%` を設定する。

## 注意・補足

- `vipsthumbnail` のオプション書式はlibvipsのバージョンによって差異がある可能性がある。手元の環境で動作確認し、必要に応じて調整すること
- サムネイル生成は外部コマンド（`vipsthumbnail`, `ffmpeg`, `pdftoppm`）を `Process.run` で呼び出す。これらがPATH上に存在しない場合、サムネイルは生成されずフォールバック画像が返る
- Crystal標準ライブラリのYAMLシリアライゼーションは `include YAML::Serializable` を使う。旧APIの `YAML.mapping` は使わない


# AI-DLC and Spec-Driven Development

Kiro-style Spec Driven Development implementation on AI-DLC (AI Development Life Cycle)

## Project Context

### Paths
- Steering: `.kiro/steering/`
- Specs: `.kiro/specs/`

### Steering vs Specification

**Steering** (`.kiro/steering/`) - Guide AI with project-wide rules and context
**Specs** (`.kiro/specs/`) - Formalize development process for individual features

### Active Specifications
- Check `.kiro/specs/` for active specifications
- Use `/kiro:spec-status [feature-name]` to check progress

## Development Guidelines
- Think in English, generate responses in English. All Markdown content written to project files (e.g., requirements.md, design.md, tasks.md, research.md, validation reports) MUST be written in the target language configured for this specification (see spec.json.language).

## Minimal Workflow
- Phase 0 (optional): `/kiro:steering`, `/kiro:steering-custom`
- Phase 1 (Specification):
  - `/kiro:spec-init "description"`
  - `/kiro:spec-requirements {feature}`
  - `/kiro:validate-gap {feature}` (optional: for existing codebase)
  - `/kiro:spec-design {feature} [-y]`
  - `/kiro:validate-design {feature}` (optional: design review)
  - `/kiro:spec-tasks {feature} [-y]`
- Phase 2 (Implementation): `/kiro:spec-impl {feature} [tasks]`
  - `/kiro:validate-impl {feature}` (optional: after implementation)
- Progress check: `/kiro:spec-status {feature}` (use anytime)

## Development Rules
- 3-phase approval workflow: Requirements → Design → Tasks → Implementation
- Human review required each phase; use `-y` only for intentional fast-track
- Keep steering current and verify alignment with `/kiro:spec-status`
- Follow the user's instructions precisely, and within that scope act autonomously: gather the necessary context and complete the requested work end-to-end in this run, asking questions only when essential information is missing or the instructions are critically ambiguous.

## Steering Configuration
- Load entire `.kiro/steering/` as project memory
- Default files: `product.md`, `tech.md`, `structure.md`
- Custom files are supported (managed via `/kiro:steering-custom`)
