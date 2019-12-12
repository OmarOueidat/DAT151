module TypeChecker where

import Control.Applicative
import Control.Monad
import Control.Monad.Except
import Control.Monad.Reader
import Control.Monad.State

import Data.Functor
import Data.Maybe
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Set as Set


import CMM.Abs
import CMM.Print
import CMM.ErrM

import qualified Annotated as A
    
type Env = (Sig,[Context]) -- functions and context stack
type Sig = Map Id ([Type],Type) -- function type signature
type Context = Map Id Type -- variables with their types

data FunType = FunType Type [Type]

typecheck :: Program -> Err A.Program
typecheck (Prg prog) = do 
    let funcs = map getTypes prog
    env <- foldM (\env (id,typ) -> updateFun env id typ ) emptyEnv funcs
    isMain env
    list <- mapM (checkDef env) prog
    return PDefs list

builtIn :: [(Id, ([Type], Type))]
builtIn = [
  (Id "printInt", ([TInt], TVoid)),
  (Id "printDouble", ([TDouble], TVoid)),
  (Id "readInt", ([], TInt)),
  (Id "readDouble", ([], TDouble))
  ]

isMain :: Env -> Err ()
isMain env = 
        case lookupFun env (Id "main") of
            Ok ([], TInt) -> return ()
            _ -> Bad "No function main"

            


inferExp :: Env -> Exp -> Err Type  
inferExp env exp = case exp of
                    EInt int -> Ok TInt
                    EDouble doub -> Ok TDouble
                    ETrue -> Ok TBool
                    EFalse -> Ok TBool
                    EId id -> lookupVar env id
                    ECall id argExps -> do 
                                        (argsTypes,typ) <- lookupFun env id
                                        expTypes <- mapM (\exp -> inferExp env exp) argExps
                                        if argsTypes == expTypes then --and ls then
                                            return typ
                                        else
                                            Bad "Function has wrong argument types"
                    EInc id -> do
                                typ <- lookupVar env id
                                if typ `elem` [TInt,TDouble] then
                                    return typ
                                    else
                                        Bad $ "Id " ++ printTree id ++ " has wrong type"
                    EDec id -> do
                            typ <- lookupVar env id
                            if typ `elem` [TInt,TDouble] then
                                return typ
                            else
                                Bad $ "Id " ++ printTree id ++ " has wrong type"
                    EInc2 id ->  do
                            typ <- lookupVar env id
                            if typ `elem` [TInt,TDouble] then
                                return typ
                            else
                                Bad $ "Id " ++ printTree id ++ " has wrong type"
                    EDec2 id ->  do
                            typ <- lookupVar env id
                            if typ `elem` [TInt,TDouble] then
                                return typ
                            else
                                Bad $ "Id " ++ printTree id ++ " has wrong type"
                    EMul exp1 exp2 -> inferBin env exp1 exp2
                    EDiv exp1 exp2 -> inferBin env exp1 exp2
                    EAdd exp1 exp2 -> inferBin env exp1 exp2
                    ESub exp1 exp2 -> inferBin env exp1 exp2
                    ELess exp1 exp2 -> do
                        inferBin env exp1 exp2           
                        return TBool
                    EGre exp1 exp2 -> do
                        inferBin env exp1 exp2           
                        return TBool
                    ELeq exp1 exp2 ->do
                        inferBin env exp1 exp2           
                        return TBool
                    EGeq exp1 exp2 ->do
                        inferBin env exp1 exp2           
                        return TBool 
                    EEqua exp1 exp2 -> do
                        typ1 <- inferExp env exp1     
                        typ2 <- inferExp env exp2
                        if (isValidType typ1 typ2) then return TBool
                        else
                            Bad "Not equal expressions equal"
                    EIneq exp1 exp2 -> do
                        typ1 <- inferExp env exp1     
                        typ2 <- inferExp env exp2
                        if (isValidType typ1 typ2) then return TBool
                        else
                            Bad "Not equal expressions inequal"
                    EConj exp1 exp2 -> do
                        typ1 <- inferExp env exp1     
                        typ2 <- inferExp env exp2
                        if typ1 == typ2  && typ1 == TBool then return TBool
                        else
                            Bad "Not equal expressions conj"
                    EDisj exp1 exp2 -> do
                        typ1 <- inferExp env exp1     
                        typ2 <- inferExp env exp2
                        if typ1 == typ2  && typ1 == TBool then return TBool
                        else
                            Bad "Not equal expressions disj"
                    EAss id exp -> do
                                varTyp <- lookupVar env id
                                expTyp <- inferExp env exp
                                if isValidAss varTyp expTyp then return varTyp
                                else Bad "Not correct assignemnt" 
                    --ETyped exp typ -> case checkExp env typ exp of
                      --                  Ok _ -> Ok typ
                        --                Bad s -> Bad s

isBad :: Err a -> Bool
isBad (Bad _) = True
isBad _ = False

isValidArgs :: [Type] -> [Type] -> Bool
isValidArgs (typ1:[]) (typ2:[]) = isValidAss typ1 typ2
isValidArgs (typ1:xs) (typ2:ys) = if isValidAss typ1 typ2 then isValidArgs xs ys else False

