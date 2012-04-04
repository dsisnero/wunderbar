module Wunderbar

  module CGI

    HIDE_FRAME = [ %r{/(wunderbar|webrick)/},
                   %r{/gems/.*/(builder|rack|sinatra)/} ]

    # produce json
    def self.json(&block)
      headers = { 'type' => 'application/json', 'Cache-Control' => 'no-cache' }
      builder = JsonBuilder.new
      output = builder.encode($params, &block)
      headers['status'] =  "404 Not Found" if output == {}
    rescue Exception => exception
      Wunderbar.error exception.inspect
      headers['status'] =  "500 Internal Server Error"
      backtrace = []
      exception.backtrace.each do |frame| 
        next if HIDE_FRAME.any? {|re| frame =~ re}
        Wunderbar.warn "  #{frame}"
        backtrace << frame 
      end
      builder = JsonBuilder.new
      builder._exception exception.inspect
      builder._backtrace backtrace
    ensure
      out?(headers) { builder.target! }
    end

    # produce text
    def self.text &block
      headers = {'type' => 'text/plain', 'charset' => 'UTF-8'}
      builder = TextBuilder.new
      output = builder.encode($params, &block)
      headers['status'] =  "404 Not Found" if output == ''
    rescue Exception => exception
      Wunderbar.error exception.inspect
      headers['status'] =  "500 Internal Server Error"
      builder.puts unless builder.size == 0
      builder.puts exception.inspect
      exception.backtrace.each do |frame| 
        next if HIDE_FRAME.any? {|re| frame =~ re}
        Wunderbar.warn "  #{frame}"
        builder.puts "  #{frame}"
      end
    ensure
      out?(headers) { builder.target! }
    end

    # Conditionally provide output, based on ETAG
    def self.out?(headers, &block)
      content = block.call
      require 'digest/md5'
      etag = Digest::MD5.hexdigest(content)

      if $env.HTTP_IF_NONE_MATCH == etag.inspect
        $cgi.out 'status' => '304 Not Modified'
      else
        $cgi.out headers.merge('Etag' => etag.inspect) do
          content
        end
      end
    rescue
    end

    # produce html/xhtml
    def self.html(*args, &block)
      headers = { 'type' => 'text/html', 'charset' => 'UTF-8' }
      headers['type'] = 'application/xhtml+xml' if @xhtml

      x = HtmlMarkup.new
      x._! "\xEF\xBB\xBF"
      x._.declare :DOCTYPE, :html

      begin
        if @xhtml
          output = x.xhtml *args, &block
        else
          output = x.html *args, &block
        end
      rescue ::Exception => exception
        headers['status'] =  "500 Internal Server Error"
        x.clear!
        x._! "\xEF\xBB\xBF"
        x._.declare :DOCTYPE, :html
        output = x.html(*args) do
          _head do
            _title 'Internal Server Error'
          end
          _body do
            _h1 'Internal Server Error'
            text = exception.inspect
            Wunderbar.error text
            exception.backtrace.each do |frame| 
              next if HIDE_FRAME.any? {|re| frame =~ re}
              Wunderbar.warn "  #{frame}"
              text += "\n  #{frame}"
            end
    
            _pre text
          end
        end
      end

      out?(headers) { output }
    end

    def self.call(env)
      require 'etc'
      $USER = ENV['REMOTE_USER'] ||= ENV['USER'] || Etc.getlogin

      accept         = $env.HTTP_ACCEPT.to_s
      request_uri    = $env.REQUEST_URI.to_s

      # implied request types
      xhr_json = Wunderbar::Options::XHR_JSON  || (accept =~ /json/)
      text = Wunderbar::Options::TEXT || 
        (accept =~ /plain/ and accept !~ /html/)
      @xhtml = (accept =~ /xhtml/ or accept == '')

      # overrides via the uri query parameter
      xhr_json  ||= (request_uri =~ /\?json$/)
      text       ||= (request_uri =~ /\?text$/)

      # overrides via the command line
      xhtml_override = ARGV.include?('--xhtml')
      html_override  = ARGV.include?('--html')

      # disable conneg if only one handler is provided
      if Wunderbar.queue.length == 1
        type = Wunderbar.queue.first.first
        xhr_json = (type == :json)
        text     = (type == :text)
      end

      Wunderbar.queue.each do |type, args, block|
        case type
        when :html, :xhtml
          unless xhr_json or text
            if type == :html
              @xhtml = false unless xhtml_override
            else
              @xhtml = false if html_override
            end

            self.html(*args, &block)
            return
          end
        when :json
          if xhr_json
            self.json(*args, &block)
            return
          end
        when :text
          if text
            self.text(*args, &block)
            return
          end
        end
      end
    end

    # map Ruby CGI headers to Rack headers
    def self.headers(headers)
      result = headers.dup
      type = result.delete('type') || 'text/html'
      charset = result.delete('charset')
      type = "#{type}; charset=#{charset}" if charset
      result['Content-Type'] ||= type
      result
    end
  end

  @queue = []

  # canonical interface
  def self.html(*args, &block)
    @queue << [:html, args, block]
  end

  def self.xhtml(*args, &block)
    @queue << [:xhtml, args, block]
  end

  def self.json(*args, &block)
    @queue << [:json, args, block]
  end

  def self.text(*args, &block)
    @queue << [:text, args, block]
  end

  def self.queue
    @queue
  end
end
