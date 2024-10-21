Gem::Specification.new do |s|
    s.name        = "emissary-maps"
    s.version     = "0.1.1"
    s.summary     = "Hex map generator"
    s.description = "Build a hex map for Emissary and write as JSON or SVG"
    s.authors     = ["Jim Rowe"]
    s.email       = "jim@jicode.org"
    s.files       = Dir["lib/*"]
    s.homepage    = "https://jimcode.org/emissary/maps"
    s.license     = "MIT"
    s.executables = ['emissary-map']
    s.require_paths = ["lib"]
  end