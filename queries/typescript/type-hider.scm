; type-hider hides TypeScript-only syntax so the buffer reads like plain
; JavaScript. The types are only concealed, never removed.
;
; `@type`       is concealed inline (annotations, type params / arguments).
; `@type.block` is a whole declaration; the plugin folds it away when it spans
;               full lines, otherwise it conceals it inline.

(type_annotation) @type
(type_parameters) @type
(type_arguments) @type

(interface_declaration) @type.block
(type_alias_declaration) @type.block
