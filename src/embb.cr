# TODO:
# - Automatically detect target architecture
# - Allow overriding of target architecture: from client crystal override and compile time environnment variables
module Embb
  extend self

  VERSION = {{ `shards version __DIR__`.chomp.stringify }}
  
  macro embbed(path, as name)
    {{run "./embb-ct", path, name}}
  end
end
