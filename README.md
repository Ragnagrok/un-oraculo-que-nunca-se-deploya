# An Oracle That Never Ships

Proof of concept for the article *An Oracle That Never Ships*
([English](https://blog.ragnagrok.com/en/2026-10-30-un-oraculo-que-nunca-se-deploya) ·
[español](https://blog.ragnagrok.com/es/2026-10-30-un-oraculo-que-nunca-se-deploya)):
a small model of a gift card, written in Haskell, used **only** as a test oracle for a system
written in PHP. The model never runs in production.

The idea in one line: generate a random sequence of commands, send it to the model and to the
real system over HTTP, and compare the answers one by one. That's called *lockstep testing*.

## What's here

| File | What it is |
|---|---|
| `model/Model.hs` | The model: a card is `Available`, `Sold` or `Expired`, and `step` says what each command answers. About forty lines. |
| `test/Lockstep.hs` | The comparison: a QuickCheck generator of commands, the HTTP adapter, and the property "the system answers what the model answers". |
| `app/index.php`, `app/schema.sql` | The "real system": a toy service in plain PHP and SQLite, the size of a controller. It has **two bugs on purpose**. |
| `fixes/*.diff` | The two fixes, in the order the test asks for them. |
| `check.sh` | Replays the whole story on a copy of the app. |

## The story `check.sh` replays

**First run.** QuickCheck finds a disagreement and shrinks it to three commands:

```
[Sell 1,Expire,Reverse]
command       model               system
Sell 1        Ok                  Ok
Expire        Ok                  Ok
Reverse       IsExpired           NothingToReverse   <--
```

This one isn't really a bug: nobody had decided what reversing a redemption on an expired card
means. The model had to say something (it says: an expired card isn't touched); the PHP code
said something else without anyone noticing. `fixes/1-expired-cards.diff` makes the app follow
the model's decision.

**Second run.** Now it's a real bug, shrunk to four commands:

```
[Sell 1,Redeem 1,Reverse,Reverse]
command       model               system
Sell 1        Ok                  Ok
Redeem 1      Ok                  Ok
Reverse       Ok                  Ok
Reverse       NothingToReverse    Ok   <--
```

The app reverses the last redemption without checking whether it was already reversed, so the
same money comes back twice. `fixes/2-double-reverse.diff` fixes it.

**Third run.** `+++ OK, passed 1000 tests.` About forty seconds over HTTP on a laptop.

## Running it

With GHC 9.12, cabal and PHP 8 with `pdo_sqlite`:

```sh
./check.sh                          # the whole story, on a temporary copy of the app

php -S localhost:8080 app/index.php # or by hand: start the app...
cabal test --test-show-details=direct   # ...and run the lockstep test against it
```

## What this proof of concept doesn't cover

It's a toy, on purpose. The article has the details; in short:

- **One card, one client, one request at a time.** Lockstep testing as done here is sequential.
  Two branches redeeming the same code at the same time need a parallel phase with a
  linearizability check, which tools like
  [quickcheck-state-machine](https://hackage.haskell.org/package/quickcheck-state-machine)
  provide.
- **No library.** The comparison is written by hand with plain QuickCheck so that it reads in one
  screen. For a real system,
  [quickcheck-lockstep](https://hackage.haskell.org/package/quickcheck-lockstep) gives you the
  machinery (references to created objects, observability, labelling).
- **The bugs were planted.** They are the kind that shows up in real systems, but here I know
  where they are.

## Further reading

- Hughes (2016), *Experiences with QuickCheck: Testing the Hard Stuff and Staying Sane*: the Volvo
  and Klarna stories.
- Arts, Hughes, Norell and Svensson (2015), *Testing AUTOSAR software with QuickCheck*.
- Claessen and Hughes (2000), *QuickCheck: A Lightweight Tool for Random Testing of Haskell
  Programs*.
