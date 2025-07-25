/-
Copyright (c) 2024 Lean FRO, LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Henrik Böving
-/
module

prelude
public import Std.Tactic.BVDecide.LRAT.Checker
public import Std.Tactic.BVDecide.LRAT.Parser
public import Std.Tactic.BVDecide.Bitblast
public import Std.Sat.AIG.CNF
public import Std.Sat.AIG.RelabelNat

@[expose] public section

/-!
This file contains theorems used for justifying the reflection procedure of `bv_decide`.
-/

namespace Std.Tactic.BVDecide

namespace Reflect

namespace BitVec

theorem and_congr (w : Nat) (lhs rhs lhs' rhs' : BitVec w) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    lhs' &&& rhs' = lhs &&& rhs := by
  simp[*]

theorem or_congr (w : Nat) (lhs rhs lhs' rhs' : BitVec w) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    lhs' ||| rhs' = lhs ||| rhs := by
  simp[*]

theorem xor_congr (w : Nat) (lhs rhs lhs' rhs' : BitVec w) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    lhs' ^^^ rhs' = lhs ^^^ rhs := by
  simp[*]

theorem not_congr (w : Nat) (x x' : BitVec w) (h : x = x') : ~~~x' = ~~~x := by
  simp[*]

theorem shiftLeft_congr (m n : Nat) (lhs : BitVec m) (rhs : BitVec n) (lhs' : BitVec m)
    (rhs' : BitVec n) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    lhs <<< rhs = lhs' <<< rhs' := by
  simp[*]

theorem shiftRight_congr (m n : Nat) (lhs : BitVec m) (rhs : BitVec n) (lhs' : BitVec m)
    (rhs' : BitVec n) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    lhs >>> rhs = lhs' >>> rhs' := by
  simp[*]

theorem arithShiftRightNat_congr (n : Nat) (w : Nat) (x x' : BitVec w) (h : x = x') :
    BitVec.sshiftRight x' n = BitVec.sshiftRight x n := by
  simp[*]

theorem arithShiftRight_congr (m n : Nat) (lhs : BitVec m) (rhs : BitVec n) (lhs' : BitVec m)
    (rhs' : BitVec n) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    BitVec.sshiftRight' lhs rhs = BitVec.sshiftRight' lhs' rhs' := by
  simp[*]

theorem add_congr (w : Nat) (lhs rhs lhs' rhs' : BitVec w) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    lhs' + rhs' = lhs + rhs := by
  simp[*]

theorem append_congr (lw rw : Nat) (lhs lhs' : BitVec lw) (rhs rhs' : BitVec rw) (h1 : lhs' = lhs)
    (h2 : rhs' = rhs) :
    lhs' ++ rhs' = lhs ++ rhs := by
  simp[*]

theorem replicate_congr (n : Nat) (w : Nat) (expr expr' : BitVec w) (h : expr' = expr) :
    BitVec.replicate n expr' = BitVec.replicate n expr := by
  simp[*]

theorem extract_congr (start len : Nat) (w : Nat) (x x' : BitVec w) (h1 : x = x') :
    BitVec.extractLsb' start len x' = BitVec.extractLsb' start len x := by
  simp[*]

theorem rotateLeft_congr (n : Nat) (w : Nat) (x x' : BitVec w) (h : x = x') :
    BitVec.rotateLeft x' n = BitVec.rotateLeft x n := by
  simp[*]

theorem rotateRight_congr (n : Nat) (w : Nat) (x x' : BitVec w) (h : x = x') :
    BitVec.rotateRight x' n = BitVec.rotateRight x n := by
  simp[*]

theorem mul_congr (w : Nat) (lhs rhs lhs' rhs' : BitVec w) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    lhs' * rhs' = lhs * rhs := by
  simp[*]

theorem beq_congr (lhs rhs lhs' rhs' : BitVec w) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    (lhs' == rhs') = (lhs == rhs) := by
  simp[*]

theorem ult_congr (lhs rhs lhs' rhs' : BitVec w) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    (BitVec.ult lhs' rhs') = (BitVec.ult lhs rhs) := by
  simp[*]

theorem getLsbD_congr (i : Nat) (w : Nat) (e e' : BitVec w) (h : e' = e) :
    (e'.getLsbD i) = (e.getLsbD i) := by
  simp[*]

theorem ofBool_congr (b : Bool) (e' : BitVec 1) (h : e' = BitVec.ofBool b) : e'.getLsbD 0 = b := by
  cases b <;> simp [h]

theorem udiv_congr (lhs rhs lhs' rhs' : BitVec w) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    (lhs' / rhs') = (lhs / rhs) := by
  simp[*]

theorem umod_congr (lhs rhs lhs' rhs' : BitVec w) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    (lhs' % rhs') = (lhs % rhs) := by
  simp[*]

theorem cond_true (discr : Bool) (lhs rhs : BitVec w) :
    (!discr || ((bif discr then lhs else rhs) == lhs)) = true := by
  cases discr <;> simp

theorem cond_false (discr : Bool) (lhs rhs : BitVec w) :
    (discr || ((bif discr then lhs else rhs) == rhs)) = true := by
  cases discr <;> simp

theorem reverse_congr (w : Nat) (x x' : BitVec w) (h : x = x') :
    BitVec.reverse x' = BitVec.reverse x := by
  simp[*]

theorem clz_congr (w : Nat) (x x' : BitVec w) (h : x = x') :
    BitVec.clz x' = BitVec.clz x := by
  simp [*]

end BitVec

namespace Bool

theorem not_congr (x x' : Bool) (h : x' = x) : (!x') = (!x) := by
  simp[*]

theorem and_congr (lhs rhs lhs' rhs' : Bool) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    (lhs' && rhs') = (lhs && rhs) := by
  simp[*]

theorem xor_congr (lhs rhs lhs' rhs' : Bool) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    (lhs' ^^ rhs') = (lhs ^^ rhs) := by
  simp[*]

theorem beq_congr (lhs rhs lhs' rhs' : Bool) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    (lhs' == rhs') = (lhs == rhs) := by
  simp[*]

theorem or_congr (lhs rhs lhs' rhs' : Bool) (h1 : lhs' = lhs) (h2 : rhs' = rhs) :
    (lhs' || rhs') = (lhs || rhs) := by
  simp[*]

theorem cond_congr (discr lhs rhs discr' lhs' rhs' : Bool) (h1 : discr' = discr) (h2 : lhs' = lhs)
    (h3 : rhs' = rhs) :
    (bif discr' then lhs' else rhs') = (bif discr then lhs else rhs) := by
  simp[*]

theorem false_of_eq_true_of_eq_false (h₁ : x = true) (h₂ : x = false) : False := by
  cases h₁; cases h₂

theorem lemma_congr (x x' : Bool) (h1 : x' = x) (h2 : x = true) : x' = true := by
  simp[*]

end Bool

open Std.Sat

/--
Verify that a proof certificate is valid for a given formula.
-/
def verifyCert (cnf : CNF Nat) (cert : String) : Bool :=
  match LRAT.parseLRATProof cert.toUTF8 with
  | .ok lratProof => LRAT.check lratProof cnf
  | .error _ => false

theorem verifyCert_correct : ∀ cnf cert, verifyCert cnf cert = true → cnf.Unsat := by
  intro c b h1
  unfold verifyCert at h1
  split at h1
  . apply LRAT.check_sound
    assumption
  . contradiction

/--
Verify that `cert` is an UNSAT proof for the SAT problem obtained by bitblasting `bv`.
-/
def verifyBVExpr (bv : BVLogicalExpr) (cert : String) : Bool :=
  verifyCert (AIG.toCNF bv.bitblast.relabelNat) cert

theorem unsat_of_verifyBVExpr_eq_true (bv : BVLogicalExpr) (c : String)
    (h : verifyBVExpr bv c = true) :
    bv.Unsat := by
  apply BVLogicalExpr.unsat_of_bitblast
  rw [← AIG.Entrypoint.relabelNat_unsat_iff]
  rw [← AIG.toCNF_equisat]
  apply verifyCert_correct
  rw [verifyBVExpr] at h
  assumption

end Reflect

end Std.Tactic.BVDecide
