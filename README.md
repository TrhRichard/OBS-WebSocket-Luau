# OBS-WebSocket-Luau

OBS WebSocket API for Luau (Zune)

A proper README.md will be made when the library has all the functions for
rpc version 1 of the websocket api.

If you think my code is ugly or slow then my answer is: I don't care I made this
for fun

## TODO

### Events

-   [ ] Implement typing for method `OBSWebSocket:on()` handler argument
    -   Due to current type solver (or my stupidity) there's no way to give proper
        autocomplete at the moment, for that reason all the events types are exported from the main class for you
-   [ ] Implement documentation for event data fields

### Requests

-   [x] Batch Requests
-   [ ] Requests
    -   [x] General
    -   [x] Config
    -   [x] Sources
    -   [ ] Scenes
    -   [ ] Inputs
    -   [ ] Transitions
    -   [ ] Filters
    -   [ ] Scene Items
    -   [x] Outputs
    -   [x] Stream
    -   [x] Record
    -   [x] Media Inputs
    -   [x] Ui

### Other

-   [ ] Add support for Lune runtime
    -   Not really gonna be mandatory for first release but
        something that should be considered, went with Zune at first because
        I liked interacting with websockets more here
-   [ ] Add support for [pesde](https://pesde.dev/) package manager
-   [ ] Add Moonwave support for documentation
    -   Probably gonna do it sometime after the first release, for now
        [OBS WebSocket Protocal](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md) can be used for more info regarding requests and stuff

## Request Implementation Format

Implementation format for me to follow so I keep stuff more consistent

-   For requests that have multiple keys,
    return the object
    (for example: `OBSWebSocket:getStats()` returns the response object)

-   For requests that have one key,
    return the value of the key
    (for example: `OBSWebSocket:getPersistentData()` returns `any?`)

-   For requests that have two keys and have same type,
    return a tuple of both
    (for example: `OBSWebSocket:getProfileParameter()` returns `(string, string)`)

## Credits

-   [Data-Oriented-House](https://github.com/Data-Oriented-House) for
    [LemonSignal](https://github.com/Data-Oriented-House/LemonSignal)

-   ChatGPT
    -   writing all the exported types in `src/init.luau` since
        I did not want to deal with that pain
