// @strict: true

// `${number}` admits a string when `+s` is finite and `s` is not empty
// (`templateLiteralTypesPatterns` pins `"0x1"`, `"1e21"`, ... as accepted and
// `""` as rejected). That makes whitespace a number: `+" "` is `0`, so a
// string of spaces, a newline, a no-break space and a padded numeral all
// satisfy `${number}`. Nothing upstream pins these; whether they are meant
// to is the question.
declare function numbers(x: `${number}`): void;

numbers(" ");       // accepted
numbers("   ");     // accepted
numbers("\n");      // accepted
numbers(" ");  // accepted
numbers(" 1");      // accepted
numbers("1 ");      // accepted
numbers("");        // TS2345
numbers("1_000");   // TS2345
