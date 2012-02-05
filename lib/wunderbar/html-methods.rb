# smart style, knows that the content is indented text/data
def $x.style!(text)
  text.slice! /^\n/
  text.slice! /[ ]+\z/
  $x.style :type => "text/css" do
    if $XHTML
      indented_text! text
    else
      indented_data! text
    end
  end
end

# smart script, knows that the content is indented text/data
def $x.script!(text)
  text.slice! /^\n/
  text.slice! /[ ]+\z/
  $x.script :lang => "text/javascript" do
    if $XHTML
      indented_text! text
    else
      indented_data! text
    end
  end
end

# execute a system command, echoing stdin, stdout, and stderr
def $x.system!(command, opts={})
  require 'open3'
  output_class = opts[:class] || {}
  stdin  = output_class[:stdin]  || 'stdin'
  stdout = output_class[:stdout] || 'stdout'
  stderr = output_class[:stderr] || 'stderr'

  $x.pre command, :class=>stdin unless opts[:echo] == false

  require 'thread'
  semaphore = Mutex.new
  Open3.popen3(command) do |pin, pout, perr|
    [
      Thread.new do
        until pout.eof?
          out_line = pout.readline.chomp
          semaphore.synchronize { $x.pre out_line, :class=>stdout }
        end
      end,

      Thread.new do
        until perr.eof?
          err_line = perr.readline.chomp
          semaphore.synchronize { $x.pre err_line, :class=>stderr }
        end
      end,

      Thread.new do
        if opts[:stdin].respond_to? :read
          require 'fileutils'
          FileUtils.copy_stream opts[:stdin], pin
        elsif opts[:stdin]
          pin.write opts[:stdin].to_s
        end
        pin.close
      end
    ].each {|thread| thread.join}
  end
end

def $x.body? args={}
  traceback_class = args.delete('traceback_class')
  traceback_style = args.delete('traceback_style')
  traceback_style ||= 'background-color:#ff0; margin: 1em 0; padding: 1em; ' +
    'border: 4px solid red; border-radius: 1em'
  $x.body(args) do
    begin
      yield
    rescue ::Exception => exception
      text = exception.inspect
      exception.backtrace.each {|frame| text += "\n  #{frame}"}

      if traceback_class
        $x.pre text, :class=>traceback_class
      else
        $x.pre text, :style=>traceback_style
      end
    end
  end
end

# Wrapper class that understands HTML
class HtmlMarkup
  VOID = %w(
    area base br col command embed hr img input keygen
    link meta param source track wbr
  )

  def initialize(*args, &block)
    # as a migration aide, use the global variable, but consider that
    # to be deprecated.
    $x ||= Builder::XmlMarkup.new :indent => 2
    @x = $x
  end

  def html(*args, &block)
    @x.html(*args) { instance_exec(@x, &block) }
  end

  def method_missing(name, *args, &block)
    if name.to_s =~ /^_(\w+)(!|\?|)$/
      name, flag = $1, $2
    else
      error = NameError.new "undefined local variable or method `#{name}'", name
      error.set_backtrace caller
      raise error
    end

    if flag != '!'
      if %w(script style).include?(name)
        if String === args.first and not block
          text = args.shift
          if $XHTML
            block = Proc.new {@x.indented_text! text}
          else
            block = Proc.new {@x.indented_data! text}
          end
        end

        args << {} if args.length == 0
        if Hash === args.last
          args.last[:lang] ||= 'text/javascript' if name == 'script'
          args.last[:type] ||= 'text/css' if name == 'style'
        end
      end

      # ensure that non-void elements are explicitly closed
      if args.length == 0 or (args.length == 1 and Hash === args.first)
        args.unshift '' if not VOID.include?(name) and not block
      end

      # remove attributes with nil values
      args.last.delete_if {|key, value| value == nil} if Hash === args.last
    end

    if flag == '!'
      # turn off indentation
      indent, level = @x.instance_eval { [@indent, @level] }
      begin
        @x.instance_eval { [@indent=0, @level=0] }
        @x.text! " "*indent*level
        @x.tag! name, *args, &block
      ensure
        @x.text! "\n"
        @x.instance_eval { [@indent=indent, @level=level] }
      end
    elsif flag == '?'
      # capture exceptions, produce filtered tracebacks
      options = (Hash === args.last)? args.last : {}
      traceback_class = options.delete(:traceback_class)
      traceback_style = options.delete(:traceback_style)
      traceback_style ||= 'background-color:#ff0; margin: 1em 0; ' +
        'padding: 1em; border: 4px solid red; border-radius: 1em'
      @x.tag!(name, *args) do
        begin
          block.call
        rescue ::Exception => exception
          text = exception.inspect
          Wunderbar.warn text
          exception.backtrace.each do |frame| 
            next if frame =~ %r{/wunderbar/}
            next if frame =~ %r{/gems/.*/builder/}
            Wunderbar.warn "  #{frame}"
            text += "\n  #{frame}"
          end
    
          if traceback_class
            $x.pre text, :class=>traceback_class
          else
            $x.pre text, :style=>traceback_style
          end
        end
      end
    else
      @x.tag! name, *args, &block
    end
  end

  def _head(*args, &block)
    @x.tag!('head', *args) do
      @x.meta :charset => 'utf-8' unless $XHTML
      block.call if block
    end
  end

  def _(text=nil)
    @x.indented_text! text if text
    @x
  end

  def _!(text=nil)
    @x.text! text if text
    @x
  end

  def declare!(*args)
    @x.declare!(*args)
  end

  def _coffeescript(text)
    require 'coffee-script'
    _script CoffeeScript.compile(text)
  rescue LoadError
    _script text, :lang => 'text/coffeescript'
  end

  def target!
    @x.target!
  end
end
