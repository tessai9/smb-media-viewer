# 要件定義書

## はじめに

本ドキュメントは、ローカルネットワーク上のSambaサーバーにCIFSマウントされたメディアファイル（画像・動画・PDF）を、ブラウザから閲覧するための軽量Webビューア「SMB Media Viewer」の要件を定義する。対象ユーザーは自宅LAN上のデバイス（古いスマートフォンを含む）からアクセスするホームユーザーである。

## 要件

### 要件 1: ディレクトリ閲覧

**目的:** ホームユーザーとして、NASにマウントされたディレクトリをブラウザで一覧表示したい。そうすることで、目的のメディアファイルにすばやくたどり着ける。

#### 受け入れ基準

1. When ユーザーが `/` にアクセスしたとき, the Media Viewer shall `/browse/` にリダイレクトする。
2. When ユーザーが `/browse/` または `/browse/*path` にアクセスしたとき, the Media Viewer shall 指定ディレクトリの内容をサーバーサイドレンダリングしたHTMLページを返す。
3. The Media Viewer shall ディレクトリ一覧においてディレクトリを先に、その後ファイルをそれぞれアルファベット順（大文字小文字無視）で表示する。
4. The Media Viewer shall 隠しファイル（ファイル名が `.` で始まるもの）を一覧に表示しない。
5. The Media Viewer shall 対応外の拡張子を持つファイルを一覧に表示しない（ディレクトリは常に表示する）。
6. When ユーザーが `/api/files/*path` にアクセスしたとき, the Media Viewer shall `offset` と `limit` クエリパラメータに従ったファイル一覧をJSON形式で返す（デフォルト: offset=0, limit=50、最大: 100）。

---

### 要件 2: メディア表示

**目的:** ホームユーザーとして、画像・動画・PDFの各ファイルをブラウザで直接閲覧したい。そうすることで、別のアプリを使わずにコンテンツを楽しめる。

#### 受け入れ基準

1. When ユーザーが `/view/*path` にアクセスしたとき, the Media Viewer shall そのファイルの種別に応じたビューアページ（SSR HTML）を返す。
2. Where ファイルが画像（jpg, jpeg, png, gif, webp, bmp, svg）のとき, the Media Viewer shall `<img>` タグでファイルを表示する。
3. Where ファイルが動画（mp4, webm, mkv, avi, mov）のとき, the Media Viewer shall `<video controls>` タグでブラウザネイティブのプレイヤーを使って表示する。
4. Where ファイルがPDF（pdf）のとき, the Media Viewer shall `<object>` タグでブラウザ内蔵ビューアを使って表示し、非対応ブラウザにはダウンロードリンクをフォールバックとして表示する。
5. The Media Viewer shall ビューアページに同一ディレクトリ内の前後ファイルへのナビゲーションリンクと、一覧に戻るリンクを表示する。
6. When ユーザーが `/raw/*path` にアクセスしたとき, the Media Viewer shall ファイル本体を適切な `Content-Type` ヘッダーとともに配信する。

---

### 要件 3: 動画シーク対応

**目的:** ホームユーザーとして、動画をシークバーで任意の位置から再生したい。そうすることで、長い動画でも快適に視聴できる。

#### 受け入れ基準

1. When ブラウザが `Range` ヘッダーつきのリクエストを `/raw/*path` に送ったとき, the Media Viewer shall HTTP 206 Partial Content で指定されたバイト範囲のみを返す。
2. If `Range` ヘッダーが指定されていないとき, the Media Viewer shall ファイル全体を HTTP 200 で返す。
3. The Media Viewer shall 動画配信時に `Accept-Ranges: bytes` ヘッダーを返す。

---

### 要件 4: サムネイル生成・キャッシュ

**目的:** ホームユーザーとして、各ファイルのサムネイルを一覧で確認したい。そうすることで、内容を開く前に把握できる。

#### 受け入れ基準

1. When ユーザーが `/thumbnail/*path` にアクセスしたとき, the Media Viewer shall そのファイルのサムネイルJPEG画像を返す。
2. The Media Viewer shall サムネイルをディスク上にキャッシュし、`SHA256(絶対パス + ":" + mtimeのUnixタイムスタンプ)` をキャッシュキーとして使用する。
3. Where ファイルが画像のとき, the Media Viewer shall `vipsthumbnail` を使ってサムネイルを生成する。
4. Where ファイルが動画のとき, the Media Viewer shall `ffmpeg` で1秒地点のフレームを抽出し、`vipsthumbnail` でリサイズしてサムネイルを生成する。
5. Where ファイルがPDFのとき, the Media Viewer shall `pdftoppm` で1ページ目を画像化し、`vipsthumbnail` でリサイズしてサムネイルを生成する。
6. If サムネイル生成が失敗したとき, the Media Viewer shall `nil` を返し、呼び出し元はフォールバック画像を配信する。
7. When ソースファイルが更新（mtime変更）されたとき, the Media Viewer shall 次回のサムネイルリクエスト時に新しいキャッシュキーで再生成する。

---

### 要件 5: 遅延読み込みと無限スクロール

**目的:** ホームユーザーとして、大量のファイルがあるディレクトリでもスムーズにスクロールしたい。そうすることで、古いスマートフォンでも快適に操作できる。

#### 受け入れ基準

1. The Media Viewer shall 初回ページ表示時に最初のバッチ（`items_per_page` 件）をSSRでHTMLに含めて返す。
2. While ユーザーがスクロールしてページ末尾の番兵要素が画面に入ったとき, the Media Viewer shall `/api/files/*` をfetchして次のバッチをDOMに追記する（無限スクロール）。
3. The Media Viewer shall `IntersectionObserver` を使ってサムネイル画像の遅延読み込みを実装し、画面内に入ったタイミングで `src` に実際のURLを設定する。
4. When サムネイル要素が画面外に出たとき, the Media Viewer shall `src` を空文字にして画像メモリを解放する（DOMは残す）。
5. If ブラウザが `IntersectionObserver` に非対応のとき, the Media Viewer shall フォールバックとして全件の `src` を即時設定する。

---

### 要件 6: パス安全性とセキュリティ

**目的:** システム管理者として、ユーザーが `media_root` 外のファイルにアクセスできないことを保証したい。そうすることで、サーバー上の任意ファイルへの不正アクセスを防げる。

#### 受け入れ基準

1. The Media Viewer shall すべてのファイルアクセス前に相対パスを正規化し、`media_root` の外を指すパスを拒否する（パストラバーサル防止）。
2. If リクエストパスが `..` や絶対パスを使って `media_root` の外を指しているとき, the Media Viewer shall HTTP 400 または 404 を返す。
3. The Media Viewer shall 認証機能を設けず、ローカルネットワーク内からのアクセスを前提とする。

---

### 要件 7: 設定

**目的:** ホームユーザーとして、設定ファイルでサーバーの動作をカスタマイズしたい。そうすることで、自分の環境に合わせて柔軟に調整できる。

#### 受け入れ基準

1. The Media Viewer shall `config.yml` が存在する場合はその値を読み込み、存在しない場合はデフォルト値を使用する。
2. The Media Viewer shall 以下の設定項目をサポートする: `media_root`（デフォルト: `/mnt/nas/media`）、`cache_dir`（デフォルト: `~/.cache/media-viewer`）、`port`（デフォルト: `3000`）、`thumbnail_size`（デフォルト: `200`）、`items_per_page`（デフォルト: `50`）。
3. When `port` 設定で指定されたポートでサーバーが起動したとき, the Media Viewer shall そのポートでHTTPリクエストを受け付ける。
