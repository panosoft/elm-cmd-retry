module Retry
    exposing
        ( FailureTagger
        , RetryRouterTagger
        , RetryCmdTagger
        , Config
        , Msg
        , Model
        , update
        , constantDelay
        , exponentialDelay
        , retry
        )

{-|
    Generic Retry Mechanism.

@docs FailureTagger, RetryRouterTagger, RetryCmdTagger, Config, Msg, Model, update, constantDelay, exponentialDelay, retry
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
    Cmd msg -> msg


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
type alias Model =
    {}


{-|
    Retry Msgs.
-}
type Msg msg
    = Nop
    | OperationFailed (RetryCmdTagger msg) (Cmd msg) Int msg
    | ReturnMsg msg


delayUpdateMsg : Msg msg -> Time -> Cmd (Msg msg)
delayUpdateMsg msg delay =
    Task.perform (\_ -> Nop) (\_ -> msg) <| Process.sleep delay


{-|
    Retry Update.
-}
update : Config -> Model -> Msg msg -> ( ( Model, Cmd (Msg msg) ), List msg )
update config model msg =
    case msg of
        Nop ->
            ( model ! [], [] )

        ReturnMsg msg ->
            ( model ! [], [ msg ] )

        OperationFailed retryCmdTagger cmd retryCount failureMsg ->
            (retryCount + 1 >= config.retryMax)
                ? ( ( model ! [], [ failureMsg ] )
                  , ( model ! [ delayUpdateMsg (ReturnMsg <| retryCmdTagger cmd) <| config.delayNext retryCount ], [] )
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
retry : RetryRouterTagger msg -> FailureTagger a msg -> RetryCmdTagger msg -> (FailureTagger a msg -> Cmd msg) -> Cmd msg
retry router failureTagger retryCmdTagger cmdConstructor =
    let
        cmd =
            cmdConstructor interceptedFailureTagger

        -- splice retry command, i.e. msg << Msg msg << msg
        interceptedFailureTagger =
            router << OperationFailed retryCmdTagger cmd 1 << failureTagger
    in
        cmd
