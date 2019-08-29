module Wunderbar
  module VERSION #:nodoc:
    MAJOR = 1
    MINOR = 3
    TINY  = 3

    STRING = [MAJOR, MINOR, TINY].join('.')
  end
end unless defined?(Wunderbar::VERSION)
