require "thin"
require "sinatra"

if ENV["PORT"]
  set :port, ENV["PORT"].to_i
end

$subs = []
$msgs = []

PREFIX = rand.to_s.slice( (2..-1) )

helpers do
  def message(msg, id: nil)
    id = $msgs.length - 1 unless id
    "data: [#{Time.now.strftime "%H:%M:%S"}] #{msg}\r\nid: #{id}\r\n\r\n"
  end

  def broadcast(msg)
    $subs.select! do |f|
      begin
        f << msg
        true
      rescue
        false
      end
    end
    $msgs << msg
  end

  def filter_nick
    if /[^a-zA-Z0-9_-]/ === params[:nick]
      halt 400, message("That was not a valid nickname")
    end
  end
end

COOKIE = rand.to_s
SERVER_START_TIME = Time.now

before do
  cookie = request.cookies["dram_chat"]
  if cookie == COOKIE
    @last_event_id = request.env["HTTP_LAST_EVENT_ID"]
  else
    response.set_cookie "dram_chat", COOKIE
    @last_event_id = nil
  end
end

get "/" do
  erb :home
end

get "/sse/:nick" do
  filter_nick

  headers "Content-Type" => "text/event-stream"

  stream do |f|
    if @last_event_id
      f << message("* Reconnected")
    else
      f << message( "* Connected; server started at: " +
                    SERVER_START_TIME.strftime("%H:%M:%S"))
    end

    if @last_event_id
      if $msgs[@last_event_id.to_i + 1 .. -1]
        $msgs[@last_event_id.to_i + 1 .. -1].each { |m| f << m }
      end
    else
      $msgs.each { |m| f << m }
      f << message("---- Chat history ----") unless $msgs.empty?
      broadcast message("#{params[:nick]} joined")
    end

    $subs << f

    loop do
      f << "event: ping\r\ndata: ping\r\nid: #{$msgs.length - 1}\r\n\r\n"
      sleep 5
    end
  end
end

post "/post/:nick" do
  filter_nick

  broadcast message(
    "#{params[:nick]}: #{request.body.read(1024).gsub(/[\r\n]/,"")}",
    id: $msgs.length)

  "ok"
end

__END__

@@ home
<meta name="viewport" content="width=device-width, initial-scale=1">
<div id="list"></div>

<input autofocus onkeydown="keydown(this, event)" id="thebox" data-nick="dram"/>

<style>
  body {
    font-size: 16px;
    font-family: Consolas, monospace;
    padding-bottom: 45px;
  }
 
  #list {
    margin-left: 20px;
    margin-right: 20px;
  }

  #thebox {
    position: fixed;
    bottom: 0px;
    left: 0px;
    width: 100%;
    padding: 3px;
    padding-left: 10px;
    padding-bottom: 13px;
    font-size: 16px;
    font-family: Consolas, monospace;
  }

  #thebox:before {
    content: attr(data-nick);
  }
</style>
<script>
  var list = document.getElementById("list");
  var src, nick, last_ping_time, errored = false;

  function say(msg) {
    var shouldScroll =
      window.scrollY + window.innerHeight
      == document.body.scrollHeight;

    var li = document.createElement("div");
    li.textContent = msg;
    if(msg[11] == "*")
      li.style.color = "green";
    if(msg[0] == "*")
      li.style.color = "darkblue";
    if(msg[0] == "!")
      li.style.color = "red";
    list.appendChild(li);

    if(shouldScroll) li.scrollIntoView();
  }

  function setup_src() {
    src = new EventSource("/sse/" + nick);
    src.onmessage = function(event) {
      say(event.data);
    }
    src.onerror = function(event) {
      if(! errored) {
        if(src.readyState == src.CONNECTING)
          say("! Reconnecting");
        else
          say("! EventSource error");
        errored = true;
      }
    }

    src.onopen = function(event) {
      errored = false;
    }

    src.addEventListener("ping", function(event) {
      last_ping_time = Date.now();
    });
  }

  function connect() {
    setup_src();

    last_ping_time = Date.now();

    setInterval(function() {
      if(! errored && Date.now() - last_ping_time > 10000) {
        say("! Lost contact with server");
        src.close();
        setup_src();
        errored = true;
      }
    }, 2000)
  }

  function keydown(t, e) {
    if(e.key == "Enter" && t.value != "") {
      if(nick) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "/post/" + nick);
        xhr.onload = function() {
          t.focus();
        }
        xhr.send(t.value);
        t.value = "";
      } else {
        if(/[^a-zA-Z0-9_-]/.test(t.value)) {
          say("! Bad nickname " +  t.value);
          say("! Only letters, digits, '-' or '_' please.");
        } else {
          nick = t.value;
          connect();
          say("");
          say("* You are now connected as " + nick);
          say("* Now talk into the box at the bottom of the page");
        }
        t.value = "";
      }
    }
  }

  say("* Welcome to dram chat.");
  say("* Input nickname and press Enter");
</script>
