module Retry
    exposing
        ( FailureTagger
        , RetryRouterTagger
        , RetryCmdTagger
        , Config
        , Msg
        , Model
        , initModel
        , update
        , constantDelay
        , exponentialDelay
        , retry
        )

{-|
    Generic Retry Mechanism.

@docs FailureTagger, RetryRouterTagger, RetryCmdTagger, Config, Msg, Model, initModel, update, constantDelay, exponentialDelay, retry
-}

import Task
import Process
import Time exposing (Time)
import Utils.Ops exposing ((?))


delayUpdateMsg : Msg msg -> Time -> Cmd (Msg msg)
delayUpdateMsg msg delay =
    Task.perform (\_ -> Nop) (\_ -> msg) <| Process.sleep delay



-- API


{-|
    Tagger for failed operations.
-}
type alias FailureTagger a msg =
    a -> msg


{-|
    Tagger to route back to Retry module.
-}
type alias RetryRouterTagger msg =
    Msg msg -> msg


{-|
    Tagger for parent to retry original command.
-}
type alias RetryCmdTagger msg =
    Int -> msg -> Cmd msg -> msg


{-|
    Retry Config.
-}
type alias Config msg =
    { retryMax : Int
    , delayNext : Int -> Time
    , routeToMeTagger : RetryRouterTagger msg
    }


{-|
    Retry Model.
-}
type alias Model msg =
    { cmd : Cmd msg
    , retryCount : Int
    }


{-|
    Retry Msgs.
-}
type Msg msg
    = Nop
    | CmdFailed (RetryCmdTagger msg) msg
    | ReturnMsg msg


{-|
    Create an initial model.
-}
initModel : Model msg
initModel =
    { cmd = Cmd.none
    , retryCount = 1
    }


{-|
    Retry Update.
-}
update : Config msg -> Msg msg -> Model msg -> ( ( Model msg, Cmd (Msg msg) ), List msg )
update config msg model =
    case msg of
        Nop ->
            ( model ! [], [] )

        ReturnMsg msg ->
            ( model ! [], [ msg ] )

        CmdFailed retryCmdTagger failureMsg ->
            (model.retryCount > config.retryMax)
                ? ( ( model ! [], [ failureMsg ] )
                  , ( { model | retryCount = model.retryCount + 1 } ! [ delayUpdateMsg (ReturnMsg <| retryCmdTagger model.retryCount failureMsg model.cmd) <| config.delayNext model.retryCount ], [] )
                  )


{-|
    Constant delay.
-}
constantDelay : Int -> Int -> Time
constantDelay delay _ =
    toFloat <| delay


{-|
    Exponential delay base 2.
-}
exponentialDelay : Int -> Int -> Int -> Time
exponentialDelay delay maxDelay retryCount =
    toFloat <| min maxDelay <| delay * (2 ^ (retryCount - 1))


{-|
    Retry a Cmd.
-}
retry : Config msg -> Model msg -> FailureTagger a msg -> RetryCmdTagger msg -> (FailureTagger a msg -> Cmd msg) -> ( Model msg, Cmd msg )
retry config model failureTagger retryCmdTagger cmdConstructor =
    let
        cmd =
            cmdConstructor interceptedFailureTagger

        -- splice retry command, i.e. msg << Msg msg << msg
        interceptedFailureTagger =
            config.routeToMeTagger << CmdFailed retryCmdTagger << failureTagger
    in
        ( { model | retryCount = 1, cmd = cmd }, cmd )
