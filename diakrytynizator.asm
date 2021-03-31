section .data

frstByteVals db 00000000b, 11000000b, 11100000b, 11110000b
masks db 01111111b, 00011111b, 00001111b, 00000111b
; Array for checking if the value was encoded with appropriate number of bytes.
; U+0000    U+007F      -> 1 byte
; U+0080    U+07FF      -> 2 bytes
; U+0800    U+FFFF      -> 3 bytes
; U+10000   U+10FFFF    -> 4 bytes
ranges dd 0x0, 0x7F, 0x80, 0x7FF, 0x800, 0xFFFF, 0x10000, 0x10FFFF

SYS_READ equ 0
SYS_WRITE equ 1
SYS_EXIT equ 60
STDIN equ 0
STDOUT equ 1

INBUFSZ equ 4000
OUTBUFSZ equ 4000

ZERO_ASCII equ 48
MOD equ 0x10FF80
SHIFT equ 0x80

global _start

section .bss

inArr resb INBUFSZ
outArr resb OUTBUFSZ

section .text

_start:
  lea r11, [rsp + 8] ; adres args[0]
  pop r8 ; Pop the number of arguments.
  pop r9 ; Pop args[0]
  dec r8
  ; First number on the stack represents the number of coeffs of the polynomial.
  push r8
  jmp loop
push_coef_on_stack:
  mov qword [r11], rax
  xor eax, eax
loop:
  add r11, 8
  mov rsi, [r11] ; The next argument's address.
  test rsi, rsi
  jz next_uni ; Null pointer met, no more parameters.
; Loop for reading a string-number modulo MOD,
; answer is written to the A register, (fits in the eax).
str_to_dec:
  ; Reads the next character, checks if it's NULL.
  mov cl, byte [rsi]
  test cl, cl
  ; If is NULL, time to push rax to the stack.
  jz push_coef_on_stack
  ; Check if the character is a digit.
  ; Otherwise program is terminated with error exitcode.
  cmp cl, 47 ; '0' - 1
  jle error
  cmp cl, 58 ; '9' + 1
  jge error
  ; Multiplies already parsed value by 10,
  ; adds new character to the value,
  ; takes modulo.
  mov ebx, 10
  mul ebx
  add eax, ecx
  sub eax, ZERO_ASCII
  call modulo
  ; Next iteration.
  inc rsi
  jmp str_to_dec

; Normal version.
; rax %= MOD
;modulo:
  ;mov ecx, MOD
  ;div rcx
  ;mov eax, edx
  ;xor edx, edx
  ;xor ecx, ecx
  ;ret

; Optimized gcc -O3 version of the following code.
; uint32_t f(uint64_t x) { return x % 0x10FF80; }
; rax %= MOD
modulo:
  mov rcx, rax
  mov rdx, 0x787c03a5c11c4499
  mul rdx
  shr rdx, 0x13
  imul rdx, rdx, 0x10ff80
  sub rcx, rdx
  mov eax, ecx
  xor edx, edx
  xor ecx, ecx
  ret

; Computes the value of the polynomial on the stack for x equal rdx.
; The polynomial is saved in the following way:
; rdi is the address on stack, which has the number of coefficients of the polynomial.
; Next are [rdi] coefficients in the order of a0 a1 .. an.
calculate:
  xor eax, eax
  mov r11, [rdi]
  mov esi, edx
mult_nd_add:
  test r11, r11
  jz calculated
  mul rsi
  add rax, [rdi + 8 * r11]
  call modulo
  dec r11
  jmp mult_nd_add
calculated:
  ret

; Reads bytes for the unicode value.
; Decodes them into the unicode value and saves it at ebx.
; Next computes polynomial value for the value, and writes encoding bytes
; to the outArr, printing if needed.
next_uni:
  cmp r13, r15
  ; Refresh buffer if needed.
  jne bfer_not_empty
  call read
  mov r15, rax
  cmp r15, 1
  jl exit
  mov r13, 0

bfer_not_empty:
; Read a byte and determine how many bytes encode the current unicode:
; 0xxxxxxx = [00000000, 01111111] = [0, 7f] -> 1 byte
; 110xxxxx = [11000000, 11011111] = [c0, df] -> 2 bytes
; 1110xxxx = [11100000, 11101111] = [e0, ef] -> 3 bytes
; 11110xxx = [11110000, 11110111] = [f0, f7] -> 4 bytes

; 10xxxxxx = [10000000, 10111111] = [80, bf] -> error if it's the first byte
; values greater than f7 also

; So it goes like this:
; [valid] [invalid] [valid                 ] [invalid]
; [0, 7f] [80,  bf] [c0..df, e0..ef, f0..f7] [f8,  ff]

; Algorithm determines with binary search (sort of) which range the first byte falls in.
;               [0, ff]
;           /            \
;      [0, df]            (df, ff]
;    /        \          /       \
; [0, 7f]  (7f, df] (df, ef]  (ef, ff]
;          /      \          /       \
;     [80, c0) [c0, df]  [f0, f7] (f7, ff]

; 10xxxxxx = [10000000, 10111111] = [80, bf] -> i-th byte's range
; in the current unicode if i > 1

