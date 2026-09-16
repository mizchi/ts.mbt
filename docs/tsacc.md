# `mtsc conformance`: checker conformance accuracy の計測

`mtsc conformance` は contributor 用の measurement CLI です。pinned TypeScript conformance
corpus を走査し、checker の recall と false positive 数を素早く集計します。アプリケーション
利用者向けの bridge generator ではありません。

最新の互換性スナップショットは [mtsc guide](./mtsc.md) に記載しています。数値は
corpus 更新や checker 実装で変わるため、変更時には以下の command で再計測します。

```sh
moon run src/cmd/mtsc -- conformance
moon run src/cmd/mtsc -- conformance --list-misses
moon run src/cmd/mtsc -- conformance --list-misses controlFlow
```

前提として `typescript/` corpus と baseline が checkout 済みである必要があります。
CI gate や詳細な TS7 baseline との照合には、より完全な次の command を使います。

```sh
just verify-checker-soundness                              # ゲート（FP 0 / PFLEGAL 0 / MISS in scope の予算）
bash scripts/checker_conformance_oracle.sh --miss-list miss.txt   # 残り MISS のパス一覧
node scripts/checker_miss_rank.mjs miss.txt                # tsc のエラーコードで順位付け
```

未対応機能の一覧・優先順位・スコープ外の判断は
[checker triage](./checker-triage.md) と
[`src/checker/UNSUPPORTED.md`](../src/checker/UNSUPPORTED.md) に記録しています。
`checker-priority.md` は TS6 オラクル時代の文書で、結論は棄却済みです。
