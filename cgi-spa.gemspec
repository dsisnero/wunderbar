# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{cgi-spa}
  s.version = "0.3.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["Sam Ruby"]
  s.date = %q{2009-12-27}
  s.description = %q{    Provides a number of globals, helper methods, and monkey patches which
    simplify the development of single page applications in the form of
    CGI scripts.
}
  s.email = %q{rubys@intertwingly.net}
  s.extra_rdoc_files = ["COPYING", "README", "lib/cgi-spa.rb", "lib/cgi-spa/builder.rb", "lib/cgi-spa/cgi-methods.rb", "lib/cgi-spa/environment.rb", "lib/cgi-spa/html-methods.rb", "lib/cgi-spa/installation.rb", "lib/cgi-spa/job-control.rb", "lib/cgi-spa/version.rb"]
  s.files = ["COPYING", "Manifest", "README", "Rakefile", "cgi-spa.gemspec", "lib/cgi-spa.rb", "lib/cgi-spa/builder.rb", "lib/cgi-spa/cgi-methods.rb", "lib/cgi-spa/environment.rb", "lib/cgi-spa/html-methods.rb", "lib/cgi-spa/installation.rb", "lib/cgi-spa/job-control.rb", "lib/cgi-spa/version.rb"]
  s.homepage = %q{http://github.com/rubys/cgi-spa}
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Cgi-spa", "--main", "README"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{cgi-spa}
  s.rubygems_version = %q{1.3.5}
  s.summary = %q{CGI Single Page Applications}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<builder>, [">= 0"])
      s.add_runtime_dependency(%q<json>, [">= 0"])
    else
      s.add_dependency(%q<builder>, [">= 0"])
      s.add_dependency(%q<json>, [">= 0"])
    end
  else
    s.add_dependency(%q<builder>, [">= 0"])
    s.add_dependency(%q<json>, [">= 0"])
  end
end
