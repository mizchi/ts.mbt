export type Unit = undefined;
export type Bool = boolean;
export type Int = number;
export type Double = number;
export type String = string;
export type Bytes = Uint8Array;
export type Result<T, E> =
  | { $tag: 1; _0: T }
  | { $tag: 0; _0: E };

export type Wrapped<T> = { value: T };

export type WrappedResult<T, E> = Wrapped<Result<T, E>>;

export interface Payload<T> {
  value: T;
  ok: Bool;
}

export type PayloadResult<T, E> = Payload<Result<T, E>>;

export interface BasePayload<T> {
  value: T;
}

export interface TaggedPayload {
  kind: String;
}

export interface RichPayload<T> extends BasePayload<T>, TaggedPayload {
  ok: Bool;
}

export type RichPayloadResult<T, E> = RichPayload<Result<T, E>>;

export interface TextValue {
  value: String;
}

export interface NumericValue {
  value: Int;
}

export interface ConflictingPayload extends TextValue, NumericValue {
  ok: Bool;
}

export type ConflictingPayloadResult = ConflictingPayload;

export interface KindLabel {
  kind: String;
}

export interface KindLabelDuplicate {
  kind: String;
}

export interface SharedTaggedPayload extends KindLabel, KindLabelDuplicate {
  ok: Bool;
}

export type SharedTaggedPayloadResult = SharedTaggedPayload;

export interface ReadonlyCount {
  readonly count: Int;
}

export interface ReadonlyCountDuplicate {
  readonly count: Int;
}

export interface SharedReadonlyPayload extends ReadonlyCount, ReadonlyCountDuplicate {
  ok: Bool;
}

export type SharedReadonlyPayloadResult = SharedReadonlyPayload;

export interface MutableCount {
  count: Int;
}

export interface ConflictingReadonlyPayload extends ReadonlyCount, MutableCount {
  ok: Bool;
}

export type ConflictingReadonlyPayloadResult = ConflictingReadonlyPayload;

export interface MethodFormatter {
  format(value: Int): String;
}

export interface MethodFormatterDuplicate {
  format(value: Int): String;
}

export interface SharedMethodPayload extends MethodFormatter, MethodFormatterDuplicate {
  ok: Bool;
}

export type SharedMethodPayloadResult = SharedMethodPayload;

export interface StringFormatter {
  (value: String): String;
}

export interface NumberFormatter {
  (value: Int): String;
}

export interface SharedFormatterPayload extends StringFormatter, NumberFormatter {
  ok: Bool;
}

export type SharedFormatterPayloadResult = SharedFormatterPayload;

export interface OptionalName {
  name?: String;
}

export interface OptionalNameDuplicate {
  name?: String;
}

export interface SharedOptionalPayload extends OptionalName, OptionalNameDuplicate {
  ok: Bool;
}

export type SharedOptionalPayloadResult = SharedOptionalPayload;

export interface RequiredName {
  name: String;
}

export interface ConflictingOptionalPayload extends OptionalName, RequiredName {
  ok: Bool;
}

export type ConflictingOptionalPayloadResult = ConflictingOptionalPayload;
