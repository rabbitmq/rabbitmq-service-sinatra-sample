require 'sinatra'
require 'erb'
require 'cgi'

require 'rabbitmq_service_util'
require 'bunny'

enable :sessions

# Opens a client connection to the RabbitMQ service, if one isn't
# already open.  This is a class method because a new instance of
# the controller class will be created upon each request.  But AMQP
# connections can be long-lived, so we would like to re-use the
# connection across many requests.
def client
  $client ||= begin
    conn = Bunny.new(RabbitMQ::amqp_connection_url)
    conn.start
    $client = conn
  end
end

def channel
  $channel ||= begin
    ch = client.create_channel
    # We only want to accept one un-acked message
    ch.prefetch(1)
    ch
  end
end

# Return the "default exchange", it has implied bindings to all queues.
def default_exchange
  $default_exchange ||= channel.default_exchange
end

# Return a queue named "messages".  This will create the queue on
# the server, if it did not already exist.  Again, we use a class
# method to share this across requests.
def messages_queue
  $messages_queue ||= channel.queue("messages")
end

def take_session(key)
  res = session[key]
  session[key] = nil
  res
end

get '/' do
  @published = take_session(:published)
  @got = take_session(:got)
  erb :index
end

post '/publish' do
  # Send the message from the form's input box to the "messages"
  # queue, via the nameless exchange.  The name of the queue to
  # publish to is specified in the routing key.
  messages_queue.publish(params[:message])
  # Notify the user that we published.
  session[:published] = true
  redirect to('/')
end

post '/get' do
  session[:got] = :queue_empty

  # Wait for a message from the queue

  messages_queue.subscribe(manual_ack: true, timeout: 10, message_max: 1) do |delivery_info, properties, payload|
    # Show the user what we got
    session[:got] = payload
  end

  redirect to('/')
end
