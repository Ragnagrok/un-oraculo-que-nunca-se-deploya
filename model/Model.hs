-- | The model of a gift card. It never runs in production: its only job is to
-- say what the real system should answer.
module Model
  ( Status (..)
  , Card (..)
  , Command (..)
  , Response (..)
  , initial
  , step
  , responses
  ) where

data Status = Available | Sold | Expired
  deriving (Eq, Show)

data Card = Card
  { status   :: Status
  , balance  :: Int
  , redeemed :: [Int]  -- redemptions not yet reversed, most recent first
  }
  deriving (Eq, Show)

data Command = Sell Int | Redeem Int | Reverse | Expire | Balance
  deriving (Eq, Show, Read)

data Response
  = Ok
  | Funds Int
  | Insufficient
  | NotSold
  | AlreadySold
  | IsExpired
  | NothingToReverse
  deriving (Eq, Show, Read)

initial :: Card
initial = Card { status = Available, balance = 0, redeemed = [] }

step :: Command -> Card -> (Response, Card)
step cmd card = case (cmd, status card) of
  (Balance, _) -> (Funds (balance card), card)

  (Sell n, Available) -> (Ok, card { status = Sold, balance = n })
  (Sell _, _)         -> (AlreadySold, card)

  (Redeem n, Sold)
    | n > balance card -> (Insufficient, card)
    | otherwise        -> (Ok, card { balance = balance card - n
                                    , redeemed = n : redeemed card })

  (Reverse, Sold) -> case redeemed card of
    n : rest -> (Ok, card { balance = balance card + n, redeemed = rest })
    []       -> (NothingToReverse, card)

  (Expire, Sold) -> (Ok, card { status = Expired })

  (_, Available) -> (NotSold, card)
  (_, Expired)   -> (IsExpired, card)

-- | What the model answers to a whole sequence, starting from a new card.
responses :: [Command] -> [Response]
responses = go initial
  where
    go _ [] = []
    go card (c : cs) = let (r, card') = step c card in r : go card' cs
