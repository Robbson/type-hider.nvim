// Enums (runtime constructs, hidden like other type declarations)
enum Color {
  Red,
  Green,
  Blue,
}

const enum Direction {
  Up,
  Down,
}

// Ambient / declare declarations (erased, no runtime output)
declare const VERSION: string;

declare function parse(input: string): number;

declare global {
  interface Window {
    __app: string;
  }
}

// Type-only imports and exports
import type { Foo } from "./foo";
import { type Bar, baz } from "./bar";
export type { Qux } from "./qux";
export { type X, y } from "./mod";

// Interfaces and type aliases
interface Shape extends Base, Serializable {
  readonly id: number;
  label?: string;
  area?(): number;
}

type Id = number | string;
type Cb<T extends object = {}> = (value: T) => void;
type Tuple = [first: string, second?: number];
type Tpl = `prefix-${string}`;
type Keys = keyof Shape;
type Indexed = Shape["id"];

// Classes with type-only members and modifiers
class Box<T> extends Base<T> implements Shape, Serializable {
  public readonly value: T;
  private static count: number = 0;
  protected optional?: string;
  declare cache: Map<string, T>;
  [key: string]: unknown;

  constructor(public age: number, readonly name: string) {}

  override run(): void {}
  get size(): number {
    return 1;
  }
}

abstract class Worker {
  abstract handle(): void;
  abstract priority: number;
}

// Overloads (signatures have no runtime output)
function overloaded(a: string): number;
function overloaded(a: number): string;
function overloaded(a: string | number): string | number {
  return a;
}

function isShape(x: unknown): x is Shape {
  return true;
}

function assertShape(x: unknown): asserts x is Shape {}

function withOptional(a?: number, b: string = "x"): void {
  console.log(a, b);
}

// Casts, assertions and definite assignment
const generic = <T extends object>(x: T): T => x;
const asserted = value as unknown as Foo;
const sat = value satisfies Foo;
const bang = maybe!;
let definite!: string;
const arr = [1, "two"] as const;

console.log(
  Color.Red,
  Direction.Up,
  VERSION,
  parse("1"),
  baz,
  y,
  generic,
  asserted,
  sat,
  bang,
  definite,
  arr,
  overloaded(1),
  withOptional(),
  new Box(1, "a"),
  isShape(1),
  assertShape(1)
);
