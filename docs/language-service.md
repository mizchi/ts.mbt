# 型チェッカを JS ライブラリとして使う

CLI (`mtsc`) 以外から型チェッカを呼ぶための API です。`src/mtsc` を
`--target js` でビルドすると、TypeScript の Language Service に似た形の
ESM モジュールが出ます。

```sh
just build-js                     # moon build --target js --release + js/mtsc.js へコピー
just verify-language-service      # Node で実際に動かす (22 cases)
just verify-language-service-types # 同梱 .d.ts を tsc --strict で検査
```

```js
import {
  createLanguageService,
  createNodeHost,
  formatDiagnostics,
} from "./js/language-service.mjs";

const service = createLanguageService(createNodeHost(["src/main.ts"]));
console.log(formatDiagnostics(service.getProgramDiagnostics()));
```

## 外部 IO は注入する

**チェッカ自体にファイルシステムは入っていません。** IO は `host` として
外から渡します。これは TypeScript と同じ分担で、`LanguageServiceHost` が
ファイルアクセスを供給し、解決 (module resolution) はサービス側がやります。

```js
const host = {
  getScriptFileNames: () => ["/p/entry.ts"],   // 必須: エントリ
  readFile: (path) => sources[path],           // 必須 (or getScriptSnapshot)
  getCurrentDirectory: () => "/p",             // 省略可、既定 "."
  getCompilationSettings: () => ({ jsx: true }), // 省略可
};
```

`readFile` は **存在確認も兼ねています**。無いものは `undefined` を返して
ください。`file_exists` を別に持たない理由はこれで、二つあると片方だけ
実装されて食い違う余地が生まれます。解決は候補パスを何通りも試すので、
存在しないパスを聞かれるのは異常ではなく通常の動作です。`readFileSync`
を直結して ENOENT が飛んでも内部で `undefined` として扱います。

同梱の host が二つあります。

| host | 用途 |
| --- | --- |
| `createMemoryHost(files)` | バンドラのプラグインなど、ソースを既に持っている場合 |
| `createNodeHost(roots)` | `node:fs` を読む。実装は 10 行 |

`createNodeHost` が 10 行で済むことが、この抽象の意味です。チェッカに
ファイルシステムが入っていないので、与えるのはこれだけで足ります。

MoonBit 側では `MtscHost` trait です。struct of closures ではなく trait に
したのは、**`impl` が全メソッドの実装を要求する**からです。既定実装で
黙って fail open する host は書けません。この repo が繰り返し払ってきた
「一つの規則が一部の場所にしか適用されていない」バグを、この境界では
コンパイラが防ぎます。

### なぜ `src/parser` の resolver と共通化しないのか

`src/parser/module_resolver.mbt` は既に npm `exports` / `typesVersions` /
`node:*` / `@types/*` / tsconfig `paths` を解決します。そちらは
**26 個の `async fn`** が非同期ファイルシステムの上に乗っています。
`LanguageServiceHost.readFile` は設計上同期なので、同期 trait では
resolver に使えず、非同期 trait では host に使えません。片方にしか
合わない interface を今推測で共通化しないという判断です。

## 何を返すか

```ts
interface Diagnostic {
  file: string;
  category: "error";
  source: "syntactic" | "semantic" | "import";
  messageText: string;
  context: string;   // "function foo > return" のような位置の手がかり
}
```

**`start` / `length` はありません。** これは手抜きではなく、チェッカの
性質です。`@checker.ExprIssue` はメッセージと breadcrumb を持ち、
`@parser.ParseError` はメッセージだけを持ち、どちらもオフセットを
持ちません。無い span を捏造すると間違った箇所に波線が出るので、
出しません。`ts.Diagnostic` はこの二つを optional に宣言しているので
(位置に紐づかない診断のため)、チェックしてから使う consumer はそのまま
動きます。代わりに `context` が宣言内のどこで失敗したかを示します。

これは `fixtures/language-service/types_consumer.ts` が `keyof` で
pin しています。`start` が生えたらそこが落ちるので、ドキュメントと型が
一緒に更新されます。

## API

| 関数 | 対応する TypeScript |
| --- | --- |
| `createLanguageService(host)` | `ts.createLanguageService` |
| `.getProgramDiagnostics()` | `program.getSemanticDiagnostics()` 全体 |
| `.getSemanticDiagnostics(file)` | 同名 |
| `.getSyntacticDiagnostics(file)` | 同名 |
| `.getProgramFileNames()` | `program.getSourceFiles().map(f => f.fileName)` |
| `.resolveModuleName(from, spec)` | `resolveModuleNames` の 1 件版 |

