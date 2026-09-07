#!/usr/bin/env python3
"""srpcheck - static sanity checks for the ScalpRobotPro MQL5 tree.

This is NOT a compiler and does not claim to be one. It catches the specific
classes of mistake that hand-editing a 235-file MQL5 tree actually produces,
and that would otherwise only surface as a MetaEditor error:

  1. unbalanced braces / parens / brackets per file (outside strings+comments)
  2. every #include resolves to a real file
  3. every class method DECLARED is also DEFINED, and vice versa
  4. every struct field READ somewhere is DECLARED somewhere
  5. every CConfigKeys:: constant used is both declared and defined
  6. the full input plumbing chain for a named EA input:
        input Inp<X>  ->  snapshot.<field>  ->  SInputSnapshot.<field>
        ->  config.Set*(CConfigKeys::<KEY>) ->  SRuntimeConfig.<field>
        ->  config.Get*(CConfigKeys::<KEY>) ->  at least one consumer
  7. include-guard uniqueness
  8. every m_member used resolves in its own class (or a base class)
  9. every .Method() call names a callable that exists somewhere in the tree
 10. every unqualified Capitalised call resolves, MQL5 built-ins allowlisted
     by deriving them from an untouched --baseline tree

Usage:  python3 srpcheck.py <MQL5 root> [--baseline=<pristine MQL5 root>]
                                        [--chain=FIELD=KEY,FIELD=KEY...]
Exit code 0 = all checks pass.
"""
import os
import re
import sys
from collections import defaultdict

# --------------------------------------------------------------------------
# lexing helpers: strip comments and string literals before counting anything
# --------------------------------------------------------------------------
_STR = re.compile(r'"(?:[^"\\\n]|\\.)*"' r"|'(?:[^'\\\n]|\\.)*'")
_BLOCK = re.compile(r"/\*.*?\*/", re.S)
_LINE = re.compile(r"//[^\n]*")


def strip_code(text):
    """Replace strings/comments with spaces, preserving newline positions."""
    def blank(m):
        return re.sub(r"[^\n]", " ", m.group(0))
    text = _BLOCK.sub(blank, text)
    text = _LINE.sub(blank, text)
    text = _STR.sub(blank, text)
    return text


def read(path):
    for enc in ("utf-8", "utf-16", "latin-1"):
        try:
            with open(path, encoding=enc) as fh:
                return fh.read()
        except (UnicodeDecodeError, UnicodeError):
            continue
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def sources(root):
    out = []
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if name.lower().endswith((".mqh", ".mq5")):
                out.append(os.path.join(dirpath, name))
    return sorted(out)


# --------------------------------------------------------------------------
FAILURES = []
CHECKS = [0]


def check(ok, label, detail=""):
    CHECKS[0] += 1
    if not ok:
        FAILURES.append(f"{label}" + (f"  --  {detail}" if detail else ""))
    return ok


# --------------------------------------------------------------------------
# 1. bracket balance
# --------------------------------------------------------------------------
def check_balance(files, root):
    bad = []
    for f in files:
        code = strip_code(read(f))
        for open_c, close_c, name in (("{", "}", "brace"),
                                      ("(", ")", "paren"),
                                      ("[", "]", "bracket")):
            d = code.count(open_c) - code.count(close_c)
            if d != 0:
                bad.append(f"{os.path.relpath(f, root)}: {name} delta {d:+d}")
    check(not bad, "1. bracket balance", "; ".join(bad[:6]))
    return not bad


# --------------------------------------------------------------------------
# 2. includes resolve
# --------------------------------------------------------------------------
INC = re.compile(r'^\s*#include\s+([<"])([^">]+)[>"]', re.M)


def check_includes(files, root):
    inc_root = os.path.join(root, "Include")
    missing = []
    for f in files:
        for _bracket, spec in INC.findall(read(f)):
            cands = [os.path.join(inc_root, spec),
                     os.path.join(os.path.dirname(f), spec)]
            if not any(os.path.isfile(os.path.normpath(c)) for c in cands):
                missing.append(f"{os.path.relpath(f, root)} -> {spec}")
    check(not missing, "2. every #include resolves", "; ".join(missing[:6]))
    return not missing


