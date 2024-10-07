# embb

Embbed large binary (or not) files into crystal lang executables.  
This is a proof of concept.  
Currently only support the runtime target x86_64-unknown-linux.  

This library work by generating object files wrapping the given input files and linking them the the crystal executable.  
Most of the work is delagated to the linker.  

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     embb:
       github: globoplox/embb
   ```

2. Run `shards install`

## Usage

```crystal
require "embb"

# At top level, declare the files to embbed
# Note: `Embb.embbed` is a macro and so parameters must be defined as literals.

Embb.embbed "./README.md", as: readme
Embb.embbed "./LICENSE", as: license
Embb.embbed "./BIGFILE", as: large

# Then use them from anywhere as `Bytes`:

def some_function
  puts String.new Embb.readme
  puts String.new Embb.license
  puts Embb.large.size
  # Random access somewhere in the > 500Mo region of bigfile
  puts String.new Embb.large[start: 500_000_000 + rand(500_000_000), count: 10]
end
```

Generate BIGFILE: `cat /dev/random | base64 | head -c 1G > BIGFILE`  

## Contributors

- [globoplox](https://github.com/globoplox) - creator
