# Cmd Retry Mechanism

> A general retry mechanism for retrying Cmds that send failure messages as part of their API.

## Install

### Elm

Since the Elm Package Manager doesn't allow for Native code and most everything we write at Panoramic Software has some native code in it,
you have to install this library directly from GitHub, e.g. via [elm-github-install](https://github.com/gdotdesign/elm-github-install) or some equivalent mechanism. It's just not worth the hassle of putting libraries into the Elm package manager until it allows native code.

## Usage

Effects Managers that send both `Success` and `Failure` messages such as [elm-postgres](https://github.com/panosoft/elm-postgres), [elm-websocket-browser](https://github.com/panosoft/elm-websocket-browser) or [elm-websocket-server](https://github.com/panosoft/elm-websocket-server) can be used with this library to retry async operations that return retriable errors.

The requirement is that the failed Effect will send a `Failure` message to the App. If an Effect Manager does this, then this library can be used with it.

Another obvious requirement is that the Effect has to be retriable. So in the above examples, connecting to a DB, connecting to a Web Socket Server or Sending a message to a Web Socket Client all are retriable operations.

## Example

Here's an example of connecting to a Postgres DB. N.B. this example code uses [elm-parent-child-update](https:/github.com/panosoft/elm-parent-child-update).

```elm
import ParentChildUpdate exposing (..)
import Retry exposing (..)
import Postgres exposing (..)

type alias DbConnectionInfo =
    { host : String
    , port_ : Int
    , database : String
    , user : String
    , password : String
    , timeout : Int
    }

connectionInfo : DbConnectionInfo
connectionInfo =
	{ host = "server"
	, port_ = "5432"
	, database = "testDB"
	, user = "user"
	, password = "password"
	, timeout = 5000
	}

type alias Model =
    { retryModel : Retry.Model Msg
    }

type Msg
    = Nop
	| Connect ConnectionId
	| ConnectError ( ConncectionId, String )
    | RetryCmd Int Msg (Cmd Msg)
    | RetryModule (Retry.Msg Msg)

retryConfig : Retry.Config
retryConfig =
    { retryMax = 3
    , delayNext = Retry.constantDelay 5000
    }


init : ( Model, Cmd Msg )
init =
	{ retryModel = Retry.initModel } ! [ Retry.retry model.retryModel RetryModule ConnectError RetryCmd (connectCmd connectionInfo) ]

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
	let
		updateRetry =
			ParentChildUpdate.updateChildParent (Retry.update retryConfig) update .retryModel RetryModule (\model retryModel -> { model | retryModel = retryModel })
	in
		case msg of
			Connect connectionId ->
				let
					log =
						Debug.log "Connected to DB, connectionId: " ++ (toString connectionId)
				in
					model ! []
			ConnectionLost ( connectionId, error ) ->
				Debug.crash "We've lost our connection: " ++ error ++ " for connectionId: " ++ (toString connectionId)

			ConnectError ( connectionId, error ) ->
				Debug.crash <| "After retrying " ++ (toString retryConfig.retryMax) ++ "times we could not connect to DB: " ++ error ++ " for connectionId: " ++ (toString connectionId)

			RetryCmd retryCount failureMsg cmd ->
				let
					(connectionId, error) =
						case failureMsg of
							ConnectError errorInfo ->
								errorInfo

							_ -> Debug.crash "BUG -- Should never get here"

					log =
						Debug.log <| "Unable to connect to DB: " ++ error ++ " for connectionId: " ++ (toString connectionId) ++ " Retry: " ++ (toString retryCount)
				in
					model ! [cmd]

			RetryModule msg model ->
				updateRetry msg model

connectCmd : DbConnectionInfo -> FailureTagger ( ConnectionId, String ) Msg -> Cmd Msg
connectCmd connectionInfo failureTagger =
    Postgres.connect failureTagger
        (Connect commandId)
        (ConnectionLost commandId)
        connectionInfo.timeout
        connectionInfo.host
        connectionInfo.port_
        connectionInfo.database
        connectionInfo.user
        connectionInfo.password

```

#### Model

The `Retry` module needs a model and this model needs to be maintained by its Parent.

#### Retry.Config

The `Retry` module needs a config and this must be passed to its `update` function by its Parent. This can be seen in `updateRetry` in the above [example](#example).

#### init

Here the `retryModel` is initalized by calling Retry's `initModel`. And then a Postgres connection Cmd is built using `connectCmd` and passed to `Retry.retry`.

#### update

There are 3 parts here that involve the Retrying Process:

1. `updateRetry` - This is the Parent/Child communication wiring (see [elm-parent-child-update](https:/github.com/panosoft/elm-parent-child-update))
2. `RetryCmd` handling in `update` - This destructures the `failureMsg` from the Effects Manager and logs out the error info along with the `retryCount`. Then it returns the original `Cmd Msg`, i.e. `cmd` that was run to try again.
3. `RetryModule` - This is the other part of the Parent/Child communication.

## API

A Note on the term `Taggers`:

Taggers is a term that is used in Elm's codebase (in Effects Managers). It's effectively a `Msg Constructor function`.

### Types

In the following type annotations, `Msg` is Retry's Msg and `msg` is the Parent's Msg.

#### FailureTagger

Tagger for failed operations.

```elm
type alias FailureTagger a msg =
	a -> msg
```

This is the Tagger for an API call to an Effects Manager that will take a SINGLE error parameter and create a Message. For the above [example](#example), this is `ConnectError`.

#### RetryRouterTagger

Tagger to route back to Retry module.

```elm
type alias RetryRouterTagger msg =
	Msg msg -> msg
```

This is the Tagger that will wrap `Retry.Msg` for the Retry module. In the above [example](#example), this is `RetryModule`.

#### RetryCmdTagger

Tagger for parent to retry original command.

```elm
type alias RetryCmdTagger msg =
	Int -> msg -> Cmd msg -> msg
```

This is the Tagger that will create a `Msg` for the Parent that will be sent by the Retry module when the `Cmd msg` fails and needs to be retried.

The Parent is then responsible for retrying the `cmd`.

#### Config

Retry Config.

```elm
type alias Config =
	{ retryMax : Int
	, delayNext : Int -> Time
	}
```

This is the configuration for Retrying a `Cmd`.

* `retryMax` - The maximum number of retries. N.B. this is the number of retries NOT counting the orginal try.
* `delayNext` - This is a function that takes a `retryCount` and returns the delay between the NEXT retry. This is in `milliseconds`. See [constantDelay](#constandelay) and [exponentialDelay](#exponentialdelay).


#### Model

Retry Model.

#### Msg

Retry Msgs.


### Functions

#### initModel

Create an initial model.

```elm
initModel : Model msg
```

#### update

Retry Update.

```elm
update : Config -> Msg msg -> Model msg -> ( ( Model msg, Cmd (Msg msg) ), List msg )
update config msg model
```

#### constantDelay

Constant delay.

```elm
constantDelay : Int -> Int -> Time
constantDelay delay _
```

This will always return the same delay no matter how many retries have been done.

* `delay` - This is the constant delay in milliseconds.

#### exponentialDelay

Exponential delay base 2.

```elm
exponentialDelay : Int -> Int -> Int -> Time
exponentialDelay delay maxDelay retryCount
```

This will return `delay` for the 1st retry, `2 * delay` for the 2nd, `4 * delay`, `16 * delay`, etc. up to `maxDelay`.

* `delay` - This is the base delay in milliseconds.
* `maxDelay` - This is max delay to return in milliseconds.
* `retryCount` - This is the retry count (starting with 1)

#### retry

Retry a Cmd.

```elm
retry : Model msg -> RetryRouterTagger msg -> FailureTagger a msg -> RetryCmdTagger msg -> (FailureTagger a msg -> Cmd msg) -> ( Model msg, Cmd msg )
retry model routerTagger failureTagger retryCmdTagger cmdConstructor
```

See above [example](#example) for usage in context.

* `model` - The Retry Module's `Model`.
* `routerTagger` - This the router tagger that will route messages to the Retry Module.
* `failureTagger` - This is the failure tagger that the Effects Manager's API call would normally expect for a failed operation.
* `retryCmdTagger` - This is the tagger that will create a `Msg` for the Parent to retry the `Cmd`.
* `cmdConstructor` - This is a function that constructs the `Cmd` to be retried. It takes a single parameter of type `FailureTagger a msg`. Here `a` is ANY type since this has to work with any Effects Manager.
