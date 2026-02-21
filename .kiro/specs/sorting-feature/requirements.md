# Requirements Document

## Project Description (Input)
smb-media-viewer sorting-feature

## Introduction

SMB メディアビューアのディレクトリ一覧に、ユーザーが操作可能なソート機能を追加する。現在の実装では「ディレクトリ優先・アルファベット順」の固定ソートのみが提供されているが、ユーザーが名前・作成日時・更新日時を基準にソートし、昇順・降順を切り替えられるようにする。ソート状態は URL クエリパラメータで管理し、ページの共有やブックマークに対応する。

---

## Requirements

### 1. ソートキーの選択

**Objective:** ホームネットワークのユーザーとして、ディレクトリ一覧のソート基準を選択したい。最近追加した写真や最後に更新したファイルをすばやく見つけられるようにするため。

#### Acceptance Criteria

1. The Media Viewer shall support three sort keys for directory listings: `name`（ファイル名、大文字小文字無視）、`ctime`（ファイルの作成日時）、`mtime`（ファイルの最終更新日時）。
2. When a sort key query parameter is absent or invalid, the Media Viewer shall default to `name` ascending order.
3. The Media Viewer shall apply the same sort key to both the SSR initial batch and the JSON API responses for the same directory.

---

### 2. ソート方向の制御

**Objective:** ホームネットワークのユーザーとして、ソートの昇順・降順を切り替えたい。最新ファイルを先頭に表示したり、名前の逆順で探したりできるようにするため。

#### Acceptance Criteria

1. The Media Viewer shall support two sort directions: `asc`（昇順）と `desc`（降順）。
2. When a sort direction query parameter is absent or invalid, the Media Viewer shall default to `asc`.
3. When the sort key is `ctime` and the direction is `desc`, the Media Viewer shall display the most recently created files first.
4. When the sort key is `mtime` and the direction is `desc`, the Media Viewer shall display the most recently modified files first.
5. When the sort key is `name` and the direction is `asc`, the Media Viewer shall sort entries in case-insensitive alphabetical order from A to Z.

---

### 3. ディレクトリ優先表示の維持

**Objective:** ホームネットワークのユーザーとして、いかなるソート設定でもディレクトリを常にファイルより先に表示したい。ナビゲーションの一貫性を保つため。

#### Acceptance Criteria

1. The Media Viewer shall always display directory entries before file entries, regardless of the active sort key or direction.
2. When sort key is `ctime` or `mtime`, the Media Viewer shall sort directories among themselves and files among themselves independently, keeping the two groups separated.
3. The Media Viewer shall apply sort direction to both the directory group and the file group independently.

---

### 4. URL クエリパラメータによるソート状態管理

**Objective:** ホームネットワークのユーザーとして、ソート済みの一覧ページを URL で共有・ブックマークしたい。再訪問時に同じ表示順を再現できるようにするため。

#### Acceptance Criteria

1. The Media Viewer shall accept `sort` and `order` as URL query parameters on `GET /browse/` and `GET /browse/*path` routes (例: `?sort=mtime&order=desc`).
2. The Media Viewer shall accept `sort` and `order` as URL query parameters on `GET /api/files/` and `GET /api/files/*path` routes, to ensure the infinite scroll batches use the same sort as the SSR initial page.
3. When `sort` or `order` values are invalid, the Media Viewer shall silently fall back to defaults without returning an error.
4. The Media Viewer shall include the active `sort` and `order` values in the HTML page so the frontend can append them to subsequent `/api/files/*` fetch requests.

---

### 5. ソート UI コントロール

**Objective:** ホームネットワークのユーザーとして、ブラウザ上でソートキーと方向を視覚的に切り替えたい。ページの再読み込みを使って直感的にソートを変更できるようにするため。

#### Acceptance Criteria

1. The Media Viewer shall render sort controls in the directory listing page that allow selection of sort key (`name` / `ctime` / `mtime`) and direction (`asc` / `desc`).
2. When a user selects a sort option, the Media Viewer shall navigate to the same directory URL with updated `sort` and `order` query parameters, causing a full page reload with the new sort applied.
3. The Media Viewer shall visually indicate the currently active sort key and direction in the sort controls.
4. The Media Viewer shall render sort controls using only HTML form elements or anchor links (JavaScript は不要。古いブラウザでも動作すること)。
5. The Media Viewer shall keep the sort controls within the existing `<nav>` or directly above the grid, without adding a separate full-page layout element.

---

### 6. ページングとの整合性

**Objective:** ホームネットワークのユーザーとして、無限スクロールでロードした追加バッチもソート順が一貫していることを期待したい。一覧の途中で表示順が変わらないようにするため。

#### Acceptance Criteria

1. When the frontend fetches subsequent batches via `/api/files/*`, the Media Viewer shall apply the same `sort` and `order` parameters as the initial SSR page, maintaining a consistent sort order across all loaded entries.
2. The Media Viewer shall treat `offset` relative to the full sorted list, so that paginated batches are contiguous and free of duplicates or gaps.
3. If `offset` is beyond the end of the sorted list, the Media Viewer shall return an empty array (既存の動作を維持)。
