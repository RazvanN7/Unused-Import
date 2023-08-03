# Unused import tool for D

This tool identifies unused *top-level* imports.
It uses dmd as a library, therefore it performs full semantic analysis before checking whether an import used or not.
As such, it is currently very limited:

- it only identifies unused top-level imports.
- it does not work for selective or renamed imports.
- aliases are eagerly substituted so we cannot know if `imported_module_a.var` is actually a direct use of `var` or whether alias `imported_module_b.alias_to_var` was used.
- enums are eagerly substituted with their correspoding integer value, so you cannot know whether `3` was actually `imported_module.Enum_decl.Three` or the literal `3`.

To use the tool:

```sh
chmoad a+x unused_import.d
./unused_import.d
```
