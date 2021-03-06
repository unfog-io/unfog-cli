module Main where

import qualified System.Environment as Env
import qualified Unfog.Arg.Parser as Arg (parse)
import Unfog.Arg.Types (Arg (CommandArg, ProcedureArg, QueryArg))
import qualified Unfog.Command.Handler as Command (handle)
import qualified Unfog.Procedure.Handler as Procedure (handle)
import qualified Unfog.Query.Handler as Query (handle)

main :: IO ()
main = dispatch =<< Arg.parse =<< Env.getArgs
  where
    dispatch (CommandArg arg) = Command.handle arg
    dispatch (ProcedureArg arg) = Procedure.handle arg
    dispatch (QueryArg arg) = Query.handle arg
