# wasm5 開発ロードマップ

## test262 統合状況

### 実装完了

#### Phase 1: String メソッド
- [x] charAt - 文字位置から1文字を取得
- [x] trim - 前後の空白を削除
- [x] substring - 部分文字列を抽出
- [x] indexOf - 部分文字列の検索
- [x] split - 文字列を分割
- [x] replace - 文字列を置換

#### Phase 1: Math メソッド
- [x] min - 最小値を取得
- [x] max - 最大値を取得
- [x] round - 四捨五入
- [x] floor - 切り捨
- [x] ceil - 切り上げ
- [x] abs - 絶対値
- [x] sqrt - 平方根
- [x] random - 乱数生成

#### Array メソッド
- [x] map - 各要素に関数を適用
- [x] filter - 条件に合う要素を抽出
- [x] reduce - 畺り込み
- [x] forEach - 各要素に関数を実行
- [x] find - 条件に合う要素を検索
- [x] slice - 部分配列を抽出
- [x] concat - 配列を結合
- [x] unshift - 先頭に要素を追加

#### test262 harness
- [x] assert.mbt - assert 関数の実装
- [x] sta.mbt - Test262Error と $DONOTEVALUATE の実装

#### ホスト定義関数
- [x] print - �準出力
- [x] $262 - test262固有のオブジェクト

### 実装進行中

#### Phase 2: this キーワード
- [ ] メソッド呼び出し時の this バインディング
- [ ] コンストラクタ内の this 参照
- [ ] bind/call/apply メソッド

### 未実装
- [ ] Phase 3: パーサ拡演算子（??, ?. ）
- [ ] Phase 4: try/catch/finally 構造
- [ ] Phase 5: モジュール
- [ ] Phase 6: クラス構文
- [ ] 正規表現
- [ ] ジェネレータ
- [ ] Symbol/WeakMap/WeakSet
- [ ] Proxy/Reflect

### 既存の課題
- [ ] Number/JSValue 型の曖昧性
- [ ] 配列メソッドの実装で大量のコンパイルエラー

### 次のステップ
1. Array メソッドのコンパイルエラーを解消
2. test262 harness の実装を完了する
3. test262 ホスト定義関数を追加して、テストランナーを作成
