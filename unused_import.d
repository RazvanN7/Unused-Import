#!/usr/bin/env dub
/+dub.sdl:
dependency "dmd" version="~>2.110.0-beta.1"
+/

import dmd.astcodegen;
import dmd.dimport;
import dmd.dmodule;
import dmd.expression;
import dmd.frontend;
import dmd.mtype;
import dmd.visitor;

import core.stdc.stdio;
import std.stdio;
import std.range;

auto distinct(Range)(Range r) if (isInputRange!Range)
{
    import std.algorithm.iteration : filter;
    bool[ElementType!Range] justSeen;
    return r.filter!(
      (k) {
         if (k in justSeen) return false;
         return justSeen[k] = true;
      }
   );
}

struct ImportInfo
{
    string importedModule;
    uint line;
}

// gather all top-level imports
extern(C++) class TopLevelImportsVisitor : Visitor
{
    alias visit = typeof(super).visit;

    ImportInfo[] imports;

    override void visit(Module m)
    {
        foreach(member; *(m.members))
        {
            if (auto imp = member.isImport())
            {
                // if selective or renamed import continue
                if (imp.aliasId || imp.names.length)
                    continue;

                string s;
                foreach (const packageId; imp.packages)
                    s ~= packageId.toString() ~ ".";

                s ~= imp.id.toString();
                imports ~= ImportInfo(s, imp.loc.linnum);
            }
        }
    }
}

// Traverse the tree and see if the used symbols come from this module or not
extern(C++) class UnusedImportVisitor : SemanticTimeTransitiveVisitor
{
    alias visit = SemanticTimeTransitiveVisitor.visit;

    override void visit(CallExp ce)
    {
        if (!ce.f)
        {
            super.visit(ce);
            return;
        }

        auto str = charsToString(ce.f.toPrettyChars());
        checkUsed(str);
        super.visit(ce);
    }

    override void visit(TypeClass tc)
    {
        auto str = charsToString(tc.sym.toPrettyChars());
        checkUsed(str);
    }

    override void visit(TypeStruct ts)
    {
        auto str = charsToString(ts.sym.toPrettyChars());
        checkUsed(str);
    }

    override void visit(TypeEnum te)
    {
        auto str = charsToString(te.sym.toPrettyChars());
        checkUsed(str);
    }

    override void visit(SymbolExp ve)
    {
        auto str = charsToString(ve.var.toPrettyChars());
        checkUsed(str);
    }

extern(D):

    string[][ImportInfo] usedImports;
    string moduleName;

    this(string[][ImportInfo] usedImports, string moduleName)
    {
        this.usedImports = usedImports;
        this.moduleName = moduleName;
    }

    const(char)[] charsToString(const(char)* chars)
    {
        import core.stdc.string;
        return chars[0 .. strlen(chars)];
    }

    void checkUsed(const(char)[] str)
    {
        import std.conv : to;
        import std.algorithm.searching : startsWith, skipOver, findSplit;

        // declarations in this module do not
        // use any imports
        if (str.startsWith(moduleName))
            return;

        foreach(key; usedImports.keys)
        {
            auto imp = key.importedModule ~ ".";
            if (str.startsWith(imp))
            {
                string symbolFQN = to!string(str);
                skipOver(symbolFQN, imp);
                auto r = symbolFQN.findSplit(".");
                usedImports[key] ~= r[0];
                break;
            }
        }
    }
}

void addImportPaths()
{
    addImport("/home/razvann/Dlang/dmd/druntime/import");
    addImport("/home/razvann/Dlang/phobos");
    addStringImport("/home/razvann/Dlang/dmd/compiler/generated/host_dmd-2.095.0/dmd2/src/dmd/dmd/res");
    addStringImport("/home/razvann/Dlang/dmd");
    addImport("/home/razvann/Dlang/dmd/compiler/src");
}

void main()
{
    initDMD();
    addImportPaths();

    enum mod = "mtype";
    auto m = parseModule("/home/razvann/Dlang/dmd/compiler/src/dmd/" ~ mod ~ ".d", null);

    scope getImportsVisitor = new TopLevelImportsVisitor();
    m[0].accept(getImportsVisitor);
    auto imps = getImportsVisitor.imports;

    string[][ImportInfo] importHash;
    foreach(imp; imps)
        importHash[imp] = [];

    m[0].fullSemantic();

    scope uiv = new UnusedImportVisitor(importHash, "dmd." ~ mod);
    m[0].accept(uiv);

    auto usedImports = uiv.usedImports;
    foreach(key; usedImports.keys())
    {
        if (!usedImports[key])
            writefln("\nWarning(%u): unused import: %s\n", key.line, key.importedModule);
        else
            writefln("Import: %s is used for the following members: %s", key.importedModule, usedImports[key].distinct());
    }
}
