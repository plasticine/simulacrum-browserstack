# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'simulacrum/browserstack/version'

Gem::Specification.new do |gem|
  gem.name          = 'simulacrum-browserstack'
  gem.version       = Simulacrum::Browserstack::VERSION
  gem.authors       = ['Justin Morris']
  gem.email         = ['desk@pixelbloom.com']
  gem.summary       = %q{BrowserStack runner for Simulacrum}
  gem.description   = %q{BrowserStack runner for Simulacrum}
  gem.homepage      = ''
  gem.license       = 'MIT'

  gem.files         = `git ls-files -z`.split("\x0")
  gem.executables   = gem.files.grep(%r{^bin/}) { |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']

  gem.add_dependency 'parallel', ['~> 1.2.0']
  gem.add_dependency 'net-http-persistent'

  gem.add_development_dependency 'bundler', '~> 1.6'
  gem.add_development_dependency 'rake'
end
