-- Haskell data types for the abstract syntax.
-- Generated by the BNF converter.

module CMM.Abs where

data Program = PDefs [Def]
  deriving (Eq, Ord, Show, Read)

data Def = DFun
  deriving (Eq, Ord, Show, Read)
