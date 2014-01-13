#
# Web frameworks often require a set of JavaScript and/or CSS stylesheet files
# to be pulled in.  Asset support makes it easy to deploy such files to be
# deployed statically; and furthermore to automatically insert the relevant
# <script src> or <link rel="stylesheet"> lines to the <head> section of your
# HTML.
#
# For examples, see angularjs.rb, jquery.rb, opal.rb, pagedown.rb, or
# polymer.rb.
#

require 'fileutils'

module Wunderbar
  class Asset
    class << self
      # URI path prepended to individual asset path
      attr_accessor :path

      # location where the asset directory is to be found/placed
      attr_accessor :root
    end

    # asset file location
    attr_reader :path

    # asset contents
    attr_reader :contents

    def self.clear
      @@scripts = []
      @@stylesheets = []
    end

    def self.content_type_for(path)
      if @@scripts.any? {|script| script.path == path}
        'application/javascript'
      elsif @@stylesheets.any? {|script| script.path == path}
        'text/css'
      else
        'application/octet-stream'
      end
    end

    clear

    @path = '../' * ENV['PATH_INFO'].to_s.count('/') + 'assets'
    @root = File.dirname(ENV['SCRIPT_FILENAME']) if ENV['SCRIPT_FILENAME']
    @root = File.expand_path((@root || Dir.pwd) + "/assets")

    # Options: typically :name plus either :file or :contents
    #   :name => name to be used for the asset
    #   :file => source for the asset
    #   :contents => contents of the asset
    def initialize(options)
      source = options[:file] || __FILE__
      @contents = options[:contents]

      options[:name] ||= File.basename(options[:file]) if source

      if options[:name]
        @path = options[:name]
        dest = File.expand_path(@path, Asset.root)

        if not File.exist?(dest) or File.mtime(dest) < File.mtime(source)
          begin
            FileUtils.mkdir_p File.dirname(dest)
            if options[:file]
              FileUtils.cp source, dest, :preserve => true
            else
              open(dest, 'w') {|file| file.write @contents}
            end
          rescue
            @path = nil
            @contents ||= File.read(source)
          end
        end
      else
      end
    end

    def self.script(options)
      @@scripts << self.new(options)
    end

    def self.css(options)
      @@stylesheets << self.new(options)
    end

    def self.declarations(parent, base)
      path = base.to_s.sub(/^\//,'').split('/').map {'../'}.join + Asset.path
      nodes = []
      @@scripts.each do |script|
        if script.path
          nodes << Node.new(:script, src: "#{path}/#{script.path}")
        elsif script.contents
          nodes << ScriptNode.new(:script, script.contents)
        end
      end

      @@stylesheets.each do |stylesheet|
        if stylesheet.path
          nodes << Node.new(:link, rel: "stylesheet", type: "text/css",
            href: "#{path}/#{stylesheet.path}")
        elsif stylesheet.contents
          nodes << StyleNode.new(:style, stylesheet.contents)
        end
      end
      nodes.each {|node| node.parent = parent}
    end
  end
end
