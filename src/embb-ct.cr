# Looks into:
# - Using llvm-objcopy if it is available on the current host
# - Using libelf instead of all this

# TODO:
# - Support other target than x86_64-unknown-linux
# - Support shoving several input files into a single elf
# - Support several input files through globbing
# - Check file update time and use input (files path / glob) hashes for temporary objects files names
# - Find a way to handle cleaning temporary files after the build to reduce cluttering with potentially huge tmp files
#   (Use a build level ID ? Might not pair well with crystal caching ?)
#   (configurable threshold for cache size, cleaning older previous build tmp files when reached ?)

path = ARGV[0]
name = ARGV[1]

symbol_name = "_embb_#{name}"
data_size = File.info(path).size

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

io = File.tempfile "#{symbol_name}.o"

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
io.write_bytes 3u8, IO::ByteFormat::LittleEndian # Linux
io.write_bytes 0u64, IO::ByteFormat::LittleEndian # Pad
io.write_bytes 1u16, IO::ByteFormat::LittleEndian # Relocatable Object
io.write_bytes 0x3Eu16, IO::ByteFormat::LittleEndian # x86-64
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

STDOUT << <<-CRYSTAL
@[Link(ldflags: "#{io.path}")]
lib Embb#{symbol_name}
  $ptr = #{symbol_name} : Void
end

module Embb
  def #{symbol_name}
     Bytes.new pointerof(Embb#{symbol_name}.ptr).as(UInt8*), #{data_size}
  end  
end
CRYSTAL

io.close
