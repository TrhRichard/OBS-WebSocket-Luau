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
-   [x] Requests
    -   [x] General
    -   [x] Config
    -   [x] Sources
    -   [x] Scenes
    -   [x] Inputs
    -   [x] Transitions
    -   [x] Filters
    -   [x] Scene Items
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

## Credits

-   [Data-Oriented-House](https://github.com/Data-Oriented-House) for
    [LemonSignal](https://github.com/Data-Oriented-House/LemonSignal)
