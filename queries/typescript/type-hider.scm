; type-hider hides TypeScript-only syntax so the buffer reads like plain
; JavaScript. The types are only concealed, never removed.
;
; `@type`       is concealed inline (annotations, type params / arguments).
; `@type.block` is a whole declaration; the plugin folds it away when it spans
;               full lines, otherwise it conceals it inline.
; `@type.cast`  is an `as` / `satisfies` cast; the plugin conceals from the
;               keyword to the end (the cast type may be an anonymous node).

(type_annotation) @type
(type_parameters) @type
(type_arguments) @type

(interface_declaration) @type.block
(type_alias_declaration) @type.block

(as_expression) @type.cast
(satisfies_expression) @type.cast
