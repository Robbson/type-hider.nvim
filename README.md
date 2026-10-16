# type-hider

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/ellisonleao/nvim-plugin-template/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

_type-hider_ is a Neovim plugin that hides all type declarations in a TypeScript source file (.ts/.tsx) so the resulting code looks like plain JavaScript without loosing any type-safety benefits. Because as the name suggests, types are only hidden from the user, not removed, so they are still working as expected.

This way code can be a lot easier to read, especially in libraries and frameworks where exhaustive type declarations are mandatory.

Unlike transpilers and type stripping algorithms, this is not obout the best possible processing & optimizations to transform the code to a specfic target platform. The resulting code should look close to the original one, no empty lines removed, no comments removed no optimizations. Because types are just hidden, you can easily switch then on again, as required.

## Using it

Types are hidden with Neovim's conceal feature. The hidden text is not removed
from the buffer, so everything keeps working: LSP, diagnostics, navigation and
so on. Inline types are concealed with an empty placeholder; a type declaration
that occupies whole lines (an `interface` or a `type` block) has those lines
folded away instead of being left empty, together with one trailing blank line if
present so folded blocks do not pile up empty separator lines. Because the
placeholder is empty, you have to run a command to show the types again.

For `.ts` and `.tsx` files the types are hidden automatically once the buffer is
loaded. These commands switch the hiding on and off:

```vim
:TypeHiderEnable   " hide the types
:TypeHiderDisable  " show the types again
:TypeHiderToggle   " toggle
```

`setup` is optional. The defaults are:

```lua
require("type-hider").setup({
  -- Filetypes the type hider applies to.
  formats = { "typescript", "typescriptreact" },
  -- Window options used while the types are hidden. 'concealcursor' keeps the
  -- types hidden while the cursor is on the line and in visual/insert mode.
  conceallevel = 2,
  concealcursor = "nvic",
  -- Hide types automatically for the filetypes above.
  auto_enable = true,
})
```

The rules live in a dedicated `type-hider` Treesitter query
(`queries/typescript/type-hider.scm`), not in the `highlights` query, so the
type hider never interferes with syntax highlighting. See
[doc/architecture.md](doc/architecture.md) for how the pieces fit together,
with diagrams of the flow.

## What gets hidden

Inline type syntax is concealed in place (with any surrounding whitespace):

- type annotations `: T`
- type parameters `function f<T>()` and type arguments `foo<T>()`
- `implements A, B` clauses
- `as` / `satisfies` casts
- return type predicates `: x is T` and `: asserts x is T`
- type-only modifiers and markers: `public` / `private` / `protected`,
  `readonly`, `override`, `abstract` (on classes), optional `?`, definite `!`
  and non-null `!`
- type-only `import` / `export` specifiers (`import { type A, b }`)

Whole declarations that emit no JavaScript are folded away, including one
trailing blank line:

- `interface` and `type` declarations
- `enum` and `const enum`
- `declare` / ambient declarations
- function overload signatures
- `abstract` methods and fields, index signatures
- `import type ...` and `export type ...` statements

Kept visible (they emit runtime JavaScript or are not type-only):

- classes and their value members, functions with bodies, expressions
- `namespace` blocks (they compile to runtime IIFEs)
- decorators
- constructor parameter properties keep working, but their implicit field
  assignment is not shown
- `export =` / `import ... = require(...)`

The last points are deliberate; the query is a normal `.scm` file, so it can be
extended or trimmed to taste.


## Features and structure

- 100% Lua
- an [architecture document](doc/architecture.md) with diagrams of the flow
- Github actions for:
  - running tests using [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) and [busted](https://olivinelabs.com/busted/)
  - check for formatting errors (Stylua)
  - vimdocs autogeneration from README.md file
  - luarocks release (LUAROCKS_API_KEY secret configuration required)

