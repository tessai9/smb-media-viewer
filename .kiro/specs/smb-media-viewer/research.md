# Research & Design Decisions

---
**Purpose**: 設計判断の根拠と調査記録を保持する。

---

## Summary

- **Feature**: `smb-media-viewer`
- **Discovery Scope**: New Feature（グリーンフィールド）
- **Key Findings**:
  - 技術スタック（Crystal + Kemal + ECR + Vanilla JS）は CLAUDE.md で確定済みのため、ライブラリ選定の比較調査は不要
  - レイヤードアーキテクチャ（Router → Services → Views）がこの規模・制約に最適であり、ヘキサゴナル等の重厚なパターンは過剰
  - CIFSマウント前提により SMB ライブラリ不要・カーネルキャッシュの恩恵を受けられる
  - IntersectionObserver + 番兵要素による無限スクロールが古いブラウザとのトレードオフを最小化する唯一の妥当な選択肢

## Research Log

### Crystal + Kemal のルーティング能力確認

- **Context**: Kemal がワイルドカードルート（`/browse/*path`）と Range リクエストを標準でサポートするか確認
- **Findings**:
  - Kemal は `get "/path/*glob"` で splat キャプチャをサポートする
  - Range リクエストはKemalが自動処理しないため、`env.request.headers["Range"]?` を手動でパースし、`env.response.status_code = 206` をセットする必要がある
  - `env.response.headers["Accept-Ranges"] = "bytes"` も手動設定が必要
- **Implications**: RawRoute の Range 処理は完全に自前実装となる。実装ブロックは Router (app.cr) 内に収める

### vipsthumbnail コマンドオプション

- **Context**: libvips のバージョン差異による CLI オプション変化の可能性（CLAUDE.md の補足より）
- **Findings**:
  - 標準的なオプション: `vipsthumbnail <src> --size WxH -o <dest>[Q=80]`
  - `-o` の出力パスに `[Q=80]` を角括弧で付加するのは libvips 8.6+ の書式
  - libvips 8.5 以前では `--vips-progress` 等のオプション配置が異なるケースがある
  - `Process.run` の戻り値（終了コード）でエラーを検出する
- **Implications**: ThumbnailService の生成メソッドは `Process.run` の終了コードを確認し、非0の場合は `nil` を返す

### pdftoppm の出力ファイル名パターン

- **Context**: `pdftoppm` は出力ファイル名に自動でページ番号サフィックスを付加する
- **Findings**:
  - `pdftoppm -jpeg -f 1 -l 1 input.pdf /tmp/prefix` は `/tmp/prefix-1.jpg` （または `-01.jpg`）を生成する
  - ページ数によってゼロパディング桁数が変化するため、glob で最初のファイルを取得する必要がある
- **Implications**: ThumbnailService の PDF 処理では `Dir.glob("#{tmp_prefix}-*.jpg").first?` パターンで出力ファイルを特定する

### IntersectionObserver と古いブラウザの互換性

- **Context**: ターゲットデバイスに古いスマートフォン（Android 4.x 等の可能性）が含まれる
- **Findings**:
  - IntersectionObserver は Chrome 51+, Firefox 55+, Safari 12.1+ でサポート
  - Android 4.x の WebView は非対応の可能性が高い
  - polyfill 導入はJSサイズ制約（3-4KB）に反するため不採用
  - フォールバック: `typeof IntersectionObserver !== 'undefined'` で分岐し、非対応時は全件即時表示
- **Implications**: 要件 5.5 のフォールバック実装が必須。古いブラウザではメモリ解放は行われないが、機能的には動作する

### SHA256 キャッシュキーの実装

- **Context**: Crystal 標準ライブラリでの SHA256 計算方法
- **Findings**:
  - `require "digest/sha256"` で利用可能
  - `Digest::SHA256.hexdigest("#{abs_path}:#{mtime.to_unix}")` で文字列ハッシュ値を取得できる
