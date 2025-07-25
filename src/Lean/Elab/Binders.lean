/-
Copyright (c) 2019 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Leonardo de Moura
-/
prelude
import Lean.Elab.Quotation.Precheck
import Lean.Elab.Term
import Lean.Elab.BindersUtil
import Lean.Elab.SyntheticMVars
import Lean.Elab.PreDefinition.TerminationHint
import Lean.Elab.Match
import Lean.Compiler.MetaAttr

namespace Lean.Elab.Term
open Meta
open Lean.Parser.Term
open TSyntax.Compat

/--
  Given syntax of the forms
    a) (`:` term)?
    b) `:` term
  return `term` if it is present, or a hole if not. -/
private def expandBinderType (ref : Syntax) (stx : Syntax) : Syntax :=
  if stx.getNumArgs == 0 then
    mkHole ref
  else
    stx[1]

/-- Given syntax of the form `ident <|> hole`, return `ident`. If `hole`, then we create a new anonymous name. -/
private def expandBinderIdent (stx : Syntax) : TermElabM Syntax :=
  match stx with
  | `(_) => mkFreshIdent stx (canonical := true)
  | _    => pure stx

/-- Given syntax of the form `(ident >> " : ")?`, return `ident`, or a new instance name. -/
private def expandOptIdent (stx : Syntax) : TermElabM Syntax := do
  if stx.isNone then
    let id ← withFreshMacroScope <| MonadQuotation.addMacroScope `inst
    return mkIdentFrom stx id
  else
    return stx[0]

/-- Auxiliary datatype for elaborating binders. -/
structure BinderView where
  /--
  Position information provider for the Info Tree.
  We currently do not track binder "macro expansion" steps in the info tree.
  For example, suppose we expand a `_` into a fresh identifier. The fresh identifier
  has synthetic position since it was not written by the user, and we would not get
  hover information for the `_` because we also don't have this macro expansion step
  stored in the info tree. Thus, we store the original `Syntax` in `ref`, and use
  it when storing the binder information in the info tree.

  Potential better solution: add a binder syntax category, an extensible `elabBinder`
  (like we have `elabTerm`), and perform all macro expansion steps at `elabBinder` and
  record them in the info tree.
  -/
  ref  : Syntax
  id   : Syntax
  type : Syntax
  bi   : BinderInfo

/--
Determines the local declaration kind depending on the variable name.

The `__x` in `let __x := 42; body` gets kind `.implDetail`.
-/
def kindOfBinderName (binderName : Name) : LocalDeclKind :=
  if binderName.isImplementationDetail then
    .implDetail
  else
    .default

partial def quoteAutoTactic : Syntax → CoreM Expr
  | .ident _ _ val preresolved =>
    return mkApp4 (.const ``Syntax.ident [])
      (.const ``SourceInfo.none [])
      (.app (.const ``String.toSubstring []) (mkStrLit (toString val)))
      (toExpr val)
      (toExpr preresolved)
  | stx@(.node _ k args) => do
    if stx.isAntiquot then
      throwErrorAt stx "invalid auto tactic, antiquotation is not allowed"
    else
      let ty := .const ``Syntax []
      let mut quotedArgs := mkApp (.const ``Array.empty [.zero]) ty
      for arg in args do
        if k == nullKind && (arg.isAntiquotSuffixSplice || arg.isAntiquotSplice) then
          throwErrorAt arg "invalid auto tactic, antiquotation is not allowed"
        else
          let quotedArg ← quoteAutoTactic arg
          quotedArgs := mkApp3 (.const ``Array.push [.zero]) ty quotedArgs quotedArg
      return mkApp3 (.const ``Syntax.node []) (.const ``SourceInfo.none []) (toExpr k) quotedArgs
  | .atom _ val => return .app (.const ``mkAtom []) (toExpr val)
  | .missing    => throwError "invalid auto tactic, tactic is missing"

