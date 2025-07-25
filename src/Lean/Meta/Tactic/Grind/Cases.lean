/-
Copyright (c) 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Leonardo de Moura
-/
prelude
import Lean.Meta.Tactic.Cases

namespace Lean.Meta.Grind

/-- Types that `grind` will case-split on. -/
structure CasesTypes where
  casesMap : PHashMap Name Bool := {}
  deriving Inhabited

structure CasesEntry where
  declName : Name
  eager : Bool
  deriving Inhabited

/--
`grind` always case-splits on the following types. Even when using `grind only`.
The goal is to reduce noise in the tactic generated by `grind?`
-/
private def builtinEagerCases : NameSet :=
  .ofList [``And, ``Exists, ``True, ``False, ``Unit, ``Empty]

/--
Returns `true` if `declName` is the name of inductive type/predicate that
even `grind only` case splits on.
Remark: we added support for them to reduce the noise in the tactic generated by
`grind?`
-/
def isBuiltinEagerCases (declName : Name) : Bool :=
  builtinEagerCases.contains declName

/-- Returns `true` if `s` contains a `declName`. -/
def CasesTypes.contains (s : CasesTypes) (declName : Name) : Bool :=
  s.casesMap.contains declName

/-- Removes the given declaration from `s`. -/
def CasesTypes.erase (s : CasesTypes) (declName : Name) : CasesTypes :=
  { s with casesMap := s.casesMap.erase declName }

def CasesTypes.insert (s : CasesTypes) (declName : Name) (eager : Bool) : CasesTypes :=
  { s with casesMap := s.casesMap.insert declName eager }

def CasesTypes.find? (s : CasesTypes) (declName : Name) : Option Bool :=
  s.casesMap.find? declName

def CasesTypes.isEagerSplit (s : CasesTypes) (declName : Name) : Bool :=
  (s.casesMap.find? declName |>.getD false) || isBuiltinEagerCases declName

def CasesTypes.isSplit (s : CasesTypes) (declName : Name) : Bool :=
  (s.casesMap.find? declName |>.isSome) || isBuiltinEagerCases declName

builtin_initialize casesExt : SimpleScopedEnvExtension CasesEntry CasesTypes ←
  registerSimpleScopedEnvExtension {
    initial        := {}
    addEntry       := fun s {declName, eager} => s.insert declName eager
  }

def resetCasesExt : CoreM Unit := do
  modifyEnv fun env => casesExt.modifyState env fun _ => {}

def getCasesTypes : CoreM CasesTypes :=
  return casesExt.getState (← getEnv)

/-- Returns `true` is `declName` is a builtin split or has been tagged with `[grind]` attribute. -/
def isSplit (declName : Name) : CoreM Bool := do
  return (← getCasesTypes).isSplit declName

partial def isCasesAttrCandidate? (declName : Name) (eager : Bool) : CoreM (Option Name) := do
  match (← getConstInfo declName) with
  | .inductInfo info => if !info.isRec || !eager then return some declName else return none
  | _ => return none

def isCasesAttrCandidate (declName : Name) (eager : Bool) : CoreM Bool := do
  return (← isCasesAttrCandidate? declName eager).isSome

def isCasesAttrPredicateCandidate? (declName : Name) (eager : Bool) : MetaM (Option InductiveVal) := do
  let some declName ← isCasesAttrCandidate? declName eager | return none
  isInductivePredicate? declName

def validateCasesAttr (declName : Name) (eager : Bool) : CoreM Unit := do
  unless (← isCasesAttrCandidate declName eager) do
    if eager then
      throwError "invalid `[grind cases eager]`, `{declName}` is not a non-recursive inductive datatype or an alias for one"
    else
      throwError "invalid `[grind cases]`, `{declName}` is not an inductive datatype or an alias for one"

def addCasesAttr (declName : Name) (eager : Bool) (attrKind : AttributeKind) : CoreM Unit := do
  validateCasesAttr declName eager
  casesExt.add { declName, eager } attrKind

def CasesTypes.eraseDecl (s : CasesTypes) (declName : Name) : CoreM CasesTypes := do
  if s.contains declName then
    return s.erase declName
  else
    throwError "`{declName}` is not marked with the `[grind]` attribute"

def ensureNotBuiltinCases (declName : Name) : CoreM Unit := do
  if isBuiltinEagerCases declName then
    throwError "`{declName}` is marked as a built-in case-split for `grind` and cannot be erased"

