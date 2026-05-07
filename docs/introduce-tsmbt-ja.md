# typescript.mbt を書いている

## tl;dr

- TypeScript の `.d.ts` から MoonBit 側の bridge package を生成する `ts2mbt` を書いてる
- ジェネリクス保持・heterogeneous union → enum 化・class + namespace declaration merging まで対応
- drizzle-orm のスキーマを Node 24 の `node:sqlite` に流して INSERT + SELECT が走るところまで動く
- TS の `infer` + 条件型 + mapped 型の深い推論は再現できない。これは設計上の限界
- 実用ターゲットは vite-plugin-moonbit。npm の型を MoonBit から消費するため
- 現在 `mizchi/ts@0.3.0` (mooncakes)。

## なぜ書いてるか

vite-plugin-moonbit を「ふつうに使えるもの」にしたい。MoonBit の JS バックエンドで Hono とか書きたいし、書いてる。

ただ npm の型を MoonBit から呼ぶたびに `JSValue` (任意の JS 値) で受けて毎回 `unsafeCast` するのが地味にだるい。`hono.get("/", handler)` の `handler` の引数が `JSValue` だと、毎回 `c.text("...")` の前に `(unsafeCast(c) : Context).text("...")` みたいなのが要る。これは流石にしんどい。

`ts2mbt` は npm の `.d.ts` を読んで、ジェネリクスを保持した MoonBit の bridge package を吐く。consumer 側からは `Hono[E, S, BasePath]` とか `Context[E, P, I]` とか普通に書ける。

## 動かしてみる

drizzle で見せるのが一番分かりやすいので drizzle で。

```bash
$ moon install mizchi/ts/cmd/ts2mbt
$ ts2mbt scaffold node_modules/drizzle-orm/index.d.ts drizzle-orm dist/
Wrote MoonBit bridge package to dist
Wrote scaffold diagnostics to dist/SCAFFOLD_DIAGNOSTICS.md
$ wc -l dist/*.mbt
     613 dist/types.mbt
     513 dist/converters.mbt
     646 dist/externs.mbt
     344 dist/guards.mbt
     195 dist/bridge.mbt
    2311 total
```

drizzle 全体 (`export * from` で 14 sub-module) で 2311 行。`types.mbt` を覗くとこんな感じ。

```moonbit
pub(all) struct Table[T] {}
pub(all) struct Column[T, TRuntimeConfig, TTypeConfig] {}
pub(all) struct Subquery[TAlias, TSelectedFields] {}
pub(all) struct ColumnBaseConfig[TDataType, TColumnType] { ... }
pub type SQL[T]

pub(all) struct DrizzleConfig[TSchema] {
  logger : Auto_BoolValue_or_LoggerValue?  // boolean | Logger を自動 enum 化
  ...
}
```

`Auto_BoolValue_or_LoggerValue` は `boolean | Logger` (heterogeneous union) を runtime discriminator (`typeof` + `instanceof`) で振り分けて enum にしたもの。MoonBit 側からは普通の enum として `BoolValue(true)` / `LoggerValue(my_logger)` で書ける。

`SQL` クラスのメソッドはこんな感じで生えてる。

```moonbit
pub fn[T] SQL::append(self : SQL[T], query : SQL[JSValue]) -> SQL[JSValue] { ... }
pub fn[T] SQL::to_query(self : SQL[T], config : BuildQueryConfig) -> QueryWithTypings { ... }
pub fn[T] SQL::as_(self : SQL[T], alias_ : String) -> SQL_Aliased { ... }
```

`as` / `alias` は MoonBit 側でぶつかるので `as_` / `alias_` に逃がしてる。`T` はちゃんと保持してる。

## 実 DB に流す

drizzle の schema を組んで Node 24 の組込 `node:sqlite` で SELECT させる smoke test を書いた。

```moonbit
fn main {
  // drizzle の runtime API でスキーマ構築
  let id_col = integer_primary_key_js(sqlite_integer_js("id"))
  let name_col = text_not_null_js(sqlite_text_js("name"))
  let columns = make_columns_object_js(id_col, name_col, ...)
  let users = sqlite_table_js("users", columns)
  let typed_users : @sut.Table[@sut.JSValue] = @sut.unsafeCast(users)

  // node:sqlite で INSERT + SELECT
  let db = open_db_js("create table users (id integer primary key, name text not null)")
  let insert = build_insert_sql_js(users, 1, "alice")
  db_run_js(db, js_query_sql(insert), js_query_params(insert))

  let rows = db_all_js(db, ...)
  if row_str(rows, 0, "name") != "alice" {
    abort("expected alice")
  }
  smoke_print_ok()
}
```

`sqliteTable` / `integer().primaryKey()` / `text().notNull()` といった drizzle の runtime API を `extern "js" fn` で呼んで、組み立てた `users` を `Table[JSValue]` にキャストして MoonBit 側に持ち上げる。SELECT は drizzle の `QueryBuilder` で `select().from(t).toSQL()` させて、生成された SQL string + params を `db.prepare(...).all(...)` に流す。

で、動いた。`Total tests: 1, passed: 1, failed: 0.` で drizzle@0.45.2 + Node 24 の実動作。`examples/typescript-to-moonbit/drizzle/` に置いてあるので `just verify-examples` で回る。

