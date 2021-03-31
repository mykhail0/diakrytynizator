#!/bin/bash

nasm -g -F dwarf -f elf64 -w+all -w+error -o $1.o $1.asm
ld -g --fatal-warnings -o $1 $1.o
