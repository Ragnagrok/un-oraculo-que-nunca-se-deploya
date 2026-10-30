{-# OPTIONS_GHC -Wno-orphans #-}
-- | Lockstep: the same random sequence goes to the model and to the real
-- system over HTTP, and the answers have to match one by one.
module Main (main) where

import qualified Data.ByteString.Lazy.Char8 as BL
import Network.HTTP.Client (Manager, defaultManagerSettings, httpLbs, newManager, parseRequest, responseBody)
import Control.Monad (unless)
import System.Environment (lookupEnv)
import System.Exit (exitFailure)
import Test.QuickCheck
import Test.QuickCheck.Monadic

import Model

instance Arbitrary Command where
  arbitrary = oneof
    [ Sell <$> chooseInt (1, 100)
    , Redeem <$> chooseInt (1, 100)
    , pure Reverse
    , pure Expire
    , pure Balance
    ]
  shrink (Sell n)   = Sell <$> filter (> 0) (shrink n)
  shrink (Redeem n) = Redeem <$> filter (> 0) (shrink n)
  shrink _          = []

-- | The adapter: one command, one HTTP request.
send :: Manager -> String -> Command -> IO Response
send http base cmd = do
  req <- parseRequest (base ++ path cmd)
  read . BL.unpack . responseBody <$> httpLbs req http
  where
    path (Sell n)   = "/sell?amount=" ++ show n
    path (Redeem n) = "/redeem?amount=" ++ show n
    path Reverse    = "/reverse"
    path Expire     = "/expire"
    path Balance    = "/balance"

prop_agrees :: Manager -> String -> [Command] -> Property
prop_agrees http base cmds = monadicIO $ do
  run (reset http base)
  actual <- run (mapM (send http base) cmds)
  let expected = responses cmds
  monitor (counterexample (report cmds expected actual))
  assert (actual == expected)

reset :: Manager -> String -> IO ()
reset http base = do
  req <- parseRequest (base ++ "/reset")
  _ <- httpLbs req http
  pure ()

report :: [Command] -> [Response] -> [Response] -> String
report cmds expected actual = unlines $
  (pad 14 "command" ++ pad 20 "model" ++ "system") :
  [ pad 14 (show c) ++ pad 20 (show e) ++ show a ++ mark e a
  | (c, e, a) <- zip3 cmds expected actual ]
  where
    pad n s = take n (s ++ repeat ' ')
    mark e a = if e == a then "" else "   <--"

main :: IO ()
main = do
  base <- maybe "http://localhost:8080" id <$> lookupEnv "SUT"
  http <- newManager defaultManagerSettings
  result <- quickCheckWithResult stdArgs { maxSuccess = 1000 } (prop_agrees http base)
  unless (isSuccess result) exitFailure
