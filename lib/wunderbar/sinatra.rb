require 'sinatra'
require 'wunderbar'
require 'digest/md5'
require 'nokogiri'

begin
  require "sinatra/reloader" if development? # gem install sinatra-contrib
rescue LoadError
end

module Wunderbar
  module SinatraHelpers
    def _html(*args, &block)
      Wunderbar::Template.locals(self, args)

      if block
        Wunderbar::Template::Html.evaluate('html.rb', self) do
          _html(*args) { instance_eval(&block) }
        end
      else
        Wunderbar::Template::Html.evaluate('html.rb', self, *args)
      end
    end

    def _xhtml(*args, &block)
      if env['HTTP_ACCEPT'] and not env['HTTP_ACCEPT'].include? 'xhtml'
        return _html(*args, &block)
      end

      Wunderbar::Template.locals(self, args)

      if block
        Wunderbar::Template::Xhtml.evaluate('xhtml.rb', self) do
          _xhtml(*args) { instance_eval(&block) }
        end
      else
        Wunderbar::Template::Xhtml.evaluate('xhtml.rb', self, *args)
      end
    end
  end

  # Tilt template implementation
  module Template
    class Base < Tilt::Template
      def self.engine_initialized?
        defined? ::Wunderbar
      end

      def initialize_engine
        require_template_library 'wunderbar'
      end

      def prepare
      end

      def precompiled_template(locals)
        raise NotImplementedError.new("dynamic only")
      end

      def precompiled_preamble(locals)
        raise NotImplementedError.new("dynamic only")
      end

      def precompiled_postamble(locals)
        raise NotImplementedError.new("dynamic only")
      end

      def self.evaluate(template, scope, *args, &block)
        scope.content_type default_mime_type
        if block
          output = new(&Proc.new {}).evaluate(scope, {}, &block)
        else
          output = scope.send :render, template, *args
        end
        scope.etag Digest::MD5.hexdigest(output)
        output
      end

    private

      def _evaluate(builder, scope, locals, &block)
        builder.set_variables_from_params(locals)

        if not block
          builder.instance_eval(data, eval_file)
        elsif not data
          builder.instance_eval(&block)
        else
          context = builder.get_binding do
            builder.instance_eval {_(&block)}
          end
          context.eval(data, eval_file)
        end
      end
    end

    class Html < Base
      self.default_mime_type = 'text/html'

      def evaluate(scope, locals, &block)
        builder = HtmlMarkup.new(scope)
        begin
          _evaluate(builder, scope, locals, &block)
        rescue Exception => exception
          scope.response.status = Wunderbar::ServerError.status
          builder.clear!
          builder.html do
            _h1 'Internal Server Error'
            _exception exception
          end
        end
        builder._.target!
      end
    end

    class Xhtml < Html
      self.default_mime_type = 'application/xhtml+xml'
    end

    module Json
      def self.ext; ['json.rb', :_json]; end
      def self.mime; 'application/json;charset=utf-8'; end

      def evaluate(scope, locals, &block)
        builder = JsonBuilder.new(scope)
        begin
          result = _evaluate(builder, scope, locals, &block)

          # if no output was produced, use the result
          builder._! result if builder.target? == {} and result

        rescue Exception => exception
          scope.content_type self.class.default_mime_type, :charset => 'utf-8'
          scope.response.status = Wunderbar::ServerError.status
          builder._exception exception
        end
        scope.cache_control :no_cache
        builder.target!
      end
    end

    module Text
      def self.ext; ['text.rb', :_text]; end
      def self.mime; 'text/plain'; end

      def evaluate(scope, locals, &block)
        builder = TextBuilder.new(scope)
        begin
          result = _evaluate(builder, scope, locals, &block)

          # if no output was produced, use the result
          builder._ result.to_s if builder.target!.empty? and result

          scope.response.status = 404 if builder.target!.empty?
        rescue Exception => exception
          scope.headers['Content-Type'] = self.class.default_mime_type
          scope.response.status = Wunderbar::ServerError.status
          builder._exception exception
        end
        builder.target!
      end
    end

    PASSABLE = [Numeric, String, Hash, Array]

    def self.locals(scope, args)
      args.push({}) if args.length == 1

      return unless Hash === args.last and not args.last[:locals]

      locals = {}

      scope.instance_variables.each do |ivar|
        next if [:@env, :@params].include? ivar
        value = scope.instance_variable_get(ivar)
        locals[ivar] = value
      end

      args.last[:locals] = locals
    end

    def self.register(language, base=Base)
      template = Class.new(Template::Base) do 
        self.default_mime_type = language.mime
        include language
      end

      Array(language.ext).each do |ext|
        SinatraHelpers.send :define_method, ext do |*args, &block|
          # parse json
          if env['CONTENT_TYPE'] =~ /^\w+\/json/
            json = JSON.parse(env['rack.input'].read)
            @params.merge! json if Hash === json
          end

          Wunderbar::Template.locals(self, args)
          if Hash === args.last and args.last[:locals]
            @params.each do |name, value| 
              args.last[:locals]["@#{name}".to_sym] = value
            end
          end

          # text, json shortcuts
          if block == nil and args.length >= 1
            case args.first
            when Array, Hash
              block = proc { _! args.first } if ext == :_json
            when String
              block = proc { _ args.first } if ext == :_text
            end
          end

          template.evaluate(ext, self, *args, &block)
        end

        Tilt.register ext.to_s, template
      end
    end

    constants.each do |language|
      language = const_get(language)
      register language if language.respond_to? :mime
    end
  end
end

Tilt.register '_html',  Wunderbar::Template::Html
Tilt.register 'html.rb',  Wunderbar::Template::Html
Tilt.register '_xhtml', Wunderbar::Template::Xhtml
Tilt.register 'xhtml.rb', Wunderbar::Template::Xhtml

helpers Wunderbar::SinatraHelpers

if Dir.exist? settings.public_folder
  Wunderbar::Asset.root = File.join(settings.public_folder, 'assets')
end

Wunderbar::Asset.virtual = true

get "/#{Wunderbar::Asset.path}/:name" do |name|
  file = "#{Wunderbar::Asset.root}/#{name}"
  _text do
    if File.exist? file
      last_modified File.mtime(file)
      content_type Wunderbar::Asset.content_type_for(name)
      _.headers.merge(response.headers)
      File.read("#{Wunderbar::Asset.root}/#{name}")
    else
      asset = Wunderbar::Asset.find(name)
      if asset
        last_modified asset.mtime
        content_type Wunderbar::Asset.content_type_for(name)
        _.headers.merge(response.headers)
        asset.contents
      end
    end
  end
end

unless Wunderbar.queue.empty?
  queue = Wunderbar.queue.dup

  get '/' do
    xhr_json = (env['HTTP_ACCEPT'].to_s =~ /json/)
    xhr_json ||= (env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest')

    task = queue.find {|type, args, block| (type!=:json) ^ xhr_json}
    pass unless task

    if xhr_json
      _json(*task[1], &task[2])
    else
      _html(*task[1], &task[2])
    end
  end

  Wunderbar.queue.clear
end

# Monkeypatch to address https://github.com/sinatra/sinatra/pull/907
module Rack
  class ShowExceptions
    alias_method :w_pretty, :pretty

    def pretty(*args)
      result = w_pretty(*args)

      unless result.respond_to? :join
        def result.join; self; end
      end

      unless result.respond_to? :each
        def result.each(&block); block.call(self); end
      end

      result
    end
  end
end