isValidAss :: Type -> Type -> Bool
isValidAss TDouble TInt = True
isValidAss typ1 typ2 = typ1 == typ2

isValidType :: Type -> Type -> Bool
isValidType TInt TDouble = True
isValidType TDouble TInt = True
isValidType typ1 typ2 = typ1 == typ2 && typ1 /= TVoid

inferBin :: Env -> Exp -> Exp -> Err Type
inferBin env exp1 exp2 = case inferExp env exp1 of
                            Ok TInt -> case inferExp env exp2 of
                                Ok TInt -> Ok TInt
                                Ok TDouble -> Ok TDouble
                                _ -> Bad "Bad type"
                            Ok TDouble -> case inferExp env exp2 of
                                Ok TInt -> Ok TDouble
                                Ok TDouble -> Ok TDouble
                                _ -> Bad "Bad type"
                            _ -> Bad "Bad type"

checkExp :: Env -> Type -> Exp -> Err ()
checkExp env typ exp = do
    expTyp <- inferExp env exp
    if expTyp == typ then
        return ()
        else
        Bad $ "type of " ++ printTree exp ++
               "expected " ++ printTree typ ++
               "but found " ++ printTree expTyp




checkStm :: Type -> Env -> Stm -> Err (Env, A.Stm)
checkStm retTyp env stm =
                    case stm of 
                        SExp exp -> do
                            typ <- inferExp env exp
                            return (env, A.SExp typ exp)
                        SDecls typ ids -> do
                                env' <- foldM (\newEnv id -> updateVar newEnv id typ) env ids
                                return (env', A.SDecls typ ids)               
                        SInit typ id exp -> do
                            newEnv <- updateVar env id typ
                            expTyp <- inferExp newEnv exp
                            if isValidAss typ expTyp then return (newEnv, A.SInit typ id exp)
                            else Bad "Types doesn't match"
                        SRet exp -> do
                            typ <- inferExp env exp
                            if typ == retTyp then return (env, A.SRet typ exp)
                            else Bad "Return type does not match"
                        SWhile exp stm' -> do
                                let newEnv = newBlock env
                                checkExp newEnv TBool exp
                                (env', stm'') <- checkStm retTyp newEnv stm'
                                -- maybe env'
                                return (env, A.SWhile exp stm'')
                        SIf exp stm1 stm2 -> do 
                                    let newEnv = newBlock env
                                    checkExp env TBool exp
                                     (env', stm1')<-  checkStm retTyp newEnv stm1
                                     (env'',stm2') <- checkStm retTyp newEnv stm2
                                     -- maybe env'' (?)
                                    return (env, A.SIf exp stm1' stm2')
                        SBlock stmxs -> do
                                    let newEnv = newBlock env
                                     (env, stms') <- checkStms retTyp (newBlock env) stmxs
                                     return (env, A.SBlock stms')


checkStms :: Type -> Env ->  [Stm] -> Err (Env, [A.Stm])
checkStms typ env [] = return (env, [])
checkStms typ env stm:stms = do 
    (env', astm) <- checkStm typ env stm
    (env'', astms) <- checkStms typ env' stms
    return (env'', astm:astms)

checkDef :: Env -> Func -> Err A.Func
checkDef env func@(FDef typ id (FArgument args) (FBody stms)) = do
                    newEnv <- foldM (\env (FArgs typ id) -> updateVar env id typ) (newBlock env) args
                    let (env, astms') = checkStms typ newEnv stms                              
                    return PDef typ id args astms'

getTypes :: Func -> (Id, ([Type],Type))
getTypes (FDef typ id (FArgument args) body) = (id, ( (map (\(FArgs typ _) -> typ) args ),typ))

lookupVar :: Env -> Id -> Err Type
lookupVar (_, []) (Id id) = Bad $  "Variable does not exist " ++ printTree id
lookupVar env@(sig,top:stack) id = case Map.lookup id top of
                                    Nothing -> lookupVar (sig,stack) id
                                    Just typ -> return typ           

lookupFun :: Env -> Id -> Err ([Type],Type)
lookupFun (sig, _) id = 
            case Map.lookup id sig of
                Just pair -> Ok pair
                Nothing -> Bad "No function found"

updateVar :: Env -> Id -> Type -> Err Env
updateVar _ _ TVoid = Bad "Can not assign variable as void"
updateVar (sig, top:stack) id typ = 
            case Map.lookup id top of
                Nothing-> do
                    let newStack = Map.insert id typ top 
                    Ok (sig, newStack:stack)
                Just id -> Bad $ "Already in environment" ++ printTree id
                --Ok _ -> Ok (sig, top:stack)

updateFun :: Env -> Id -> ([Type],Type) -> Err Env
updateFun env@(sig, stack) id funcTypes = 
            case lookupFun env id of
                Bad _ -> Ok (Map.insert id funcTypes sig, stack)
                Ok _ -> Bad $ "Function already exists " ++ printTree id

newBlock :: Env -> Env
newBlock (sig, stack) = (sig, Map.empty:stack)

emptyEnv :: Env
emptyEnv = (Map.fromList builtIn, [Map.empty])