/--
Adds a declaration whose value is a Syntax expression representing `tactic`.
If `name?` is provided, it is used for the declaration name, and otherwise a fresh name is generated.
Returns the declaration name.
-/
def declareTacticSyntax (tactic : Syntax) (name? : Option Name := none) : TermElabM Name :=
  withFreshMacroScope do
    let name ← name?.getDM do MonadQuotation.addMacroScope ((← getEnv).asyncPrefix?.getD .anonymous ++ `_auto)
    let type := Lean.mkConst `Lean.Syntax
    let value ← quoteAutoTactic tactic
    trace[Elab.autoParam] value
    let decl := Declaration.defnDecl { name, levelParams := [], type, value, hints := .opaque,
                                       safety := DefinitionSafety.safe }
    addDecl decl
    modifyEnv (addMeta · name)
    compileDecl decl
    return name

/--
Expand `optional (binderTactic <|> binderDefault)`
```
def binderTactic  := leading_parser " := " >> " by " >> tacticParser
def binderDefault := leading_parser " := " >> termParser
```
-/
private def expandBinderModifier (type : Syntax) (optBinderModifier : Syntax) : TermElabM Syntax := do
  if optBinderModifier.isNone then
    return type
  else
    let modifier := optBinderModifier[0]
    let kind     := modifier.getKind
    if kind == `Lean.Parser.Term.binderDefault then
      let defaultVal := modifier[1]
      `(optParam $type $defaultVal)
    else if kind == `Lean.Parser.Term.binderTactic then
      let tac := modifier[2]
      let name ← declareTacticSyntax tac
      `(autoParam $type $(mkIdentFrom tac name))
    else
      throwUnsupportedSyntax

private def getBinderIds (ids : Syntax) : TermElabM (Array Syntax) :=
  ids.getArgs.mapM fun id =>
    let k := id.getKind
    if k == identKind || k == `Lean.Parser.Term.hole then
      return id
    else
      throwErrorAt id "identifier or `_` expected"

/--
Convert `stx` into an array of `BinderView`s.
`stx` must be an identifier, `_`, `explicitBinder`, `implicitBinder`, `strictImplicitBinder`, or `instBinder`.
-/
private def toBinderViews (stx : Syntax) : TermElabM (Array BinderView) := do
  let k := stx.getKind
  if stx.isIdent || k == ``hole then
    -- binderIdent
    return #[{ ref := stx, id := (← expandBinderIdent stx), type := mkHole stx, bi := .default }]
  else if k == ``Lean.Parser.Term.explicitBinder then
    -- `(` binderIdent+ binderType (binderDefault <|> binderTactic)? `)`
    let ids ← getBinderIds stx[1]
    let type        := stx[2]
    let optModifier := stx[3]
    ids.mapM fun id => do pure { ref := id, id := (← expandBinderIdent id), type := (← expandBinderModifier (expandBinderType id type) optModifier), bi := .default }
  else if k == ``Lean.Parser.Term.implicitBinder then
    -- `{` binderIdent+ binderType `}`
    let ids ← getBinderIds stx[1]
    let type := stx[2]
    ids.mapM fun id => do pure { ref := id, id := (← expandBinderIdent id), type := expandBinderType id type, bi := .implicit }
  else if k == ``Lean.Parser.Term.strictImplicitBinder then
    -- `⦃` binderIdent+ binderType `⦄`
    let ids ← getBinderIds stx[1]
    let type := stx[2]
    ids.mapM fun id => do pure { ref := id, id := (← expandBinderIdent id), type := expandBinderType id type, bi := .strictImplicit }
  else if k == ``Lean.Parser.Term.instBinder then
    -- `[` optIdent type `]`
    let id ← expandOptIdent stx[1]
    let type := stx[2]
    return #[ { ref := id, id := id, type := type, bi := .instImplicit } ]
  else
    throwUnsupportedSyntax

/--
The error name for "failed to infer binder type" errors.

We cannot use `logNamedError` here because the error is logged later, after attempting to synthesize
metavariables, in `logUnassignedUsingErrorInfos`.
-/
def failedToInferBinderTypeErrorName := `lean.inferBinderTypeFailed

private def registerFailedToInferBinderTypeInfo (type : Expr) (view : BinderView) : TermElabM Unit := do
  let msg := if view.id.getId.hasMacroScopes then
    m!"binder type"
  else
    m!"type of binder `{view.id.getId}`"
  registerCustomErrorIfMVar type view.ref (m!"Failed to infer {msg}".tagWithErrorName failedToInferBinderTypeErrorName)
  registerLevelMVarErrorExprInfo type view.ref m!"Failed to infer universe levels in {msg}"

def addLocalVarInfo (stx : Syntax) (fvar : Expr) : TermElabM Unit :=
  addTermInfo' (isBinder := true) stx fvar

private def ensureAtomicBinderName (binderView : BinderView) : TermElabM Unit :=
  let n := binderView.id.getId.eraseMacroScopes
  unless n.isAtomic do
    throwErrorAt binderView.id "invalid binder name '{n}', it must be atomic"

register_builtin_option checkBinderAnnotations : Bool := {
  defValue := true
  descr    := "check whether type is a class instance whenever the binder annotation `[...]` is used"
}

/-- Throw an error if `type` is not a valid local instance. -/
private partial def checkLocalInstanceParameters (type : Expr) : TermElabM Unit := do
  let .forallE n d b bi ← whnf type | return ()
  -- We allow instance arguments so that local instances of the form
  -- `variable [∀ (a : α) [P a], Q a]`
  -- are accepted, per https://github.com/leanprover/lean4/issues/2311
  if bi != .instImplicit && !b.hasLooseBVar 0 then
    throwError "invalid parametric local instance, parameter with type{indentExpr d}\ndoes not have forward dependencies, type class resolution cannot use this kind of local instance because it will not be able to infer a value for this parameter."
  withLocalDecl n bi d fun x => checkLocalInstanceParameters (b.instantiate1 x)

private partial def elabBinderViews (binderViews : Array BinderView) (fvars : Array (Syntax × Expr)) (k : Array (Syntax × Expr) → TermElabM α)
    : TermElabM α :=
  let rec loop (i : Nat) (fvars : Array (Syntax × Expr)) : TermElabM α := do
    if h : i < binderViews.size then
      let binderView := binderViews[i]
      ensureAtomicBinderName binderView
      let type ← elabType binderView.type
      registerFailedToInferBinderTypeInfo type binderView
      if binderView.bi.isInstImplicit && checkBinderAnnotations.get (← getOptions) then
        unless (← isClass? type).isSome do
          throwErrorAt binderView.type (m!"invalid binder annotation, type is not a class instance{indentExpr type}" ++ .note "Use the command `set_option checkBinderAnnotations false` to disable the check")
        withRef binderView.type <| checkLocalInstanceParameters type
      let id := binderView.id.getId
      let kind := kindOfBinderName id
      withLocalDecl id binderView.bi type (kind := kind) fun fvar => do
        addLocalVarInfo binderView.ref fvar
        loop (i+1) (fvars.push (binderView.id, fvar))
    else
      k fvars
  loop 0 fvars

private partial def elabBindersAux (binders : Array Syntax) (k : Array (Syntax × Expr) → TermElabM α) : TermElabM α :=
  let rec loop (i : Nat) (fvars : Array (Syntax × Expr)) : TermElabM α := do
    if h : i < binders.size then
      let binderViews ← toBinderViews binders[i]
      elabBinderViews binderViews fvars <| loop (i+1)
    else
      k fvars
  loop 0 #[]

/--
  Like `elabBinders`, but also pass syntax node per binder.
  `elabBinders(Ex)` automatically adds binder info nodes for the produced fvars, but storing the syntax nodes
  might be necessary when later adding the same binders back to the local context so that info nodes can
  manually be added for the new fvars; see `MutualDef` for an example. -/
def elabBindersEx (binders : Array Syntax) (k : Array (Syntax × Expr) → TermElabM α) : TermElabM α :=
  universeConstraintsCheckpoint do
    if binders.isEmpty then
      k #[]
    else
      elabBindersAux binders k

/--
  Elaborate the given binders (i.e., `Syntax` objects for `bracketedBinder`),
  update the local context, set of local instances, reset instance cache (if needed), and then
  execute `k` with the updated context.
  The local context will only be included inside `k`.

  For example, suppose you have binders `[(a : α), (b : β a)]`, then the elaborator will
  create two new free variables `a` and `b`, push these to the context and pass to `k #[a,b]`.
  -/
def elabBinders (binders : Array Syntax) (k : Array Expr → TermElabM α) : TermElabM α :=
  elabBindersEx binders (fun fvars => k (fvars.map (·.2)))

/-- Same as `elabBinder` with a single binder.-/
def elabBinder (binder : Syntax) (x : Expr → TermElabM α) : TermElabM α :=
  elabBinders #[binder] fun fvars => x fvars[0]!

/-- If `binder` is a `_` or an identifier, return a `bracketedBinder` using `type` otherwise throw an exception. -/
def expandSimpleBinderWithType (type : Term) (binder : Syntax) : MacroM Syntax :=
  if binder.isOfKind ``hole || binder.isIdent then
    `(bracketedBinderF| ($binder : $type))
  else
    Macro.throwErrorAt type "unexpected type ascription"

@[builtin_macro Lean.Parser.Term.forall] def expandForall : Macro
  | `(forall $binders* : $ty, $term) => do
    let binders ← binders.mapM (expandSimpleBinderWithType ty)
    `(forall $binders*, $term)
  | _ => Macro.throwUnsupported

@[builtin_term_elab «forall»] def elabForall : TermElab := fun stx _ =>
  match stx with
  | `(forall $binders*, $term) =>
    elabBinders binders fun xs => do
      let e ← elabType term
      mkForallFVars xs e
  | _ => throwUnsupportedSyntax

open Lean.Elab.Term.Quotation in
@[builtin_quot_precheck Lean.Parser.Term.arrow] def precheckArrow : Precheck
  | `($dom:term -> $rng) => do
    precheck dom
    precheck rng
  | _ => throwUnsupportedSyntax

@[builtin_term_elab arrow] def elabArrow : TermElab := fun stx _ =>
  match stx with
  | `($dom:term -> $rng) => do
    -- elaborate independently from each other
    let dom ← elabType dom
    let rng ← elabType rng
    return mkForall (← MonadQuotation.addMacroScope `a) BinderInfo.default dom rng
  | _                    => throwUnsupportedSyntax

/--
The dependent arrow. `(x : α) → β` is equivalent to `∀ x : α, β`, but we usually
reserve the latter for propositions. Also written as `Π x : α, β` (the "Pi-type")
in the literature. -/
@[builtin_term_elab depArrow] def elabDepArrow : TermElab := fun stx _ =>
  -- bracketedBinder `->` term
  let binder := stx[0]
  let term   := stx[2]
  elabBinders #[binder] fun xs => do
    mkForallFVars xs (← elabType term)

/--
  Auxiliary functions for converting `id_1 ... id_n` application into `#[id_1, ..., id_m]`
  It is used at `expandFunBinders`. -/
private partial def getFunBinderIds? (stx : Syntax) : OptionT MacroM (Array Syntax) :=
  let convertElem (stx : Term) : OptionT MacroM Syntax :=
    match stx with
    | `(_) =>
      /-
      We used to use `mkFreshIdent` here,
      but it prevented us from obtaining hover info for `_` because the
      fresh identifier would have a synthetic position, and synthetic positions
      are ignored by the LSP server.
      See comment at `BinderView.ref` for additional details.
      -/
      return stx
    | `($_:ident) => return stx
    | _ => failure
  match stx with
  | `($f $args*) => do
     let mut acc := #[].push (← convertElem f)
     for arg in args do
       acc := acc.push (← convertElem arg)
     return acc
  | _ =>
    return #[].push (← convertElem stx)

/--
  Auxiliary function for expanding `fun` notation binders. Recall that `fun` parser is defined as
  ```
  def funBinder : Parser := implicitBinder <|> instBinder <|> termParser maxPrec
  leading_parser unicodeSymbol "λ" "fun" >> many1 funBinder >> "=>" >> termParser
  ```
  to allow notation such as `fun (a, b) => a + b`, where `(a, b)` should be treated as a pattern.
  The result is a pair `(explicitBinders, newBody)`, where `explicitBinders` is syntax of the form
  ```
  `(` ident `:` term `)`
  ```
  which can be elaborated using `elabBinders`, and `newBody` is the updated `body` syntax.
  We update the `body` syntax when expanding the pattern notation.
  Example: `fun (a, b) => a + b` expands into `fun _a_1 => match _a_1 with | (a, b) => a + b`.
  See local function `processAsPattern` at `expandFunBindersAux`.

  The resulting `Bool` is true if a pattern was found. We use it "mark" a macro expansion. -/
partial def expandFunBinders (binders : Array Syntax) (body : Syntax) : MacroM (Array Syntax × Syntax × Bool) :=
  let rec loop (body : Syntax) (i : Nat) (newBinders : Array Syntax) := do
    if h : i < binders.size then
      let binder := binders[i]
      let processAsPattern : Unit → MacroM (Array Syntax × Syntax × Bool) := fun _ => do
        let pattern := binder
        let major ← mkFreshIdent binder
        let (binders, newBody, _) ← loop body (i+1) (newBinders.push $ mkExplicitBinder major (mkHole binder))
        let newBody ← `(match $major:ident with | $pattern => $newBody)
        pure (binders, newBody, true)
      match binder.getKind with
      | ``Lean.Parser.Term.implicitBinder
      | ``Lean.Parser.Term.strictImplicitBinder
      | ``Lean.Parser.Term.instBinder
      | ``Lean.Parser.Term.explicitBinder
      | ``Lean.Parser.Term.hole | `ident => loop body (i+1) (newBinders.push binder)
      | ``Lean.Parser.Term.paren =>
        let term := binder[1]
        match (← getFunBinderIds? term) with
        | some idents =>
          -- `fun (x ...) ...` ~> `fun (x : _) ...`
          -- Interpret `(x ...)` as sequence of binders instead of pattern only if none of the idents
          -- are defined in the global scope. Technically, it would be sufficient to only check the
          -- first ident to be sure that the syntax cannot possibly be a valid pattern. However, for
          -- consistency we apply the same check to all idents so that the possibility of shadowing
          -- a global decl is identical for all of them.
          if (← idents.allM fun ident => return List.isEmpty (← Macro.resolveGlobalName ident.getId)) then
            loop body (i+1) (newBinders ++ idents.map (mkExplicitBinder · (mkHole binder)))
          else
            processAsPattern ()
        | none => processAsPattern ()
      | ``Lean.Parser.Term.typeAscription =>
        let term := binder[1]
        let type := binder[3].getOptional?.getD (mkHole binder)
        match (← getFunBinderIds? term) with
        | some idents => loop body (i+1) (newBinders ++ idents.map (fun ident => mkExplicitBinder ident type))
        | none        => processAsPattern ()
      | _ => processAsPattern ()
    else
      pure (newBinders, body, false)
  loop body 0 #[]

namespace FunBinders

structure State where
  fvars         : Array Expr := #[]
  lctx          : LocalContext
  localInsts    : LocalInstances
  expectedType? : Option Expr := none

private def propagateExpectedType (fvar : Expr) (fvarType : Expr) (s : State) : TermElabM State := do
  match s.expectedType? with
  | none              => pure s
  | some expectedType =>
    let expectedType ← whnfForall expectedType
    match expectedType with
    | .forallE _ d b _ =>
      discard <| isDefEq fvarType d
      let b := b.instantiate1 fvar
      return { s with expectedType? := some b }
    | _ =>
      return { s with expectedType? := none }

private partial def elabFunBinderViews (binderViews : Array BinderView) (i : Nat) (s : State) : TermElabM State := do
  if h : i < binderViews.size then
    let binderView := binderViews[i]
    ensureAtomicBinderName binderView
    withRef binderView.type <| withLCtx s.lctx s.localInsts do
      let type ← elabType binderView.type
      registerFailedToInferBinderTypeInfo type binderView
      let fvarId ← mkFreshFVarId
      let fvar  := mkFVar fvarId
      let s     := { s with fvars := s.fvars.push fvar }
      let id    := binderView.id.getId
      let kind  := kindOfBinderName id
      /-
        We do **not** want to support default and auto arguments in lambda abstractions.
        Example: `fun (x : Nat := 10) => x+1`.
        We do not believe this is an useful feature, and it would complicate the logic here.
      -/
      let lctx  := s.lctx.mkLocalDecl fvarId id type binderView.bi kind
      addTermInfo' (lctx? := some lctx) (isBinder := true) binderView.ref fvar
      let s ← withRef binderView.id <| propagateExpectedType fvar type s
      let s := { s with lctx }
      match ← isClass? type, kind with
      | some className, .default =>
        let localInsts := s.localInsts.push { className, fvar := mkFVar fvarId }
        elabFunBinderViews binderViews (i+1) { s with localInsts }
      | _, _ => elabFunBinderViews binderViews (i+1) s
  else
    pure s

partial def elabFunBindersAux (binders : Array Syntax) (i : Nat) (s : State) : TermElabM State := do
  if h : i < binders.size then
    let binderViews ← toBinderViews binders[i]
    let s ← elabFunBinderViews binderViews 0 s
    elabFunBindersAux binders (i+1) s
  else
    pure s

end FunBinders

def elabFunBinders (binders : Array Syntax) (expectedType? : Option Expr) (x : Array Expr → Option Expr → TermElabM α) : TermElabM α :=
  if binders.isEmpty then
    x #[] expectedType?
  else do
    let lctx ← getLCtx
    let localInsts ← getLocalInstances
    let s ← FunBinders.elabFunBindersAux binders 0 { lctx, localInsts, expectedType? }
    withLCtx s.lctx s.localInsts do
      x s.fvars s.expectedType?

def expandWhereDecls (whereDecls : Syntax) (body : Syntax) : MacroM Syntax :=
  match whereDecls with
  | `(whereDecls|where $[$_:whereFinally]?) => `($body)
  | `(whereDecls|where $[$decls:letRecDecl];* $[$_:whereFinally]?) => `(let rec $decls:letRecDecl,*; $body)
  | _ => Macro.throwUnsupported

def expandWhereDeclsOpt (whereDeclsOpt : Syntax) (body : Syntax) : MacroM Syntax :=
  if whereDeclsOpt.isNone then
    return body
  else
    expandWhereDecls whereDeclsOpt[0] body

/--
 Helper function for `expandMatchAltsIntoMatch`.
-/
private def expandMatchAltsIntoMatchAux (matchAlts : Syntax) (isTactic : Bool) (useExplicit : Bool) : Nat → Array Syntax → Array Ident → MacroM Syntax
  | 0,   discrs, xs => do
    if isTactic then
      `(tactic|match $[$discrs:term],* with $matchAlts:matchAlts)
    else
      let stx ← `(match $[$discrs:term],* with $matchAlts:matchAlts)
      clearInMatch stx xs
  | n+1, discrs, xs => withFreshMacroScope do
    let x ← `(x) -- If this were implementation-detail, the `contradiction` tactic used by match would not find it.
    let d ← `(@$x:ident)
    let body ← expandMatchAltsIntoMatchAux matchAlts isTactic useExplicit n (discrs.push d) (xs.push x)
    if isTactic then
      `(tactic| intro $x:term; $body:tactic)
    else if useExplicit then
      `(@fun $x => $body)
    else
      `(fun $x => $body)

/--
  Expand `matchAlts` syntax into a full `match`-expression.
  Example:
  ```
  | 0, true => alt_1
  | i, _    => alt_2
  ```
  expands into (for tactic == false)
  ```
  fun x_1 x_2 =>
  match @x_1, @x_2 with
  | 0, true => alt_1
  | i, _    => alt_2
  ```
  and (for tactic == true)
  ```
  intro x_1; intro x_2;
  match @x_1, @x_2 with
  | 0, true => alt_1
  | i, _    => alt_2
  ```

  If `useExplicit = true`, we add a `@` before `fun` to disable implicit lambdas. We disable them when processing `let` and `let rec` declarations
  to make sure the behavior is consistent with top-level declarations where we can write
  ```
  def f : {α : Type} → α → α
    | _, a => a
  ```
  We use `useExplicit = false` when we are elaborating the `fun | ... => ... | ...` notation. See issue #1132.
  If `@fun` is used with this notation, the we set `useExplicit = true`.
  We also use `useExplicit = false` when processing `instance ... where` notation declarations. The motivation is to have compact declarations such as
  ```
  instance [Alternative m] : MonadLiftT Option m where
  monadLift -- We don't want to provide the implicit arguments of `monadLift` here. One should use `monadLift := @fun ...` if they want to provide them.
    | some a => pure a
    | none => failure
  ```

  Remark: we add `@` at discriminants to make sure we don't consume implicit arguments, and to make the behavior consistent with `fun`.
  Example:
  ```
  inductive T : Type 1 :=
  | mkT : (forall {a : Type}, a -> a) -> T

  def makeT (f : forall {a : Type}, a -> a) : T :=
    mkT f

  def makeT' : (forall {a : Type}, a -> a) -> T
  | f => mkT f
  ```
  The two definitions should be elaborated without errors and be equivalent.
 -/
def expandMatchAltsIntoMatch (ref : Syntax) (matchAlts : Syntax) (useExplicit := true) : MacroM Syntax :=
  withRef ref <| expandMatchAltsIntoMatchAux matchAlts (isTactic := false) (useExplicit := useExplicit) (getMatchAltsNumPatterns matchAlts) #[] #[]

def expandMatchAltsIntoMatchTactic (ref : Syntax) (matchAlts : Syntax) : MacroM Syntax :=
  withRef ref <| expandMatchAltsIntoMatchAux matchAlts (isTactic := true) (useExplicit := false) (getMatchAltsNumPatterns matchAlts) #[] #[]

/--
Sanity-checks the number of patterns in each alternative of a definition by pattern matching.
Specifically, verifies that all alternatives have the same number of patterns and that the number
of patterns is upper-bounded by the number of (dependent) arrows in the expected type.

Note: This function assumes that the number of patterns in the first alternative will be equal to
`numDiscrs` (since we use the first alternative to infer the arity of the generated matcher in
`getMatchAltsNumPatterns`).
-/
private def checkMatchAltPatternCounts (matchAlts : Syntax) (numDiscrs : Nat) (expectedType : Expr)
    : MetaM Unit := do
  let sepPats (pats : List Syntax) := MessageData.joinSep (pats.map toMessageData) ", "
  let maxDiscrs? ← forallTelescopeReducing expectedType fun xs e =>
    if e.getAppFn.isMVar then pure none else pure (some xs.size)
  let matchAltViews := matchAlts[0].getArgs.filterMap getMatchAlt
  let numPatternsStr (n : Nat) := s!"{n} {if n == 1 then "pattern" else "patterns"}"
  if h : matchAltViews.size > 0 then
    if let some maxDiscrs := maxDiscrs? then
      if numDiscrs > maxDiscrs then
        if maxDiscrs == 0 then
          throwErrorAt matchAltViews[0].lhs m!"Cannot define a value of type{indentExpr expectedType}\n\
            by pattern matching because it is not a function type"
        else
          throwErrorAt matchAltViews[0].lhs m!"Too many patterns in match alternative: \
            At most {numPatternsStr maxDiscrs} expected in a definition of type {indentExpr expectedType}\n\
            but found {numDiscrs}:{indentD <| sepPats matchAltViews[0].patterns.toList}"
    -- Catch inconsistencies between pattern counts here so that we can report them as "inconsistent"
    -- rather than as "too many" or "too few" (as the `match` elaborator does)
    for view in matchAltViews do
      let numPats := view.patterns.size
      if numPats != numDiscrs then
        let origPats := sepPats matchAltViews[0].patterns.toList
        let pats := sepPats view.patterns.toList
        throwErrorAt view.lhs m!"Inconsistent number of patterns in match alternatives: This \
          alternative contains {numPatternsStr numPats}:{indentD pats}\n\
          but a preceding alternative contains {numDiscrs}:{indentD origPats}"

/--
  Similar to `expandMatchAltsIntoMatch`, but supports an optional `where` clause.

  Expand `matchAltsWhereDecls` into `let rec` + `match`-expression.
  Example
  ```
  | 0, true => ... f 0 ...
  | i, _    => ... f i + g i ...
  where
    f x := g x + 1

    g : Nat → Nat
      | 0   => 1
      | x+1 => f x
  ```
  expands into
  ```
  fun x_1 x_2 =>
    let rec
      f x := g x + 1,
      g : Nat → Nat
        | 0   => 1
        | x+1 => f x
    match x_1, x_2 with
    | 0, true => ... f 0 ...
    | i, _    => ... f i + g i ...
  ```
-/
def expandMatchAltsWhereDecls (matchAltsWhereDecls : Syntax) (expectedType : Expr) : TermElabM Syntax :=
  let matchAlts     := matchAltsWhereDecls[0]
  -- matchAltsWhereDecls[1] is the termination hints, collected elsewhere
  let whereDeclsOpt := matchAltsWhereDecls[2]
  let rec loop (i : Nat) (discrs : Array Syntax) : TermElabM Syntax :=
    match i with
    | 0   => do
      checkMatchAltPatternCounts matchAlts discrs.size expectedType
      let matchStx ← `(match $[@$discrs:term],* with $matchAlts:matchAlts)
      liftMacroM do
        let matchStx ← clearInMatch matchStx discrs
        if whereDeclsOpt.isNone then
          return matchStx
        else
          expandWhereDeclsOpt whereDeclsOpt matchStx
    | n+1 => withFreshMacroScope do
      let body ← loop n (discrs.push (← `(x)))
      `(@fun x => $body)
  loop (getMatchAltsNumPatterns matchAlts) #[]

@[builtin_macro Parser.Term.fun] partial def expandFun : Macro
  | `(fun $binders* : $ty => $body) => do
    let binders ← binders.mapM (expandSimpleBinderWithType ty)
    `(fun $binders* => $body)
  | `(fun $binders* => $body) => do  -- if there is a type ascription, we assume all binders are already simple
    let (binders, body, expandedPattern) ← expandFunBinders binders body
    if expandedPattern then
      `(fun $binders* => $body)
    else
      Macro.throwUnsupported
  | stx@`(fun $m:matchAlts) => expandMatchAltsIntoMatch stx m (useExplicit := false)
  | _ => Macro.throwUnsupported