# --------------------------------------------------------------------------
# 3. declared-vs-defined methods
#    A declaration inside a class body ends in ');'  (no inline body).
#    A definition is  Class::Method(  at file scope.
# --------------------------------------------------------------------------
DECL = re.compile(
    r"^\s{2,}(?:static\s+|virtual\s+)*"
    r"(?:const\s+)?[A-Za-z_][\w:<>*&\s]*?"
    r"\b([A-Z][A-Za-z0-9_]*)\s*\([^;{]*\)\s*(?:const\s*)?;\s*$", re.M)
DEFN = re.compile(r"^[\w:<>*&\s]*?\b([A-Z]\w*)::([A-Za-z_]\w*)\s*\(", re.M)


def check_methods(files, root):
    """Per-file: every Class::Method definition has a matching declaration."""
    orphan_defs = []
    for f in files:
        code = strip_code(read(f))
        classes = set(re.findall(r"^class\s+(\w+)", code, re.M))
        if not classes:
            continue
        declared = set()
        for cls in classes:
            body = re.search(r"^class\s+" + cls + r"\b.*?^  \};",
                             code, re.M | re.S)
            if body:
                for m in DECL.finditer(body.group(0)):
                    declared.add((cls, m.group(1)))
        for m in DEFN.finditer(code):
            cls, meth = m.group(1), m.group(2)
            if cls not in classes:
                continue                       # defined elsewhere, fine
            if cls == meth or meth == "~" + cls:
                continue                       # ctor / dtor
            if (cls, meth) not in declared:
                # tolerate: declaration may carry a return type we failed to
                # lex. Only report when the name appears nowhere in the body.
                if not re.search(r"\b" + re.escape(meth) + r"\s*\(",
                                 body.group(0) if body else ""):
                    orphan_defs.append(
                        f"{os.path.relpath(f, root)}: {cls}::{meth} defined "
                        "but not declared")
    check(not orphan_defs, "3. every definition has a declaration",
          "; ".join(orphan_defs[:6]))
    return not orphan_defs


# --------------------------------------------------------------------------
# 4/5. CConfigKeys constants: declared in the class, defined at file scope,
#      and every use refers to one that exists.
# --------------------------------------------------------------------------
def check_config_keys(files, root):
    keys_file = os.path.join(root, "Include", "ScalpRobotPro",
                             "Configuration", "CConfigKeys.mqh")
    code = strip_code(read(keys_file))
    declared = set(re.findall(r"^\s+static const string\s+(\w+)\s*;", code, re.M))
    defined = set(re.findall(r"^const string CConfigKeys::(\w+)\s*=", code, re.M))
    check(declared == defined, "4. CConfigKeys declared == defined",
          f"decl-only {sorted(declared - defined)[:5]} "
          f"def-only {sorted(defined - declared)[:5]}")

    used = set()
    for f in files:
        used |= set(re.findall(r"CConfigKeys::(\w+)", strip_code(read(f))))
    unknown = used - declared
    check(not unknown, "5. every CConfigKeys:: use exists",
          f"unknown {sorted(unknown)[:5]}")
    return declared, defined


# --------------------------------------------------------------------------
# 6. struct field reads resolve to a declaration
# --------------------------------------------------------------------------
def struct_fields(root, header, struct):
    code = strip_code(read(os.path.join(root, header)))
    body = re.search(r"^struct\s+" + struct + r"\b.*?^  \};", code, re.M | re.S)
    if not body:
        return set()
    return set(re.findall(r"^\s{2,}(?:const\s+)?[\w:<>*&]+\s+(\w+)\s*(?:\[[^\]]*\])?\s*;",
                          body.group(0), re.M))


