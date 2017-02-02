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


{-|
    Tagger for failed operations.
-}
type alias FailureTagger a msg =
    a -> msg


{-|
    Tagger to route back to this module.
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
type alias Config =
    { retryMax : Int
    , delayNext : Int -> Time
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
    | OperationFailed (RetryCmdTagger msg) msg
    | ReturnMsg msg


delayUpdateMsg : Msg msg -> Time -> Cmd (Msg msg)
delayUpdateMsg msg delay =
    Task.perform (\_ -> Nop) (\_ -> msg) <| Process.sleep delay



-- API


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
update : Config -> Msg msg -> Model msg -> ( ( Model msg, Cmd (Msg msg) ), List msg )
update config msg model =
    case msg of
        Nop ->
            ( model ! [], [] )

        ReturnMsg msg ->
            ( model ! [], [ msg ] )

        OperationFailed retryCmdTagger failureMsg ->
            (model.retryCount + 1 >= config.retryMax)
                ? ( ( model ! [], [ failureMsg ] )
                  , ( { model | retryCount = model.retryCount + 1 } ! [ delayUpdateMsg (ReturnMsg <| retryCmdTagger model.retryCount failureMsg model.cmd) <| config.delayNext model.retryCount ], [] )
                  )


{-|
    Constant delay.
-}
constantDelay : Int -> Int -> Time
constantDelay delay retryCount =
    toFloat <| delay


{-|
    Exponential delay base 2.
-}
exponentialDelay : Int -> Int -> Int -> Time
exponentialDelay delay maxDelay retryCount =
    toFloat <| min maxDelay <| delay * (2 ^ (retryCount - 1))


{-|
    Retry an operation.
-}
retry : Model msg -> RetryRouterTagger msg -> FailureTagger a msg -> RetryCmdTagger msg -> (FailureTagger a msg -> Cmd msg) -> ( Model msg, Cmd msg )
retry model router failureTagger retryCmdTagger cmdConstructor =
    let
        cmd =
            cmdConstructor interceptedFailureTagger

        -- splice retry command, i.e. msg << Msg msg << msg
        interceptedFailureTagger =
            router << OperationFailed retryCmdTagger << failureTagger
    in
        ( { model | retryCount = 1, cmd = cmd }, cmd )