@[builtin_macro Parser.Term.explicit] partial def expandExplicitFun : Macro := fun stx =>
  match stx with
  | `(@fun $m:matchAlts) => expandMatchAltsIntoMatch stx[1] m (useExplicit := true)
  | _ => Macro.throwUnsupported

open Lean.Elab.Term.Quotation in
@[builtin_quot_precheck Lean.Parser.Term.fun] def precheckFun : Precheck
  | `(fun $binders* $[: $ty?]? => $body) => do
    let (binders, body, _) ← liftMacroM <| expandFunBinders binders body
    let mut ids := #[]
    for b in binders do
      for v in ← toBinderViews b do
        Quotation.withNewLocals ids <| precheck v.type
        ids := ids.push v.id.getId
    Quotation.withNewLocals ids <| precheck body
  | _ => throwUnsupportedSyntax

@[builtin_term_elab «fun»] partial def elabFun : TermElab := fun stx expectedType? =>
  match stx with
  | `(fun $binders* => $body) => do
    -- We can assume all `match` binders have been iteratively expanded by the above macro here, though
    -- we still need to call `expandFunBinders` once to obtain `binders` in a normal form
    -- expected by `elabFunBinder`.
    let (binders, body, _) ← liftMacroM <| expandFunBinders binders body
    elabFunBinders binders expectedType? fun xs expectedType? => do
      /- We ensure the expectedType here since it will force coercions to be applied if needed.
          If we just use `elabTerm`, then we will need to a coercion `Coe (α → β) (α → δ)` whenever there is a coercion `Coe β δ`,
          and another instance for the dependent version. -/
      let e ← elabTermEnsuringType body expectedType?
      mkLambdaFVars xs e
  | _ => throwUnsupportedSyntax

/--
Configuration for `let` elaboration.
-/
structure LetConfig where
  /-- Elaborate as a nondependent `let` (a `have`). -/
  nondep : Bool := false
  /-- Eliminate the `let` if it is unused by the body. -/
  usedOnly : Bool := false
  /-- Zeta reduces (inlines) the `let`. -/
  zeta : Bool := false
  /-- Postpone elaboration of the value until after the body is elaborated. -/
  postponeValue : Bool := false
  /-- Generalize the value from the expected type when elaborating the body. -/
  generalize : Bool := false
  /-- For `let x := v; b`, adds `eq : x = v` to the context. -/
  eq? : Option Ident := none

def LetConfig.setFrom (config : LetConfig) (key : Syntax) (val : Bool) : LetConfig :=
  if key.isOfKind ``Parser.Term.letOptNondep then
    { config with nondep := val }
  else if key.isOfKind ``Parser.Term.letOptUsedOnly then
    { config with usedOnly := val }
  else if key.isOfKind ``Parser.Term.letOptZeta then
    { config with zeta := val }
  else if key.isOfKind ``Parser.Term.letOptPostponeValue then
    { config with postponeValue := val }
  else if key.isOfKind ``Parser.Term.letOptGeneralize then
    { config with generalize := val }
  else
    config

/--
Interprets a `Parser.Term.letConfig`.
-/
def mkLetConfig (letConfig : Syntax) (initConfig : LetConfig) : TermElabM LetConfig := do
  let mut config := initConfig
  unless letConfig.isOfKind ``Parser.Term.letConfig do
    return config
  for item in letConfig[0].getArgs do
    match item with
    | `(letPosOpt| +$opt:letOpts) => config := config.setFrom opt.raw[0] true
    | `(letNegOpt| -$opt:letOpts) => config := config.setFrom opt.raw[0] false
    | `(letOptEq| (eq := $n:ident)) => config := { config with eq? := n }
    | `(letOptEq| (eq := $b)) => config := { config with eq? := mkIdentFrom b (canonical := true) (← mkFreshBinderNameForTactic `h) }
    | _ => pure ()
  return config

