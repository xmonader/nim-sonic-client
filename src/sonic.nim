## Sonicclient
## Copyright Ahmed T. Youssef
## nim Sonic client 
import strformat, tables, json, strutils, sequtils, hashes, net, asyncdispatch, asyncnet, os, strutils, parseutils, deques, options, net

type 
  SonicChannel {.pure.} = enum 
   Ingest
   Search
   Control

type
  SonicBase[TSocket] = ref object of RootObj
   socket: TSocket
   host: string
   port: int
   password: string
   connected: bool
   timeout*: int
   protocol*: int
   bufSize*: int
   channel*: SonicChannel

  Sonic* = ref object of SonicBase[net.Socket]
  AsyncSonic* = ref object of SonicBase[asyncnet.AsyncSocket]

type 
  SonicServerError = object of Exception

when defined(ssl):
  proc SSLifySonicConnectionNoVerify(Sonic: var Sonic|AsyncSonic) = 
   let ctx = newContext(verifyMode=CVerifyNone)
   ctx.wrapSocket(Sonic.socket)

proc quoteText(text:string): string =
  ## Quote text and normalize it in sonic protocol context.
  ##  - text str  text to quote/escape
  ##  Returns:
  ##    str  quoted text

  return '"' & text.replace('"', '\"').replace("\r\n", "") & '"'


proc isError(response: string): bool =
  ## Check if the response is Error or not in sonic context.
  ## Errors start with `ERR`
  ##  - response   response string
  ##  Returns:
  ##    bool  true if response is an error.
  
  if response.startsWith("ERR "):
     result = true
  result = false


proc raiseForError(response:string): string =
  ## Raise SonicServerError in case of error response.
  ##  - response message to check if it's error or not.
  ##  Returns:
  ##    str the response message
  if isError(response):
   raise newException(SonicServerError, response)
  return response


proc startSession*(this:Sonic|AsyncSonic): Future[void] {.multisync.} =
  let resp = await this.socket.recvLine()

  if "CONNECTED" in resp:
   this.connected = true
  
  var channelName = ""
  case this.channel:
   of SonicChannel.Ingest:  channelName = "ingest"
   of SonicChannel.Search:  channelName = "search"
   of SonicChannel.COntrol: channelName = "control"
  
  let msg = fmt"START {channelName} {this.password} \r\n"
  await this.socket.send(msg)  #### start
  discard await this.socket.recvLine()  #### started. FIXME extract protocol bufsize
  
proc open*(host = "localhost", port = 1491, password="", channel:SonicChannel, ssl=false, timeout=0): Sonic =
  result = Sonic(
   socket: newSocket(buffered = true),
   host: host,
   port: port,
   password: password,
   channel: channel
  )
  result.timeout = timeout
  result.channel = channel
  when defined(ssl):
   if ssl == true:
     SSLifySonicConnectionNoVerify(result)
  result.socket.connect(host, port.Port)
  
  result.startSession()
  
proc openAsync*(host = "localhost", port = 1491, password="", ssl=false, timeout=0): Future[AsyncSonic] {.async.} =
  ## Open an asynchronous connection to a Sonic server.
  result = AsyncSonic(
   socket: newAsyncSocket(buffered = true),
  )
  when defined(ssl):
   if ssl == true:
     SSLifySonicConnectionNoVerify(result)
  result.timeout = timeout
  await result.socket.connect(host, port.Port)
  await result.startSession()

proc receiveManaged*(this:Sonic|AsyncSonic, size=1): Future[string] {.multisync.} =
  when this is Sonic:
   if this.timeout == 0:
     result = this.socket.recvLine()
   else:
     result = this.socket.recvLine(timeout=this.timeout)
  else:
   result = await this.socket.recvLine()
  
  result = raiseForError(result.strip())

proc execCommand*(this: Sonic|AsyncSonic, command: string, args:seq[string]): Future[string] {.multisync.} =
  let cmdArgs = concat(@[command], args)
  let cmdStr = join(cmdArgs, " ").strip()
  await this.socket.send(cmdStr & "\r\n")
  result = await this.receiveManaged()

proc execCommand*(this: Sonic|AsyncSonic, command: string): Future[string] {.multisync.} =
  result = await this.execCommand(command, @[""])

proc ping*(this: Sonic|AsyncSonic): Future[bool] {.multisync.} =
  ## Send ping command to the server
  ## Returns:
  ## bool  True if successfully reaching the server.
  
  result = (await this.execCommand("PING")) == "PONG"

proc quit*(this: Sonic|AsyncSonic): Future[string] {.multisync.} =
   ## Quit the channel and closes the connection.
   result = await this.execCommand("QUIT")
   this.socket.close()

## TODO: check help.
proc help*(this: Sonic|AsyncSonic, arg: string): Future[string] {.multisync.} =
   ## Sends Help query.
   result = await this.execCommand("HELP", @[arg])

proc push*(this: Sonic|AsyncSonic, collection, bucket, objectName, text: string, lang=""): Future[bool] {.multisync.} =
   ## Push search data in the index
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - objectName: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact)
   ##   - text: search text to be indexed can be a single word, or a longer text; within maximum length safety limits
   ##   - lang: ISO language code
   ##   Returns:
   ##     bool  True if search data are pushed in the index. 
   var langString = ""
   if lang != "":
     langString = fmt"LANG({lang})"
   let text = quoteText(text)
   result = (await this.execCommand("PUSH", @[collection, bucket, objectName, text, langString]))=="OK"

