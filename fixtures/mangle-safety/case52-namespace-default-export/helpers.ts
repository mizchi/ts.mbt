// A module that declares a TOP-LEVEL binding named `Type`, colliding
// with the namespace object the barrel below builds. This is the whole
// setup: without a second `Type` in the bundle the linker never has to
// rename, and the bug cannot appear.
export const Type = (input: string): string => "helper-type:" + input;
export const helperLabel = "helpers";