## 何ができないか

正直に書く。

### 1. TS の `typeof users.$inferSelect` の深い推論は再現できない

`typeof Foo` そのものは type query として AST に残すようにした。なので `InstanceType<typeof Foo>` / `ConstructorParameters<typeof Foo>` みたいな「クラス値から instance / constructor args を取る」浅い utility は bridge 側で下げられる。

ただし drizzle の `typeof users.$inferSelect` は別物。`infer` + 条件型 + mapped 型 + indexed access の連鎖で、TS 型システム固有の計算結果を取り出している。MoonBit の型システムでは対応する機構がない。

なので MoonBit 側で `users` は `Table[JSValue]` として持つしかなくて、column の型は失われる。runtime API は完全に動くから SQL の生成と実行は問題なくできる。けど「`row.id` が `Int` で `row.name` が `String`」みたいな結果型の inference は無理。

これは設計上の限界。MoonBit 側に TS の type-level computation を持ち込むつもりは正直ないし、たぶん割に合わない。

### 2. クラスコンストラクタの `new` 呼び出し

`extern "js" fn x() = "Foo"` だと `function x() { return Foo() }` になって `new` が付かない。drizzle の `new QueryBuilder()` とか `new DatabaseSync(":memory:")` とかは別の `.mjs` helper を挟んで wrap する必要がある。

これは MoonBit 側のサポート待ち。今は `package.json#imports` map に `#myhelper: ./helper.mjs` を書いて逃がす。

### 3. 再帰型の深い推論

```ts
interface BuildRelationalQueryResult {
  selection: BuildRelationalQueryResult['selection'];  // 自己参照
}
```

みたいな自己参照は cycle break で `Array[JSValue]` に倒している。安全側だけど、本来推論できるはずの場所で型を失っている。

## どこまで動くか

実装してる sub-package (現在 0.3.0)。

- `src/parser` — TS / JS パーサー + module resolver。npm `exports`、`typesVersions`、`node:*`、`@types/*` ぜんぶ
- `src/checker` — declaration-level の型システム。`is_assignable_to` / `extends_decision` / `infer` pattern matching / distributive conditional / `Pick` / `Omit` / `Record` / `Exclude` / `Extract` / `NonNullable` / `Awaited` / `ReturnType` / `Parameters`
- `src/bridge` — bridge code generation。class + namespace declaration merging、heterogeneous union → enum lowering、cross-file generic arity propagation、self-referential indexed access の cycle break、単純 typealias passthrough、`typeof Class` 由来の `InstanceType` / `ConstructorParameters` など

0.3.0 時点の確認は native tests 1119 / 1119、examples 11 / 11、24-package real-world corpus byte-identical。`pub type Foo = Double` のような単純 alias と alias-position の `NonNullable` / `Awaited` / `ReturnType` / `Parameters`、それから `typeof Class` の constructor utility まで入っている。

CLI 触り方:

```bash
# 単発の .d.ts から bridge 生成
ts2mbt scaffold node_modules/drizzle-orm/index.d.ts drizzle-orm dist/

# package.json の deps から全部
ts2mbt generate --package-json package.json --out internal/generated

# 逆方向: MoonBit pkg.generated.mbti から .d.ts
mbt2ts decl src/foo/pkg.generated.mbti dist/foo.d.ts
```

real-world corpus (現在 24 package) を `just verify-realworld-typescript` で回している。

`clsx` / `chalk` / `dotenv` / `hono` / `zod` / `date-fns` / `magic-string` / `source-map` / `valibot` / `immer` / `execa` / `preact` / `vitest` / `playwright` / `react-router` / `jose` / `express` / `glob` / `node:sqlite` / `node:fs` / `node:path` / `node:crypto` / `node:os` / `node:url` / `node:querystring` / `node:assert` / `node:util` / `node:buffer`。

各 package の JSValue surface を「unknown / overload / conditional・mapped / callback / tuple・array / namespace」のバケットで budget 化して、回帰したら CI で気付くようにしてる。

## これから

- zod / valibot の `output<T>` とか mapped 型の partial evaluation。今は generic 引数を `JSValue` で widening している
- template literal types (`` `bg${Capitalize<T>}` ``) の expansion。alias 位置は対応してるけど param / field 位置は `String` に倒している
- `typeof ns.Foo` や `typeof import("./mod").Foo` のような qualified/import type query の bridge 解決。AST には残すが、constructor utility の解決対象はまずローカル class / import binding の浅いケースに絞っている
- JSX / component layer。React / Preact の bridge は generic 構造としては動くが component 化はしてない

drizzle 例は `just verify-examples` の rail に乗せたので回帰しなくなった。これを足場にして、もう少し real-world でガサつくところを潰したい。自分の用途的には vite-plugin-moonbit + Hono / drizzle / zod が普通に書けるラインに乗せきるのが当面のゴールだと思っている。

## 触り方

```bash
ghq get github.com/mizchi/ts.mbt
cd $(ghq path mizchi/ts.mbt)
moon test --target native
just verify-examples
```

mooncakes 経由なら:

```json
// moon.mod.json
{
  "deps": {
    "mizchi/ts": "0.3.0"
  }
}
```

おわり。