proc pop*(this: Sonic|AsyncSonic, collection, bucket, objectName, text: string): Future[int] {.multisync.} =
   ## Pop search data from the index
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - objectName: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact)
   ##   - text: search text to be indexed can be a single word, or a longer text; within maximum length safety limits
   ##   Returns:
   ##     int 
   let text = quoteText(text)
   let resp = await this.execCommand("POP", @[collection, bucket, objectName, text])
   result = resp.split()[^1].parseInt()

proc count*(this: Sonic|AsyncSonic, collection, bucket, objectName: string): Future[int] {.multisync.} =
   ## Count indexed search data
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - objectName: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact)
   ## Returns:
   ## int  count of index search data.

   var bucketString = ""
   if bucket != "":
     bucketString = bucket
   var objectNameString = ""
   if objectName != "":
     objectNameString = objectName
   result = parseInt(await this.execCommand("COUNT", @[collection, bucket, objectName]))

proc flushCollection*(this: Sonic|AsyncSonic, collection: string): Future[int] {.multisync.} =
   ## Flush all indexed data from a collection
   ##  - collection index collection (ie. what you search in, eg. messages, products, etc.)
   ##   Returns:
   ##     int  number of flushed data
   
   result = (await this.execCommand("FLUSHC", @[collection])).parseInt

proc flushBucket*(this: Sonic|AsyncSonic, collection, bucket: string): Future[int] {.multisync.} =
   ## Flush all indexed data from a bucket in a collection
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   Returns:
   ##    int  number of flushed data
   
   result = (await this.execCommand("FLUSHB", @[collection, bucket])).parseInt

proc flushObject*(this: Sonic|AsyncSonic, collection, bucket, objectName: string): Future[int] {.multisync.} =
   ## Flush all indexed data from an object in a bucket in collection
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - objectName: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact)
   ##   Returns:
   ##     int  number of flushed data
   
   result = (await this.execCommand("FLUSHO", @[collection, bucket, objectName])).parseInt

proc flush*(this: Sonic|AsyncSonic, collection: string, bucket="", objectName=""): Future[int] {.multisync.} =
   ## Flush indexed data in a collection, bucket, or in an object.
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - objectName: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact)
   ##   Returns:
   ##     int  number of flushed data
   if bucket == "" and objectName=="":
      result = await this.flushCollection(collection)
   elif bucket != "" and objectName == "":
      result = await this.flushBucket(collection, bucket)
   elif objectName != "" and bucket != "":
      result = await this.flushObject(collection, bucket, objectName)

proc query*(this: Sonic|AsyncSonic, collection, bucket, terms: string, limit=10, offset: int=0, lang=""): Future[seq[string]] {.multisync.} =
  ## Query the database
  ##  - collection index collection (ie. what you search in, eg. messages, products, etc.)
  ##  - bucket index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
  ##  - terms text for search terms
  ##  - limit a positive integer number; set within allowed maximum & minimum limits
  ##  - offset a positive integer number; set within allowed maximum & minimum limits
  ##  - lang an ISO 639-3 locale code eg. eng for English (if set, the locale must be a valid ISO 639-3 code; if not set, the locale will be guessed from text).
  ##  Returns:
  ##    list  list of objects ids.
   
  let limitString = fmt"LIMIT({limit})"
  var langString = ""
  if lang != "":
   langString = fmt"LANG({lang})"
  let offsetString = fmt"OFFSET({offset})"

  let termsString = quoteText(terms)
  discard await this.execCommand("QUERY", @[collection, bucket, termsString, limitString, offsetString, langString])
  let resp = await this.receiveManaged()
  result = resp.splitWhitespace()[3..^1]

proc suggest*(this: Sonic|AsyncSonic, collection, bucket, word: string, limit=10): Future[seq[string]] {.multisync.} =
   ## auto-completes word.
   ##   - collection index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - word word to autocomplete
   ##   - limit a positive integer number; set within allowed maximum & minimum limits (procault: {None})
   ##   Returns:
   ##     list list of suggested words.
   var limitString = fmt"LIMIT({limit})" 
   let wordString = quoteText(word)
   discard await this.execCommand("SUGGEST", @[collection, bucket, wordString, limitString])
   let resp = await this.receiveManaged()
   result = resp.splitWhitespace()[3..^1]


proc trigger*(this: Sonic|AsyncSonic, action=""): Future[string] {.multisync.} =
   ## Trigger an action
   ##   action text for action
   result = await this.execCommand("TRIGGER", @[action])

when isMainModule:

  proc testIngest() =
   var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Ingest)
   echo $cl.execCommand("PING")

   echo cl.ping()
   echo cl.protocol
   echo cl.bufsize
   echo cl.push("wiki", "articles", "article-1",
              "for the love of god hell")
   echo cl.pop("wiki", "articles", "article-1",
              "for the love of god hell")
   echo cl.pop("wikis", "articles", "article-1",
              "for the love of god hell")
   echo cl.push("wiki", "articles", "article-2",
              "for the love of satan heaven")
   echo cl.push("wiki", "articles", "article-3",
              "for the love of lorde hello")
   echo cl.push("wiki", "articles", "article-4",
              "for the god of loaf helmet")

  proc testSearch() =

   var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Search)
   echo $cl.execCommand("PING")

   echo cl.ping()
   echo cl.query("wiki", "articles", "for")
   echo cl.query("wiki", "articles", "love")
   echo cl.suggest("wiki", "articles", "hell")
   echo cl.suggest("wiki", "articles", "lo")

  proc testControl() =
   var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Control)
   echo $cl.execCommand("PING")

   echo cl.ping()
   echo cl.trigger("consolidate")


  testIngest()
  testSearch()
  testControl()