/--
The default elaboration order is `binders`, `typeStx`, `valStx`, and `body`.
If `config.postponeValue == true`, then we use the order `binders`, `typeStx`, `body`, and `valStx`.
If `config.generalize == true`, then the value is abstracted from the expected type when elaborating the body.
-/
def elabLetDeclAux (id : Syntax) (binders : Array Syntax) (typeStx : Syntax) (valStx : Syntax) (body : Syntax)
    (expectedType? : Option Expr) (config : LetConfig) : TermElabM Expr := do
  if config.generalize then
    if config.postponeValue then
      throwError "`+postponeValue` and `+generalize` are incompatible"
    tryPostponeIfNoneOrMVar expectedType?
  let (type, val, binders) ← elabBindersEx binders fun xs => do
    let (binders, fvars) := xs.unzip
    /-
    We use `withSynthesize` to ensure that any postponed elaboration problem
    and nested tactics in `type` are resolved before elaborating `val`.
    Resolved: we want to avoid synthetic opaque metavariables in `type`.
    Recall that this kind of metavariable is non-assignable, and `isDefEq`
    may waste a lot of time unfolding declarations before failing.
    See issue #4051 for an example.

    Here is the analysis for issue #4051.
    - Given `have x : type := value; body`, we were previously elaborating `value` even
      if `type` contained postponed elaboration problems.
    - Moreover, the metavariables in `type` corresponding to postponed elaboration
      problems cannot be assigned by `isDefEq` since the elaborator is supposed to assign them.
    - Then, when checking whether type of `value` is definitionally equal to `type`,
      a very long-time was spent unfolding a bunch of declarations before it failed.
      In #4051, it was unfolding `Array.swaps` which is defined by well-founded recursion.
      After the failure, the elaborator inserted a postponed coercion
      that would be resolved later as soon as the types don't have unassigned metavariables.

    We use `postpone := .partial` to allow type class (TC) resolution problems to be postponed
    Recall that TC resolution does **not** produce synthetic opaque metavariables.
    -/
    let type ← withSynthesize (postpone := .partial) <| elabType typeStx
    let letMsg := if config.nondep then "have" else "let"
    registerCustomErrorIfMVar type typeStx m!"failed to infer '{letMsg}' declaration type"
    registerLevelMVarErrorExprInfo type typeStx m!"failed to infer universe levels in '{letMsg}' declaration type"
    if config.postponeValue then
      let type ← mkForallFVars fvars type
      let val  ← mkFreshExprMVar type
      pure (type, val, binders)
    else
      let val  ← elabTermEnsuringType valStx type
      let type ← mkForallFVars fvars type
      /- By default `mkLambdaFVars` and `mkLetFVars` create binders only for let-declarations that are actually used
         in the body. This generates counterintuitive behavior in the elaborator since users will not be notified
         about holes such as
         ```
          def ex : Nat :=
            let x := _
            42
         ```
       -/
      let val  ← mkLambdaFVars fvars val (usedLetOnly := false)
      pure (type, val, binders)
  let kind := kindOfBinderName id.getId
  trace[Elab.let.decl] "{id.getId} : {type} := {val}"
  let result ←
    withLetDecl id.getId (kind := kind) type val (nondep := config.nondep) fun x => do
      let elabBody : TermElabM Expr := do
        let mut expectedType? := expectedType?
        if config.generalize then
          let throwNoType := throwError "failed to elaborate with `+generalize`, expected type is not available"
          let some expectedType := expectedType? | throwNoType
          let expectedType ← instantiateMVars expectedType
          if expectedType.getAppFn.isMVar then throwNoType
          let motiveBody ← kabstract expectedType (← instantiateMVars val)
          let motive := motiveBody.instantiate1 x
          -- When `config.nondep` is false, then `motive` will be definitionally equal to `expectedType`.
          -- Type correctness only needs to be checked in the `nondep` case:
          if config.nondep then
            unless (← isTypeCorrect motive) do
              throwError "failed to elaborate with `+generalize`, generalized expected type is not type correct:{indentD motive}"
          expectedType? := motive
        elabTermEnsuringType body expectedType? >>= instantiateMVars
      addLocalVarInfo id x
      match config.eq? with
      | none =>
        let body ← elabBody
        if config.zeta then
          pure <| (← body.abstractM #[x]).instantiate1 val
        else
          mkLetFVars #[x] body (usedLetOnly := config.usedOnly) (generalizeNondepLet := false)
      | some h =>
        let hTy ← mkEq x val
        withLetDecl h.getId hTy (← mkEqRefl x) (nondep := true) fun h' => do
          addLocalVarInfo h h'
          let body ← elabBody
          if config.zeta then
            pure <| (← body.abstractM #[x, h']).instantiateRev #[val, ← mkEqRefl val]
          else if config.nondep then
            -- TODO(kmill): Think more about how to encode this case.
            -- Currently we produce `(fun (x : α) (h : x = val) => b) val rfl`.
            -- N.B. the nondep lets become lambdas here.
            let f ← mkLambdaFVars #[x, h'] body
            return mkApp2 f val (← mkEqRefl val)
          else
            mkLetFVars #[x, h'] body (usedLetOnly := config.usedOnly) (generalizeNondepLet := false)
  if config.postponeValue then
    forallBoundedTelescope type binders.size fun xs type => do
      -- the original `fvars` from above are gone, so add back info manually
      for b in binders, x in xs do
        addLocalVarInfo b x
      let valResult ← elabTermEnsuringType valStx type
      let valResult ← mkLambdaFVars xs valResult (usedLetOnly := false)
      unless (← isDefEq val valResult) do
        throwError "unexpected error when elaborating 'let'"
  pure result

structure LetIdDeclView where
  id      : Syntax
  binders : Array Syntax
  type    : Syntax
  value   : Syntax

def mkLetIdDeclView (letIdDecl : Syntax) : LetIdDeclView :=
  /-
  def letId := leading_parser binderIdent <|> hygieneInfo
  def letIdBinder := binderIdent <|> bracketedBinder
  def letIdLhs := letId >> many letIdBinder >> optType
  def letIdDecl := leading_parser letIdLhs >> " := " >> termParser
  -/
  let letId := letIdDecl[0]
  let id :=
    if letId[0].isOfKind hygieneInfoKind then
      HygieneInfo.mkIdent letId[0] `this (canonical := true)
    else
      -- Assumed to be binderIdent
      letId[0]
  let binders := letIdDecl[1].getArgs
  let optType := letIdDecl[2]
  let type    := expandOptType id optType
  let value   := letIdDecl[4]
  { id, binders, type, value }

def expandLetEqnsDecl (letDecl : Syntax) (useExplicit := true) : MacroM Syntax := do
  let ref       := letDecl
  let matchAlts := letDecl[3]
  let val ← expandMatchAltsIntoMatch ref matchAlts (useExplicit := useExplicit)
  return mkNode `Lean.Parser.Term.letIdDecl #[letDecl[0], letDecl[1], letDecl[2], mkAtomFrom ref " := ", val]

def elabLetDeclCore (stx : Syntax) (expectedType? : Option Expr) (initConfig : LetConfig) : TermElabM Expr := do
  let (config, declIdx) ← if stx[1].isOfKind ``Parser.Term.letConfig then
    pure (← mkLetConfig stx[1] initConfig, 2)
  else
    pure (initConfig, 1)
  let letDecl   := stx[declIdx][0]
  let body      := stx[declIdx + 2]
  if letDecl.getKind == ``Lean.Parser.Term.letIdDecl then
    let { id, binders, type, value } := mkLetIdDeclView letDecl
    let id ← if id.isIdent then pure id else mkFreshIdent id (canonical := true)
    elabLetDeclAux id binders type value body expectedType? config
  else if letDecl.getKind == ``Lean.Parser.Term.letPatDecl then
    -- node `Lean.Parser.Term.letPatDecl  $ try (termParser >> pushNone >> optType >> " := ") >> termParser
    let pat     := letDecl[0]
    let optType := letDecl[2]
    let val     := letDecl[4]
    if pat.getKind == ``Parser.Term.hole then
      -- `let _ := ...` should be treated as a `letIdDecl`
      let id   ← mkFreshIdent pat (canonical := true)
      let type := expandOptType id optType
      elabLetDeclAux id #[] type val body expectedType? config
    else
      if config.postponeValue then
        throwError "`+deferValue` with patterns is not allowed"
      if config.usedOnly then
        throwError "`+usedOnly` with patterns is not allowed"
      if config.zeta then
        throwError "`+zeta` with patterns is not allowed"
      -- We are currently ignore `config.nondep` when patterns are used.
      -- We are also currently ignoring `config.generalize`.
      let val ← if optType.isNone then
        `($val:term)
      else
        let type := optType[0][1]
        `(($val:term : $type))
      let stxNew ← if let some h := config.eq? then
        `(match $h:ident : $val:term with | $pat => $body)
      else
        `(match $val:term with | $pat => $body)
      withMacroExpansion stx stxNew <| elabTerm stxNew expectedType?
  else if letDecl.getKind == ``Lean.Parser.Term.letEqnsDecl then
    let letDeclIdNew ← liftMacroM <| expandLetEqnsDecl letDecl
    let declNew := stx[declIdx].setArg 0 letDeclIdNew
    let stxNew  := stx.setArg declIdx declNew
    withMacroExpansion stx stxNew <| elabTerm stxNew expectedType?
  else
    throwUnsupportedSyntax

@[builtin_term_elab «let»] def elabLetDecl : TermElab :=
  fun stx expectedType? => elabLetDeclCore stx expectedType? {}

@[builtin_term_elab «have»] def elabHaveDecl : TermElab :=
  fun stx expectedType? => elabLetDeclCore stx expectedType? { nondep := true }

@[builtin_term_elab «let_fun»] def elabLetFunDecl : TermElab :=
  fun stx expectedType? => do
    withRef stx <| Linter.logLintIf Linter.linter.deprecated stx[0]
      "`let_fun` has been deprecated in favor of `have`"
    elabLetDeclCore stx expectedType? { nondep := true }

@[builtin_term_elab «let_delayed»] def elabLetDelayedDecl : TermElab :=
  fun stx expectedType? => elabLetDeclCore stx expectedType? { postponeValue := true }

@[builtin_term_elab «let_tmp»] def elabLetTmpDecl : TermElab :=
  fun stx expectedType? => elabLetDeclCore stx expectedType? { usedOnly := true }

@[builtin_term_elab «letI»] def elabLetIDecl : TermElab :=
  fun stx expectedType? => elabLetDeclCore stx expectedType? { zeta := true }

@[builtin_term_elab «haveI»] def elabHaveIDecl : TermElab :=
  fun stx expectedType? => elabLetDeclCore stx expectedType? { zeta := true, nondep := true }

builtin_initialize
  registerTraceClass `Elab.let
  registerTraceClass `Elab.let.decl
  registerTraceClass `Elab.autoParam

end Lean.Elab.Term