- **Implications**: shard 追加不要。ThumbnailService 内で完結する

---

## Architecture Pattern Evaluation

| オプション | 概要 | 強み | リスク/制約 | 評価 |
|----------|------|------|------------|------|
| レイヤードアーキテクチャ | Router → Services → Views の3層 | シンプル・把握しやすい・小規模に適切 | 層間の依存が直線的でテスト難易度やや高 | **採用** |
| ヘキサゴナル（Ports & Adapters） | コアドメインをアダプタで囲む | テスト容易性高・外部依存の差し替えが容易 | この規模では過剰・ボイラープレート増大 | 不採用 |
| MVC | Model-View-Controller | Webアプリの標準的パターン | CrystalにはRailsのようなMVCフレームワークがない | Kemalはルーターのみのため自然にレイヤードに収束 |

---

## Design Decisions

### Decision: thin controller パターン

- **Context**: ルーティングロジックとビジネスロジックの分離方針
- **Alternatives Considered**:
  1. ファットコントローラ — app.cr にすべてのロジックを書く
  2. サービス委譲 — app.cr はルーティングのみ、ロジックはサービス層に委譲
- **Selected Approach**: サービス委譲（thin controller）
- **Rationale**: サービス層が HTTP 非依存になることでユニットテストが容易になる。また、CLAUDE.md のアーキテクチャ方針と一致する
- **Trade-offs**: サービスファイル数が増えるが、各ファイルの責務が明確になる
- **Follow-up**: FileBrowser.safe_path のテストケースを優先的に作成する

### Decision: サムネイル生成失敗時の nil 返却

- **Context**: 外部コマンド（vipsthumbnail/ffmpeg/pdftoppm）が PATH 上に存在しない、またはクラッシュした場合の振る舞い
- **Alternatives Considered**:
  1. 例外を伝播させて 500 を返す
  2. nil を返してフォールバック画像を使用する
- **Selected Approach**: nil を返してフォールバック
- **Rationale**: サムネイル生成はオプション機能であり、生成失敗がコンテンツ閲覧を妨げるべきでない。Graceful Degradation の方針に合致する
- **Trade-offs**: フォールバック画像（静的 SVG またはインライン PNG）の準備が必要
- **Follow-up**: フォールバック画像を `public/` に配置し、thumbnail ルートで 302 リダイレクトする

### Decision: JSON API のページング上限強制

- **Context**: `/api/files/*path?limit=99999` のような過大なリクエストへの対応
- **Alternatives Considered**:
  1. エラー (400) を返す
  2. 上限（100）にクランプして正常応答する
- **Selected Approach**: クランプ（上限100に切り詰め）
- **Rationale**: ホームユーザーの誤用を想定しており、エラーではなく安全な挙動にする。FileBrowser 内でクランプすることで Router が意識しなくて済む
- **Trade-offs**: 呼び出し元が上限超えに気づきにくいが、ホームユースでは許容範囲

---

## Risks & Mitigations

- **CIFS マウント切断** — ファイルシステムアクセス中に例外が発生する。Router 層で rescue して 500 を返し、ログに記録する
- **外部コマンド不在** — PATH に vipsthumbnail/ffmpeg/pdftoppm がない場合、サムネイルは nil になる。フォールバック画像で吸収するが、初回デプロイ時のチェックリストにコマンド存在確認を含める
- **古いブラウザの IntersectionObserver 非対応** — フォールバックで全件即時表示。大量ファイル時のメモリ消費増大は許容する（古いデバイスの制約）
- **pdftoppm 出力ファイル名の不確実性** — ゼロパディング桁数がページ数依存。glob で特定する実装で対応する

## References

- Kemal Framework: https://kemalcr.com/
- Crystal Process.run: https://crystal-lang.org/api/Process.html
- libvips vipsthumbnail: https://www.libvips.org/API/current/Using-vipsthumbnail.md.html
- IntersectionObserver MDN: https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API
- HTTP Range Requests: https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests
