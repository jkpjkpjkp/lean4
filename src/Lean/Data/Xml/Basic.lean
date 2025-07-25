/-
Copyright (c) 2021 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Dany Fabian
-/
prelude
import Init.Data.ToString.Macro
import Std.Data.TreeMap.Basic

namespace Lean
namespace Xml

def Attributes := Std.TreeMap String String
instance : ToString Attributes := ⟨λ as => as.foldl (λ s n v => s ++ s!" {n}=\"{v}\"") ""⟩

mutual
inductive Element
| Element
  (name : String)
  (attributes : Attributes)
  (content : Array Content)

inductive Content
| Element (element : Element)
| Comment (comment : String)
| Character (content : String)
deriving Inhabited
end

mutual
private partial def eToString : Element → String
| Element.Element n a c => s!"<{n}{a}>{c.map cToString |>.foldl (· ++ ·) ""}</{n}>"

private partial def cToString : Content → String
| Content.Element e => eToString e
| Content.Comment c => s!"<!--{c}-->"
| Content.Character c => c

end
instance : ToString Element := ⟨eToString⟩
instance : ToString Content := ⟨cToString⟩
