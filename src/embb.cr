module Embb
  extend self
  VERSION = {{ `shards version __DIR__`.chomp.stringify }}

  macro embbed(path, as name)
    {{ run(
         "./embb-ct", path, name,
         env("EMBB_ARCH") || [:aarch64, :avr, :arm, :i386, :wasm32, :x86_64].find { |flag| flag? flag }.id.stringify,
         env("EMBB_VENDOR") || [:macosx, :portbld, :unknown].find { |flag| flag? flag }.id.stringify || "unkown",
         env("EMBB_OS") || [:darwin, :dragonfly, :freebsd, :linux, :netbsd, :openbsd, :solaris, :windows].find { |flag| flag? flag }.id.stringify,
         env("EMBB_ABI") || [:android, :armhf, :gnu, :gnueabihf, :msvc, :musl, :wasi, :win32].find { |flag| flag? flag }.id.stringify
       ) unless flag? :docs }}
  end
end
