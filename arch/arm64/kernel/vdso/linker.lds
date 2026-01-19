/* Minimal linker script for -r flag */
SECTIONS
{
  .text : { *(.text) }
  .data : { *(.data) }
  .bss : { *(.bss) }
  .rodata : { *(.rodata) }
}