def check_chain(root, files, field, key):
    """The eight-site plumbing chain for one input, end to end."""
    ea = read(os.path.join(root, "Experts", "ScalpRobotPro",
                           "ScalpRobotPro.mq5"))
    builder = read(os.path.join(root, "Include", "ScalpRobotPro",
                                "Configuration", "CConfigurationBuilder.mqh"))
    runtime = read(os.path.join(root, "Include", "ScalpRobotPro",
                                "Runtime", "CRuntimeConfig.mqh"))
    keys = read(os.path.join(root, "Include", "ScalpRobotPro",
                             "Configuration", "CConfigKeys.mqh"))
    ok = True
    ok &= check(re.search(r"snapshot\." + field + r"\s*=", ea) is not None,
                f"6.{field}.a EA assigns snapshot.{field}")
    ok &= check(re.search(r"^\s+\w+\s+" + field + r"\s*;", builder, re.M)
                is not None,
                f"6.{field}.b SInputSnapshot declares {field}")
    #  The optional (cast) is the codebase's established idiom for enum-typed
    #  inputs: SRuntimeConfig holds them as int so they round-trip through the
    #  keyed store, so the builder writes config.SetInt(KEY,(int)in.field).
    #  Without this the check failed every enum input in the project.
    ok &= check(re.search(r"CConfigKeys::" + key
                          + r"\s*,\s*(?:\(\s*[\w ]+\s*\)\s*)?in\." + field,
                          builder, re.S) is not None,
                f"6.{field}.c builder writes {key} from in.{field}")
    ok &= check(f"CConfigKeys::{key};" in keys.replace(" ", " ") or
                re.search(r"static const string\s+" + key + r"\s*;", keys)
                is not None,
                f"6.{field}.d {key} declared")
    ok &= check(re.search(r"CConfigKeys::" + key + r"\s*=", keys) is not None,
                f"6.{field}.e {key} defined")
    ok &= check(re.search(r"^\s+\w+\s+" + field + r"\s*;", runtime, re.M)
                is not None,
                f"6.{field}.f SRuntimeConfig declares {field}")
    ok &= check(re.search(r"out\." + field + r"\s*=.*?CConfigKeys::" + key,
                          runtime, re.S) is not None,
                f"6.{field}.g SRuntimeConfig reads {key} into {field}")
    ok &= check(re.search(r"\b" + field + r"\s*=", runtime) is not None,
                f"6.{field}.h SRuntimeConfig::Reset seeds a default")
    consumers = [os.path.relpath(f, root) for f in files
                 if re.search(r"m_config\." + field + r"\b|config\." + field
                              + r"\b", strip_code(read(f)))]
    ok &= check(len(consumers) > 0,
                f"6.{field}.i at least one consumer reads it",
                f"consumers={consumers}")
    return ok, consumers


# --------------------------------------------------------------------------
# 7. include-guard uniqueness
# --------------------------------------------------------------------------
def check_guards(files, root):
    seen = defaultdict(list)
    for f in files:
        if not f.lower().endswith(".mqh"):
            continue
        m = re.search(r"^#ifndef\s+(\w+)", read(f), re.M)
        if m:
            seen[m.group(1)].append(os.path.relpath(f, root))
    dupes = {k: v for k, v in seen.items() if len(v) > 1}
    check(not dupes, "7. include guards unique", f"{list(dupes.items())[:3]}")
    return not dupes


# --------------------------------------------------------------------------
# 8. every m_member USED inside a class's methods is DECLARED in that class
#    or in one of its base classes.
#
#    Scope matters here, not mere existence. 'm_digits' is declared in four
#    unrelated classes in this tree, so a tree-wide existence test passes it
#    happily while the compiler rejects it in a fifth class that has no such
#    member. That is precisely the defect this check was added for.
# --------------------------------------------------------------------------
MEMBER_DECL = re.compile(
    r"^\s*(?:static\s+)?(?:const\s+)?[A-Za-z_][\w:<>]*\s*[*&]?\s*"
    r"(m_\w+(?:\s*(?:\[[^\]]*\])?\s*,\s*[*&]?\s*m_\w+)*)"
    r"\s*(?:\[[^\]]*\])?\s*;", re.M)
MEMBER_NAME = re.compile(r"\bm_\w+")
MEMBER_USE = re.compile(r"\bm_\w+")
CLASS_HEAD = re.compile(r"^class\s+(\w+)(?:\s*:\s*public\s+(\w+))?", re.M)
#--- A DEFINITION starts in column 0. The leading (?!\s) matters: without it
#--- a wrapped argument line such as "      CRegimeEngine::RegimeToString(x),"
#--- reads as a new definition and mis-attributes the rest of the enclosing
#--- method to the wrong class.
DEFN_TOP = re.compile(r"^(?!\s)[\w:<>*&\s]*?\b([A-Z]\w*)::([A-Za-z_]\w*)\s*\(",
                      re.M)


