# `tsacc`: checker conformance accuracy の計測

`tsacc` は contributor 用の measurement CLI です。pinned TypeScript conformance
corpus を走査し、checker の recall と false positive 数を素早く集計します。アプリケーション
利用者向けの bridge generator ではありません。

最新の互換性スナップショットは [mtsc guide](./mtsc.md) に記載しています。数値は
corpus 更新や checker 実装で変わるため、変更時には以下の command で再計測します。

```sh
moon run src/cmd/tsacc
moon run src/cmd/tsacc --list-misses
moon run src/cmd/tsacc --list-misses controlFlow
```

前提として `typescript/` corpus と baseline が checkout 済みである必要があります。
CI gate や詳細な TS7 baseline との照合には、より完全な次の command を使います。

```sh
just checker-conformance-oracle --max-fp 0 --max-legal-parsefail 1
```

未対応機能の優先順位と false-positive を避ける制約は
[checker priority](./checker-priority.md) に記録しています。