; r12 has the number of bytes to read for the current unicode value
; rbx has the beginning of the unicode extracted from the first byte
  xor ebx, ebx
  mov bl, byte [inArr + r13]
  cmp bl, 0xDF
  ja three_or_four
  cmp bl, 0x7F
  jbe one
  cmp bl, 0xC0
  jb error
  mov r12, 2
  sub bl, 0xC0 ; take only meaningful encoding bits
  jmp nr_known
three_or_four:
  cmp bl, 0xEF
  jbe three
  cmp bl, 0xF7
  ja error
  mov r12, 4
  sub bl, 0xF0 ; take only meaningful encoding bits
  jmp nr_known

one:
  mov r12, 1
  jmp nr_known
three:
  mov r12, 3
  sub bl, 0xE0 ; take only meaningful encoding bits

; if one portion left, special treatment

; The number of bytes is known and is in r12
nr_known:
  mov r8, r12
loop_nr_known:
  dec r12
  test r12, r12
  jz check_unicode ; No more bytes for this unicode, encoded number is saved at rbx

  ; go to the next byte, refresh buffer if needed
  inc r13
  cmp r13, r15
  jne bfer_not_empty2
  call read
  mov r15, rax
  cmp r15, 1
  jl error ; Expected more bytes to read.
  mov r13, 0

bfer_not_empty2:
  mov cl, byte [inArr + r13]
  ; cl should be in the form of 10xxxxxx = [10000000, 10111111] = [80, bf]
  cmp cl, 0x80
  jb error
  cmp cl, 0xBF
  ja error
  sub cl, 0x80 ; take 6 meaningful encoding bits
  shl ebx, 6
  add bl, cl
  jmp loop_nr_known

; r8 has the number of bytes that encoded the value in rbx.
; Need to check if the value in rbx is in the appropriate range.
check_unicode:
  dec r8
  cmp ebx, dword [ranges + 8 * r8]
  jb error
  cmp ebx, dword [ranges + 8 * r8 + 4]
  ja error

  ; Check if given unicode needs to be transformed.
  cmp ebx, 0x80
  jb transformed
  ; If needs to, then shift.
  sub ebx, SHIFT
  ; Calculate polynomial (x -> rdx, beginning of polynomial DS -> rdi).
  mov rdx, rbx
  lea rdi, [rsp]
  call calculate
  ; Shift back.
  add eax, SHIFT
  mov ebx, eax
transformed:
  call write
  inc r13
  jmp next_uni

; Reads INBUFSZ bytes into inArr, returns number of bytes read.
read:
  mov eax, SYS_READ
  mov edi, STDIN
  lea rsi, [inArr]
  mov rdx, INBUFSZ
  syscall
  ret

; Encodes unicode value of ebx to outArr.
; If becomes full, prints it.
; r14 is used for the actual size of the buffer.
; U+0000    U+007F      -> 1 byte
; U+0080    U+07FF      -> 2 bytes
; U+0800    U+FFFF      -> 3 bytes
; U+10000   U+10FFFF    -> 4 bytes
; Algorithm determines with binary search how many bytes to print.
write:
  cmp ebx, 0x7FF
  ja three_or_four_bytes
  cmp ebx, 0x7F
  jbe one_byte
  mov r12, 2
  jmp bytes_determined
three_or_four_bytes:
  cmp ebx, 0xFFFF
  jbe three_bytes
  mov r12, 4
  jmp bytes_determined
one_byte:
  mov r12, 1
  jmp bytes_determined
three_bytes:
  mov r12, 3

; r12 has the number of bytes to encode the unicode value.
bytes_determined:
  mov r8, r12 ; r8 is used for counting
; If the number of bytes to encode the unicode is greater than 1,
; they are created iteratively from 6 least significant bits in a loop,
; they are in the form of 10xxxxxx. They are pushed on the stack,
; so that they are retrieved in a good order.
pushing_bytes_loop:
  dec r8
  test r8, r8
  jz first_byte
  mov cl, bl
  ; A bitmask to zero first two bits of a byte.
  and cl, 00111111b
  add cl, 10000000b
  shr ebx, 6
  push rcx
  jmp pushing_bytes_loop
; The first byte is created differently, using a specific bitmask
; depending on the number of encoded bytes.
first_byte:
  dec r12 ; r12 won't be used in the future anymore, so can be used for counting
  mov cl, bl
  and cl, byte [masks + r12]
  add cl, byte [frstByteVals + r12]
  push rcx
; Encoded bytes are retrieved from the stack and written into the array,
; array is printed if there is no space.
popping_bytes_loop:
  pop rcx
  mov byte [outArr + r14], cl
  ; Increment pointer.
  inc r14
  cmp r14, OUTBUFSZ
  jne enough_space
  ; If not enough space, print array.
  call print
  ; Reset pointer.
  xor r14, r14
enough_space:
  test r12, r12
  jz end_write
  dec r12
  jmp popping_bytes_loop
end_write:
  ret

; Size to print is in r14
print:
  mov eax, SYS_WRITE
  mov edi, STDOUT
  lea rsi, [outArr]
  mov rdx, r14
  syscall
  ret

error:
  call print
  mov eax, SYS_EXIT
  mov edi, 1
  syscall

exit:
  call print
  mov eax, SYS_EXIT
  xor edi, edi
  syscall
