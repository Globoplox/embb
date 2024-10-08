require "digest/sha256"

# TODO:
# - Support several input files through globbing, in the same elf file
# - Find a way to handle cleaning temporary files after the build to reduce cluttering with potentially huge tmp files

path = ARGV[0]
name = ARGV[1]
arch = ARGV[2]
vendor = ARGV[3]
os = ARGV[4]
abi = ARGV[5]

arch = nil if arch.empty?
vendor = nil if vendor.empty?
os = nil if os.empty?
abi = nil if abi.empty?

# Using elf for everything and hoping linkers are cool enough.
#
# case {os, abi}
# when {"linux", _}, {"openbsd", _}, {"freebsd", _}, {_, "netbsd"}, {"solaris", _}
#   # Use Elf files
# when {"darwin", _}
#   # Use Mach-O
# when {"windows", _}
#   # Use COFF
# end

# Also, only using Elf64 

# Despite not containing any machine code, linker tends to be strict about e_machine compatibility.
# ld on a typical x86_64 linux machine will reject linking with an elf file with no machine specified.
elf_machine = case arch
when "aarch64" then 183 
when "arm" then 40
when "i386" then 3
when "wasm32" then raise "Target architecture 'wasm32' is unsupported" # Not using elf files afaik
when "x86_64" then 62 
when "avr" then 185 
else raise "Target architecture '#{arch}' is not supported"
end

symbol_name = "_embb_#{name}"
path_info = File.info path
data_size = path_info.size

# Reuse existing cache if still fresh
hash = Digest::SHA256.new.update("#{arch}-#{os}-#{abi}-#{path}-#{name}").hexfinal
object_path = Path[Dir.tempdir, "embb_#{hash}.o"]
meta = File.info? object_path