def class_body(code, cls):
    return re.search(r"^class\s+" + cls + r"\b.*?^  \};", code, re.M | re.S)


def harvest_classes(files):
    """cls -> set(own members);  cls -> base name or None."""
    members = defaultdict(set)
    bases = {}
    for f in files:
        code = strip_code(read(f))
        for m in CLASS_HEAD.finditer(code):
            cls, base = m.group(1), m.group(2)
            bases[cls] = base
            body = class_body(code, cls)
            if body:
                for group in MEMBER_DECL.findall(body.group(0)):
                    members[cls] |= set(MEMBER_NAME.findall(group))
    return members, bases


def member_closure(cls, members, bases, _seen=None):
    if _seen is None:
        _seen = set()
    if cls in _seen or cls not in bases:
        return set()
    _seen.add(cls)
    out = set(members.get(cls, set()))
    base = bases.get(cls)
    if base:
        out |= member_closure(base, members, bases, _seen)
    return out


def check_members(files, root):
    members, bases = harvest_classes(files)
    cache = {}

    def allowed(cls):
        if cls not in cache:
            cache[cls] = member_closure(cls, members, bases)
        return cache[cls]

    bad = []
    for f in files:
        code = strip_code(read(f))
        rel = os.path.relpath(f, root)
        #--- File-scope method definitions, chunked from each header to the
        #--- next boundary. A boundary is the next definition header OR the
        #--- next class/struct declaration - without the latter, the final
        #--- method of one class swallows the whole next class body and its
        #--- member declarations get attributed to the wrong owner.
        defs = list(DEFN_TOP.finditer(code))
        marks = sorted({m.start() for m in defs} |
                       {m.start() for m in
                        re.finditer(r"^(?:class|struct)\s+\w+", code, re.M)} |
                       {len(code)})
        spans = []
        for m in defs:
            end = next(x for x in marks if x > m.start())
            spans.append((m.group(1), m.start(), code[m.start():end]))
        #--- Class bodies, which hold the inline methods.
        for m in CLASS_HEAD.finditer(code):
            body = class_body(code, m.group(1))
            if body:
                spans.append((m.group(1), body.start(), body.group(0)))
        for cls, offset, chunk in spans:
            if cls not in bases:
                continue                     # not a class defined in this tree
            ok = allowed(cls)
            for name in sorted(set(MEMBER_USE.findall(chunk))):
                if name not in ok:
                    line = code[:offset + chunk.index(name)].count("\n") + 1
                    bad.append(f"{rel}:{line}: {cls} has no {name}")
    check(not bad, "8. every m_member used is in that class's scope",
          "; ".join(bad[:8]))
    return not bad


# --------------------------------------------------------------------------
# 9. every .Method( call names a callable that EXISTS somewhere in the tree.
#
#    "Exists" = the identifier appears followed by '(' in a position that is
#    not itself a member call, i.e. a declaration, a definition, a free
#    function or a Class::Method reference. This tree includes no MQL5
#    standard-library header, so the closure really is the whole tree and an
#    unmatched name means an invented API. That is exactly the defect that
#    'exec_log.LogExecution(...)' was, against a real 'LogExecutionTime'.
# --------------------------------------------------------------------------
CALL_USE = re.compile(r"\.\s*([A-Z]\w*)\s*\(")
CALL_DEF = re.compile(r"(?<![.\w])([A-Z]\w*)\s*\(")


def check_calls(files, root):
    exists = set()
    for f in files:
        exists |= set(CALL_DEF.findall(strip_code(read(f))))
    bad = []
    for f in files:
        code = strip_code(read(f))
        for name in sorted(set(CALL_USE.findall(code))):
            if name not in exists:
                line = code[:code.index(name)].count("\n") + 1
                bad.append(f"{os.path.relpath(f, root)}:{line}: .{name}()")
    check(not bad, "9. every .Method() call names something that exists",
          "; ".join(bad[:8]))
    return not bad