def eraseCasesAttr (declName : Name) : CoreM Unit := do
  ensureNotBuiltinCases declName
  let s := casesExt.getState (← getEnv)
  let s ← s.eraseDecl declName
  modifyEnv fun env => casesExt.modifyState env fun _ => s

/--
We say a free variable is "simple" to be processed by the cases tactic IF:
- It is the latest and consequently there are no forward dependencies, OR
- It is not a proposition.
-/
private def isSimpleFVar (e : Expr) : MetaM Bool := do
  let .fvar fvarId := e | return false
  let decl ← fvarId.getDecl
  if decl.index == (← getLCtx).numIndices - 1 then
    -- It is the latest free variable, so there are no forward dependencies
    return true
  else
    -- It is pointless to add an auxiliary equality if `e`s type is a proposition
    isProp decl.type

/--
The `grind` tactic includes an auxiliary `cases` tactic that is not intended for direct use by users.
This method implements it.
This tactic is automatically applied when introducing local declarations with a type tagged with `[grind_cases]`.
It is also used for "case-splitting" on terms during the search.

It differs from the user-facing Lean `cases` tactic in the following ways:

- It avoids unnecessary `revert` and `intro` operations.

- It does not introduce new local declarations for each minor premise. Instead, the `grind` tactic preprocessor is responsible for introducing them.

- If the major premise type is an indexed family, auxiliary declarations and (heterogeneous) equalities are introduced.
  However, these equalities are not resolved using `unifyEqs`. Instead, the `grind` tactic employs union-find and
  congruence closure to process these auxiliary equalities. This approach avoids applying substitution to propositions
  that have already been internalized by `grind`.
-/
def cases (mvarId : MVarId) (e : Expr) : MetaM (List MVarId) := mvarId.withContext do
  let tag ← mvarId.getTag
  let type ← whnf (← inferType e)
  let .const declName _ := type.getAppFn | throwInductiveExpected type
  let .inductInfo _ ← getConstInfo declName | throwInductiveExpected type
  let recursorInfo ← mkRecursorInfo (mkCasesOnName declName)
  let k (mvarId : MVarId) (fvarId : FVarId) (indices : Array FVarId) : MetaM (List MVarId) := do
    let indicesExpr := indices.map mkFVar
    let recursor ← mkRecursorAppPrefix mvarId `grind.cases fvarId recursorInfo indicesExpr
    let lctx ← getLCtx
    let lctx := lctx.setKind fvarId .implDetail
    let lctx := indices.foldl (init := lctx) fun lctx fvarId => lctx.setKind fvarId .implDetail
    let localInsts ← getLocalInstances
    let mut recursor := mkApp (mkAppN recursor indicesExpr) (mkFVar fvarId)
    let mut recursorType ← inferType recursor
    let mut mvarIdsNew := #[]
    let mut idx := 1
    for _ in *...recursorInfo.numMinors do
      let .forallE _ targetNew recursorTypeNew _ ← whnf recursorType
        | throwTacticEx `grind.cases mvarId "unexpected recursor type"
      recursorType := recursorTypeNew
      let tagNew := if recursorInfo.numMinors > 1 then Name.num tag idx else tag
      let mvar ← mkFreshExprMVarAt lctx localInsts targetNew .syntheticOpaque tagNew
      recursor := mkApp recursor mvar
      mvarIdsNew := mvarIdsNew.push mvar.mvarId!
      idx := idx + 1
    mvarId.assign recursor
    return mvarIdsNew.toList
  if recursorInfo.numIndices > 0 then
    let s ← generalizeIndices' mvarId e
    s.mvarId.withContext do
      k s.mvarId s.fvarId s.indicesFVarIds
  else if (← isSimpleFVar e) then
    -- We don't need to revert anything.
    k mvarId e.fvarId! #[]
  else
    let mvarId ← if (← isProof e) then
      mvarId.assert (← mkFreshUserName `x) type e
    else
      mvarId.assertExt (← mkFreshUserName `x) type e
    let (fvarId, mvarId) ← mvarId.intro1
    mvarId.withContext do k mvarId fvarId #[]

where
  throwInductiveExpected {α} (type : Expr) : MetaM α := do
    throwTacticEx `grind.cases mvarId m!"(non-recursive) inductive type expected at {e}{indentExpr type}"

end Lean.Meta.Grind