# If not, build an Elf File containing the input file as .rodata
# along with a symbol for it's location.
if meta.nil? || meta.modification_time > path_info.modification_time
  
  io = File.open object_path, "w"

  string_section_data = "\0"
  section_section_name_index = string_section_data.size
  string_section_data += ".shstrtab\0"
  string_section_name_index = string_section_data.size
  string_section_data += ".strtab\0"
  data_section_name_index = string_section_data.size
  string_section_data += ".rodata\0"
  symtab_section_name_index = string_section_data.size
  string_section_data += ".symtab\0"

  symbol_string_section_data = "\0"
  symbol_name_index = symbol_string_section_data.size
  symbol_string_section_data += "#{symbol_name}\0" 


  elf_header_size = 0x40
  section_header_size = 0x40
  section_count = 5 # special 0 first one, section strings, strings, data, symbols 

  symbol_size = 24
  section_header_offset = elf_header_size +
                          string_section_data.size +
                          symbol_string_section_data.size +
                          data_size +
                          symbol_size * 2

  # ELF Header
  io << "\u{7F}ELF" # Magic
  io.write_bytes 2u8, IO::ByteFormat::LittleEndian # 64b
  io.write_bytes 1u8, IO::ByteFormat::LittleEndian # Little-endian
  io.write_bytes 1u8, IO::ByteFormat::LittleEndian # Elf Version
  io.write_bytes 0u8, IO::ByteFormat::LittleEndian # os abi, nothing special
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Pad
  io.write_bytes 1u16, IO::ByteFormat::LittleEndian # Relocatable Object
  io.write_bytes elf_machine.to_u16, IO::ByteFormat::LittleEndian # Architecture
  io.write_bytes 1u32, IO::ByteFormat::LittleEndian # Elf Version
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Unused entry point
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Program header offset
  io.write_bytes section_header_offset.to_u64, IO::ByteFormat::LittleEndian # Section header offset
  io.write_bytes 0x0u32, IO::ByteFormat::LittleEndian # Flags
  io.write_bytes 0x40u16, IO::ByteFormat::LittleEndian # Elf header size
  io.write_bytes 0x38u16, IO::ByteFormat::LittleEndian # Program header table entry size
  io.write_bytes 0u16, IO::ByteFormat::LittleEndian # Program header table entries count
  io.write_bytes section_header_size.to_u16, IO::ByteFormat::LittleEndian # Section header table entry size
  io.write_bytes section_count.to_u16, IO::ByteFormat::LittleEndian # Section header table entries count (string, data, symbols)
  io.write_bytes 1u16, IO::ByteFormat::LittleEndian # Index of section containing section names

  # Sections data
  # Section string data
  io << string_section_data
  # Sybmol string data
  io << symbol_string_section_data
  # Data
  File.open path do |data_io|
    IO.copy src: data_io, dst: io
  end

  # Symbol
  # Undefined first index
  symbol_size.times do
    io.write_byte 0u8
  end

  # Actual symbol
  io.write_bytes symbol_name_index.to_u32, IO::ByteFormat::LittleEndian # Offset of name
  io.write_bytes (1u8 << 4) | 1u8 , IO::ByteFormat::LittleEndian # Type and binding: global | object
  io.write_bytes 0u8, IO::ByteFormat::LittleEndian # Visibility default
  io.write_bytes 3u16, IO::ByteFormat::LittleEndian # Section index
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Symbol value
  io.write_bytes 8u64, IO::ByteFormat::LittleEndian # Symbol size

  offset = elf_header_size

  # First section (0)
  section_header_size.times do
    io.write_byte 0u8
  end

  # Section string section
  io.write_bytes section_section_name_index.to_u32, IO::ByteFormat::LittleEndian # Offset in section names section to name of this section
  io.write_bytes 3u32, IO::ByteFormat::LittleEndian # String table
  io.write_bytes 0x20u64, IO::ByteFormat::LittleEndian # Null terminated strings
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Virtual address
  io.write_bytes offset.to_u64, IO::ByteFormat::LittleEndian # Section offset 
  io.write_bytes string_section_data.size.to_u64, IO::ByteFormat::LittleEndian # Section size
  io.write_bytes 0u32, IO::ByteFormat::LittleEndian # Index of linked section
  io.write_bytes 0u32, IO::ByteFormat::LittleEndian # Info
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Alignement required
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Size of entries

  offset += string_section_data.size

  # String section
  io.write_bytes string_section_name_index.to_u32, IO::ByteFormat::LittleEndian # Offset in section names section to name of this section
  io.write_bytes 3u32, IO::ByteFormat::LittleEndian # String table
  io.write_bytes 0x20u64, IO::ByteFormat::LittleEndian # Null terminated strings
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Virtual address
  io.write_bytes offset.to_u64, IO::ByteFormat::LittleEndian # Section offset
  io.write_bytes symbol_string_section_data.size.to_u64, IO::ByteFormat::LittleEndian # Section size
  io.write_bytes 0u32, IO::ByteFormat::LittleEndian # Index of linked section
  io.write_bytes 0u32, IO::ByteFormat::LittleEndian # Info
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Alignement required
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Size of entries

  offset += symbol_string_section_data.size

  # Data section
  io.write_bytes data_section_name_index.to_u32, IO::ByteFormat::LittleEndian # Offset in section names section to name of this section
  io.write_bytes 1u32, IO::ByteFormat::LittleEndian # Program data
  io.write_bytes 0x2u64, IO::ByteFormat::LittleEndian # Occupies memory
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Virtual address
  io.write_bytes offset.to_u64, IO::ByteFormat::LittleEndian # Section offset
  io.write_bytes data_size.to_u64, IO::ByteFormat::LittleEndian # Section size
  io.write_bytes 0u32, IO::ByteFormat::LittleEndian # Index of linked section
  io.write_bytes 0u32, IO::ByteFormat::LittleEndian # Info
  io.write_bytes 8u64, IO::ByteFormat::LittleEndian # Alignement required
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Size of entries

  offset += data_size

  # Symbol section
  io.write_bytes symtab_section_name_index.to_u32, IO::ByteFormat::LittleEndian # Offset in section names section to name of this section
  io.write_bytes 2u32, IO::ByteFormat::LittleEndian # Symbol table
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # No flags
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Virtual address
  io.write_bytes offset.to_u64, IO::ByteFormat::LittleEndian # Section offset
  io.write_bytes (symbol_size * 2).to_u64, IO::ByteFormat::LittleEndian # Section size
  io.write_bytes 2u32, IO::ByteFormat::LittleEndian # Index of linked section (symbol string section)
  io.write_bytes 1u32, IO::ByteFormat::LittleEndian # One greater than the symbol table index of the last local symbol (binding STB_LOCAL).
  io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Alignement required
  io.write_bytes symbol_size.to_u64, IO::ByteFormat::LittleEndian # Size of a symbol entry (24 bytes)
  io.close
end

# Output crystal code to be embbed in caller.

STDOUT << <<-CRYSTAL
@[Link(ldflags: "#{object_path}")]
lib Embb::Symbols
  $#{symbol_name} : UInt8[#{data_size}]
end

module Embb
  def #{name}
     Bytes.new Symbols.#{symbol_name}.to_unsafe, Symbols.#{symbol_name}.size, read_only: true
  end  
end
CRYSTAL