# --------------------------------------------------------------------------
# 10. every UNQUALIFIED Capitalised call resolves to something the tree
#     declares - calibrated against the preserved baseline.
#
#     The hard part is MQL5's several hundred built-in functions, which are
#     declared nowhere and which no hand-written allowlist would ever cover
#     completely. So the allowlist is DERIVED: run the same resolver over the
#     untouched baseline tree, which is known to compile, and treat whatever
#     fails to resolve there as a built-in by definition. Only names that are
#     unresolved in the WORKING tree and absent from the baseline can fail.
#
#     Consequence worth stating: an incomplete name harvest costs sensitivity
#     and never precision, because anything the harvest misses is present in
#     both trees and therefore lands in the allowlist. This is the check that
#     catches a helper that is called but never declared - the third defect
#     in this session's fix-2 block was exactly that.
# --------------------------------------------------------------------------
UNQUAL_CALL = re.compile(r"(?<![.\w:])([A-Z]\w*)\s*\(")


def declared_names(files):
    out = set()
    for f in files:
        code = strip_code(read(f))
        out |= set(re.findall(r"^(?:class|struct|enum)\s+(\w+)", code, re.M))
        out |= set(re.findall(r"^\s*#define\s+(\w+)", code, re.M))
        out |= set(re.findall(r"\b([A-Z]\w*)::", code))
        out |= set(re.findall(r"::([A-Za-z_]\w*)\s*\(", code))
        out |= set(m.group(1) for m in DECL.finditer(code))
        #--- Inline in-class definitions end in '{', not ';'.
        out |= set(re.findall(
            r"^\s{2,}(?:static\s+|virtual\s+)*(?:const\s+)?"
            r"[A-Za-z_][\w:<>*&\s]*?\b([A-Z]\w*)\s*\([^;{]*\)"
            r"\s*(?:const\s*)?(?:override\s*)?\{", code, re.M))
        #--- Free functions and EA entry points at column 0.
        out |= set(re.findall(
            r"^(?!\s)(?:[\w:<>*&]+\s+)+([A-Z]\w*)\s*\([^;]*$", code, re.M))
    return out


def unresolved_calls(files):
    known = declared_names(files)
    out = {}
    for f in files:
        code = strip_code(read(f))
        for name in set(UNQUAL_CALL.findall(code)):
            if name not in known:
                out.setdefault(name, f)
    return out


def check_unqualified(files, root, baseline):
    if not baseline or not os.path.isdir(baseline):
        return True                       # not calibrated, so not asserted
    allow = set(unresolved_calls(sources(baseline)).keys())
    bad = [f"{os.path.relpath(f, root)}: {n}()"
           for n, f in sorted(unresolved_calls(files).items())
           if n not in allow]
    check(not bad, "10. every unqualified call resolves (vs baseline)",
          "; ".join(bad[:8]))
    return not bad


# --------------------------------------------------------------------------
def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    root = os.path.abspath(sys.argv[1])
    chains = []
    baseline = ""
    for arg in sys.argv[2:]:
        if arg.startswith("--baseline"):
            baseline = os.path.abspath(arg.split("=", 1)[1]) if "=" in arg else ""
        elif arg.startswith("--chain"):
            spec = arg.split("=", 1)[1] if "=" in arg else ""
            for pair in spec.split(","):
                if "=" in pair:
                    a, b = pair.split("=", 1)
                    chains.append((a.strip(), b.strip()))
    files = sources(root)
    print(f"srpcheck: {len(files)} source files under {root}")
    if baseline:
        print(f"          calibrated against baseline {baseline}")
    print()

    check_balance(files, root)
    check_includes(files, root)
    check_methods(files, root)
    check_config_keys(files, root)
    check_guards(files, root)
    check_members(files, root)
    check_calls(files, root)
    check_unqualified(files, root, baseline)
    for field, key in chains:
        ok, consumers = check_chain(root, files, field, key)
        mark = "OK  " if ok else "FAIL"
        print(f"  chain {mark} {field} <- {key}")
        for c in consumers:
            print(f"           consumer: {c}")

    print()
    if FAILURES:
        print(f"CHECKS={CHECKS[0]} FAILED={len(FAILURES)} VERDICT=FAIL")
        for f in FAILURES:
            print("  FAIL " + f)
        return 1
    print(f"CHECKS={CHECKS[0]} FAILED=0 VERDICT=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
