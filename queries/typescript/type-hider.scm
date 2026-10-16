; type-hider hides TypeScript-only syntax so the buffer reads like plain
; JavaScript. The types are only concealed, never removed.
;
; Captures:
;   @type           inline type syntax, concealed in place
;   @type.block     a whole declaration, folded away (incl. one trailing blank)
;   @type.cast      `as` / `satisfies` cast, concealed from the keyword
;   @type.specifier type-only `import`/`export` specifier, concealed with comma

; ---------------------------------------------------------------------------
; Whole declarations that emit no JavaScript
; ---------------------------------------------------------------------------
(interface_declaration) @type.block
(type_alias_declaration) @type.block
(enum_declaration) @type.block
(ambient_declaration) @type.block
(function_signature) @type.block
(abstract_method_signature) @type.block
(index_signature) @type.block

; `abstract` / `declare` class fields exist only in the type system
((public_field_definition "abstract") @type.block)
((public_field_definition "declare") @type.block)

; Exported type-only declarations, so the `export` keyword is folded too
((export_statement (interface_declaration)) @type.block)
((export_statement (type_alias_declaration)) @type.block)
((export_statement (enum_declaration)) @type.block)
((export_statement (ambient_declaration)) @type.block)
((export_statement (function_signature)) @type.block)

; Type-only import / export statements
((import_statement "type") @type.block)
((export_statement "type") @type.block)

; ---------------------------------------------------------------------------
; Inline type syntax
; ---------------------------------------------------------------------------
(type_annotation) @type
(type_predicate_annotation) @type
(asserts_annotation) @type
(type_parameters) @type
(type_arguments) @type
(implements_clause) @type.clause

; ---------------------------------------------------------------------------
; Type-only modifiers and markers (concealed with following whitespace)
; ---------------------------------------------------------------------------
(accessibility_modifier) @type.modifier
(override_modifier) @type.modifier
(abstract_class_declaration "abstract" @type.modifier)
(public_field_definition "readonly" @type.modifier)
(required_parameter "readonly" @type.modifier)
(public_field_definition "?" @type.modifier)
(optional_parameter "?" @type.modifier)
(method_signature "?" @type.modifier)
(property_signature "?" @type.modifier)
(variable_declarator "!" @type.modifier)
(non_null_expression "!" @type.modifier)

; ---------------------------------------------------------------------------
; Casts
; ---------------------------------------------------------------------------
(as_expression) @type.cast
(satisfies_expression) @type.cast

; ---------------------------------------------------------------------------
; Type-only import / export specifiers (`import { type A, b }`)
; ---------------------------------------------------------------------------
((import_specifier "type") @type.specifier)
((export_specifier "type") @type.specifier)
