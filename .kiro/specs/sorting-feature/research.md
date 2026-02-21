# Research & Design Decisions

---
**Purpose**: Discovery findings for the sorting-feature extension.

---

## Summary

- **Feature**: `sorting-feature`
- **Discovery Scope**: Extension（既存システムへの機能追加）
- **Key Findings**:
  - Crystal の `File::Info#creation_time` は Crystal 1.x で利用可能。CIFS/Samba マウント上では Windows NTFS の birthtime が `statx(STATX_BTIME)` 経由で取得される
  - `list_entries` のデフォルトパラメータを使えば、既存呼び出し元（`/view/*` など）を変更せずに後方互換性を維持できる
  - `@[JSON::Field(ignore: true)]` アノテーションで `ctime` フィールドを JSON 出力から除外しつつソートに活用できる
  - `<form method="get">` による JS レスフォームソートで、古いブラウザを含む全クライアントに対応できる

---

## Research Log

### Crystal `File::Info#creation_time` の可用性

- **Context**: ソートキー `ctime` を実装するために Crystal がファイル作成日時を取得できるか確認する必要があった
- **Findings**:
  - Crystal 1.x の `File::Info` は `creation_time : Time` プロパティを持つ
  - Linux では `statx` システムコール（`STATX_BTIME`）で birthtime を取得する（Crystal 1.0+ 対応）
  - CIFS マウント（SMB2/3）では Windows NTFS の creation time が転送されるため通常利用可能
  - birthtime 非対応 fs（例: ext3）では `mtime` と同値にフォールバックするが、これはソートの誤動作ではなく単に区別できないだけ
- **Implications**: `FileEntry` に `ctime : Time` フィールドを追加し、`File::Info#creation_time` で設定する。JSON 出力には不要なため `@[JSON::Field(ignore: true)]` で除外する

### JS レスソート UI の設計

- **Context**: 要件 5.4 が JS 不使用・旧ブラウザ対応を指定している
- **Findings**:
  - `<form method="get">` はページ全体を `?sort=X&order=Y` 付きで再ロードするため、サーバーサイドソートと完全に整合する
  - `<select>` + `<button type="submit">` の組み合わせは全ブラウザで動作する
  - `<option selected>` 属性で現在のソート状態を視覚的に示せる（ECR テンプレート側で active 判定）
- **Implications**: `directory.ecr` に `<form class="sort-bar" method="get">` を追加。ECR テンプレートは `sort_key` と `sort_dir` の値を受け取り、対応する `<option>` に `selected` を付与する

### 無限スクロール API との整合

- **Context**: `app.js` の `loadMore` が `/api/files/*` を fetch するとき、ソートパラメータを同期する必要がある
- **Findings**:
  - `.grid` div に `data-sort` / `data-order` 属性を追加するだけで JS 側が読み取れる
  - これは既存の `data-path` / `data-offset` パターンと完全に一致する
  - `app.js` の変更量は最小限（fetch URL に 2 パラメータを追加するだけ）
- **Implications**: `directory.ecr` で `.grid` に `data-sort` と `data-order` を追加。`app.js` の `loadMore` で `grid.dataset.sort` と `grid.dataset.order` を読む

---

## Architecture Pattern Evaluation

| オプション | 説明 | 強み | リスク/制限 |
|-----------|------|------|------------|
| サービス層で SortKey/SortDir enum を定義 | `file_browser.cr` に enum を追加し `list_entries` シグネチャを拡張 | 型安全・テスト容易・既存パターンに準拠 | なし |
| 文字列パラメータをサービス層まで直接伝播 | ルート層で parse せずそのまま渡す | 実装が簡単 | サービス層に HTTP の知識が漏出する（steering 違反） |
| クライアントサイドソート（JS） | JSON API からの全件取得後に JS でソート | SSR 不要 | 古いブラウザ非対応・大量ファイルでメモリ問題 |

**選択**: サービス層で enum を定義するアプローチ。ルート層が parse 責務を持ち、サービス層は enum を受け取る。steering の「サービス層は HTTP を知らない」原則に準拠。

---

## Design Decisions

### Decision: `ctime` の JSON 除外

- **Context**: `FileEntry` は `JSON::Serializable` を include しているため、追加したフィールドはすべて API レスポンスに含まれる
- **Alternatives Considered**:
  1. `ctime` を JSON に含める — クライアントで将来的に利用可能だが、ペイロードが増加する
  2. `@[JSON::Field(ignore: true)]` で除外 — ペイロード最小・API 契約変化なし
- **Selected Approach**: `@[JSON::Field(ignore: true)]` で除外
- **Rationale**: クライアント側でソートする要件はなく、現時点で不要なデータを API に追加しない（over-fetching 防止）
- **Trade-offs**: 将来クライアントサイドで `ctime` が必要になれば、アノテーションを外すだけで済む

### Decision: `list_entries` のデフォルトパラメータによる後方互換

- **Context**: `/view/*path` など他のルートも `list_entries` を呼び出しており、これらにはソートパラメータを渡さない
- **Selected Approach**: `sort_key : SortKey = SortKey::Name, sort_dir : SortDir = SortDir::Asc` をデフォルト値として追加
- **Rationale**: Crystal のデフォルトパラメータにより、既存の呼び出し元はコード変更不要。デフォルトは現行の Name/Asc 固定ソートと同一なので動作変化なし

---

## Risks & Mitigations

- **birthtime 非対応ファイルシステム**: `ctime` == `mtime` になる可能性がある — ユーザーへの告知は不要（表示は変わらないため）
- **ソートパラメータのインジェクション**: `sort` / `order` に無効値が入った場合はデフォルトにサイレントフォールバックする（要件 1.2、2.2、4.3）
- **CSS サイズ超過**: `sort-bar` スタイル追加で 3KB 制限を超えないよう、最小限のスタイルのみ追加する

---

## References

- Crystal `File::Info` API: https://crystal-lang.org/api/File/Info.html
- Crystal `JSON::Field` annotation: https://crystal-lang.org/api/JSON/Field.html
- Crystal enum syntax: https://crystal-lang.org/reference/syntax_and_semantics/enum.html
