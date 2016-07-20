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
    "data: [#{Time.now.strftime "%H:%M:%S"}] #{msg}\r\nid: #{msg}\r\n\r\n"
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
end

get "/" do
  p $msgs
  erb :home
end

get "/sse/:nick" do
  headers "Content-Type" => "text/event-stream"

  stream :keep_open do |f|
    f << message("Connected")
    last_id = request.env["HTTP_LAST_EVENT_ID"]
    last_id = -1 unless last_id
    
    if not last_id or $msgs[last_id.to_i + 1 .. -1]
      $msgs[last_id.to_i + 1 .. -1].each do |m|
        f << m
      end
    end

    $subs << f

    unless request.env["HTTP_LAST_EVENT_ID"]
      f << message("---- Historical messages ----")
      broadcast message("#{params[:nick]} joined")
    end
  end
end

post "/post/:nick" do
  broadcast message(
    "#{params[:nick]}: #{request.body.read}",
    id: $msgs.length)

  "ok"
end

__END__

@@ home
<meta name="viewport" content="width=device-width, initial-scale=1">
<input onkeydown="keydown(this, event)" />
<ul id="list"></ul>
<style> body { font-size: 16; font-family: Consolas, monospace; } </style>
<script>
  var list = document.getElementById("list");
  var src, nick;

  function say(msg) {
      var li = document.createElement("li");
      li.textContent = msg;
      list.insertBefore(li, list.firstChild);
  }

  function connect() {
    src = new EventSource("/sse/" + nick);
    src.onmessage = function(event) {
      say(event.data)
    }
  }

  function keydown(t, e) {
    if(e.keyIdentifier == "Enter" && t.value != "") {
      if(nick) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "/post/" + nick);
        xhr.onload = function() {
          t.focus();
        }
        xhr.send(t.value);
        t.value = "";
      } else {
        nick = t.value.replace(/[^a-zA-Z]/g, "");
        t.value = "";
        connect();
      }
    }
  }

  say("After you connect, you can talk into the box above");
  say("Input nickname and press Enter");
  say("Welcome to dram chat.");
</script>
