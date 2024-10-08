# embb

Embbed files into crystal lang executables (including large binary files).   


This library works by generating object files wrapping the given input files and linking them with the crystal executable.  
It only support generating Elf64 object files.  
Support on platforms different than `x86_64-linux-*` may vary depending on linker willingness to accpets this library shenanigans.  

### Caution

This library generate temporary files at compile-time.  
Those temporary files may be as large as the files embbed in the binary.  
These files can be safely discarded after complete compilation.  
They follow the naming scheme `<Crystal Dir.tempdir>/embb_<sha256 hash>.o`  

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     embb:
       github: globoplox/embb
   ```

2. Run `shards install`

## Usage

At top level, declare the files to embbed.  
Note that `Embb.embbed` is a macro and so parameters must be defined as literals.  

```crystal
require "embb"

Embb.embbed "./README.md", as: readme
Embb.embbed "./LICENSE", as: license
Embb.embbed "./BIGFILE", as: large # Generate BIGFILE: `cat /dev/random | base64 | head -c 1G > BIGFILE`  
```

Then you access the data from anywhere as `Bytes`:  

```crystal
def some_function
  puts String.new Embb.readme
  puts String.new Embb.license
  puts Embb.large.size
  # Random access somewhere in the > 500Mo region of a big file
  puts String.new Embb.large[start: 500_000_000 + rand(500_000_000), count: 10]
end
```

The `Embb.<name>` are a quality of life that build a read-only byte slice. from the raw symbol  
The raw symbols can be accessed through `Embb::Symbols.<name>` as a `UInt8[<input file bytesize>]`.

## Contributors

- [globoplox](https://github.com/globoplox) - creator