`getSemanticDiagnostics(file)` でも **プログラム全体をロードします**。
その必要があります: そのファイルの型は import 先の宣言に依存するので、
単体で見れば import した型は全部未解決になります。TypeScript も同じで、
あれは program に対する query であって 1 ファイルのコンパイルではありません。

これは**コスト**でもあります。1 回の呼び出しがプログラム 1 回のロードなので、
**全ファイルを回すループはプログラムに対して 2 乗**になります。全体を
見たいなら `getProgramDiagnostics()` を 1 回呼んで `file` で絞ってください。

ファイル単位のキャッシュは意図的に持っていません。invalidate するには
host 側に version channel (TypeScript の `getScriptVersion`) が必要で、
この host にはそれがなく、invalidate できないキャッシュは
「書いてあるコスト」より悪いからです。per-file の query がホットパスに
なったら、足すべきものは `script_version` です。

### 移植していない部分

completions / quick info / definitions / rename / formatting は入って
いません。全部 position を要求するので、上記の通り中身のない形だけの
API になります。

module resolution は**相対指定子のみ**です。`react` や `node:fs` のような
bare specifier は解決しません。`resolveModuleName` はこの二つを区別して
返します。

```js
service.resolveModuleName("/p/entry.ts", "./score");
// { resolvedFileName: "/p/score.ts", isExternal: false }
service.resolveModuleName("/p/entry.ts", "./nope");
// { resolvedFileName: "", isExternal: false }   ← 解決失敗。診断が出る
service.resolveModuleName("/p/entry.ts", "react");
// { resolvedFileName: "", isExternal: true }    ← 対象外。診断は出ない
```

`isExternal` を分けているのは、**存在しないファイル**と**ここの仕事では
ないもの**が違うからです。bare specifier を失敗として報告すると、元から
存在するはずのないファイルを探させることになります。package 解決が
できる host は、解決結果を host が読めるパスとして渡してください。

解決の候補順は `src/parser/module_resolver.mbt` の `Types` モードと同じ
です。`.d.ts` が実装より優先されます (宣言を持っているのはそちら)。
`./util.js` は `./util.ts` を先に探します — ESM の TypeScript ソースでは
`import "./util.js"` は `util.ts` を指すので、書かれた拡張子から先に
探すと emit 済みの成果物を型チェックしてしまいます。

## 既存の `checkModuleGraph` は変わりません

呼び出し側が解決済みのグラフを渡す元の ABI はそのままです。repo の外に
consumer がいるので形を変えていません。中身は host 経路と同じ
`collect_parsed_graph_issues` を通るようになりました。

新しく書くなら `createLanguageService` の方です。`checkModuleGraph` は
**型チェックの前に呼び出し側が解決を済ませておく**必要があり、それが
一番面倒な部分です。

## CLI も Node で動きます

このライブラリ API とは別に、`mtsc` CLI 自体も `js` backend でビルドでき、
Node がそのまま実行できます。

```sh
just build-cli-js     # moon build --target js --release
node _build/js/release/build/cmd/mtsc/mtsc.js entry.ts --bundle --noEmit
just verify-cli-node  # native バイナリとの差分 (16 cases + --watch 往復)
```

`--watch` を含めて動きます。詳細と、実際に動かして初めて出た 2 つのバグ
(`@env.args()` のバックエンド間の形の違い、ESM で `require` が無いこと)
は CLAUDE.md の `src/cmd/mtsc` の項に記録してあります。

**どちらを使うかは用途で分かれます。** バンドラのプラグインや
エディタ統合のように「既にソースを持っていて、診断を構造化データで
受け取りたい」場合はこのライブラリ API です。CLI はプロセス境界越しに
テキストを返すので、その用途には向きません。

## テストの構成

| harness | 何を見るか |
| --- | --- |
| `moon test --target native src/mtsc` | サービス本体 35 cases。`MtscMemoryHost` 経由で、JS から呼ばれるのと同じ generic コード |
| `just verify-language-service` | Node でしか見えない部分 22 cases: `extern "js"` の host 呼び出し、値の受け渡し、実ファイルシステム、`ts.LanguageServiceHost` 形の host、facade |
| `just verify-language-service-types` | 同梱 `.d.ts` を `tsc --strict` で |

`verify-language-service` は mutation で検出力を確認してあります:
`.js` → `.ts` の読み替えを外す / parse error を捨てる /
`getScriptSnapshot` fallback を消す、のいずれでも落ちます。

診断を主張する case には必ず**正しい方の隣**を並べてあります。「壊れた
プログラムを報告する」と「正しいプログラムを報告しない」は別の主張で、
後者だけが「何にでも診断を出すサービス」を捕まえます。
