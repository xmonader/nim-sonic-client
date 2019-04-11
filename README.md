# nim-sonic-client


nim client for [sonic](https://github.com/valeriansaliou/sonic) search backend.

## Install

```
nimble install sonic
```

## Examples


### Ingest
```nim
    var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Ingest)
    echo $cl.execCommand("PING")

    echo cl.ping()
    echo cl.protocol
    echo cl.bufsize
    echo cl.push("wiki", "articles", "article-1",
                  "for the love of god hell")
    echo cl.push("wiki", "articles", "article-2",
                  "for the love of satan heaven")
    echo cl.push("wiki", "articles", "article-3",
                  "for the love of lorde hello")
    echo cl.push("wiki", "articles", "article-4",
                  "for the god of loaf helmet")
```
```
PONG
true
0
0
true
2
0
true
true
true
```


### Search
```nim

    var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Search)
    echo $cl.execCommand("PING")

    echo cl.ping()
    echo cl.query("wiki", "articles", "for")
    echo cl.query("wiki", "articles", "love")
    echo cl.suggest("wiki", "articles", "hell")
    echo cl.suggest("wiki", "articles", "lo")
```
```
PONG
true
@[]
@["article-3", "article-2"]
@[]
@["loaf", "lorde", "love"]

```
### Control
```nim
    var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Control)
    echo $cl.execCommand("PING")

    echo cl.ping()
    echo cl.trigger("consolidate")
```
```
PONG
true
OK
```
## API reference

API documentation can be found at [docs/api](./docs/api/sonic.html) and also [Browsable](https://xmonader.github.io/nim-sonic-client/api/sonic/sonic.html)

### Generating docs
use `nimble genDocs`