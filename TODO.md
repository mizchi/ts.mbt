# test262 進捗

## 現状 (2026-01-31)

| カテゴリ | Passed | Total | 達成率 |
|---------|--------|-------|--------|
| allowlist 全体 | 19,122 | 30,225 | 63% |
| negative テスト | 3,902 | 4,447 | 88% |
| language | 12,678 | 20,430 | 62% |

---

## 次にやるべきこと

### 高優先度

1. **async generator の yield* 対応**
   - yield* の thenable 処理

2. **iterator.return() / throw()**
   - ループ中断時のクリーンアップ
   - for-of の early termination

3. **行終端子の処理改善**
   - CR (U+000D) をコメント終端として認識

### 中優先度

4. **正規表現リテラル パーサー**
   - `/pattern/flags` 構文

5. **Symbol 完全対応**
   - Symbol.iterator → @@iterator (現在の代替)
   - Well-known symbols

### 低優先度 (ES2024+)

- `using` declaration
- import defer
- import attributes

---

## 完了した項目

- ✅ strict mode 重複パラメータ禁止
- ✅ strict mode での eval/arguments 代入禁止
- ✅ for-await-of パーサー修正
- ✅ async generator 基本対応

---

## 対応しない項目

- with statement (非推奨、3,469件スキップ)
- eval の一部高度な機能
- 末尾呼び出し最適化 (TCO)

---

## スキップ理由の内訳 (4,302件)

| 理由 | 件数 |
|------|------|
| with statement | 3,469 |
| module syntax | 319 |
| fixture | 252 |
| missing includes | 262 |
