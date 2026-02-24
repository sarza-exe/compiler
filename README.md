# Imperative Language Compiler

This project is a compiler for a simple imperative language, generating code for a dedicated virtual machine. The tool was built using **BISON** and **FLEX** generators within a **C++** environment.

## 📁 File Structure

* `parser.y` – The core of the project. BISON grammar specification. It parses the grammar and generates virtual machine code while performing error checking and reporting.
* `lexer.l` – FLEX lexical analyzer for the input source code.
* `codeGenerator.hh` – Responsible for code generation, creating and fixing jump instructions (backpatching), and generating code snippets for multiplication, division, and constant generation.
* `symbolTable.hh` – Manages information regarding variables, parameters, iterators, and procedures.
* `main.cc` – Handles file I/O and invokes the parser.
* `Makefile` – Build script for the project.

## 🏆 Ranking and Stability

The compiler participated in a performance and quality ranking, securing **26th place out of 79** participants.

**Reliability:** The program passed **100% of the competition tests** (28/28 hidden scenarios), confirming its stability and resilience against logical errors in the source code.

**Compliance:** Fully supports advanced language elements such as procedure parameters passed by reference (IN-OUT), constants (I), and undefined output parameters (O).

## ⚙️ Key Functionalities

**Efficient Arithmetic:** Implementation of multiplication, division, and modulo operations executes in **logarithmic time** relative to the argument values. This avoids costly loops based on simple addition/subtraction.

**Jump Management:** The program emits and repairs (backpatching) virtual machine jump instructions required for conditional statements, procedure calls, and `FOR`, `WHILE`, and `REPEAT-UNTIL` loops .

**Memory Management:** Full support for arrays with arbitrary indexing ranges (e.g., `tab[10:20]`) and local `FOR` loop iterators. Correct reference assignment during procedure calls.

**Error Analysis:** The compiler precisely signals semantic errors, such as variable redefinition, use of undeclared identifiers, or attempts to modify constants or iterators.

## 🚀 Usage

As per requirements, the project includes a `Makefile`.

1. **Compiling the project:**

```bash
make

```

2. **Running the compiler:**

```bash
./kompilator <input_file> <output_file>

```

---

## 🖥️ Virtual Machine Instruction Set

The virtual machine consists of 8 registers ($r_a$ through $r_h$), a program counter $k$, and memory cells $p_i$.

| Instruction | Interpretation | Cost |
| --- | --- | --- |
| `READ` | Read number into $r_a$; $k \leftarrow k+1$ | 100 |
| `WRITE` | Display content of $r_a$; $k \leftarrow k+1$ | 100 |
| `LOAD j` | $r_a \leftarrow p_j$; $k \leftarrow k+1$ | 50 |
| `STORE j` | $p_j \leftarrow r_a$; $k \leftarrow k+1$ | 50 |
| `RLOAD rx` | $r_a \leftarrow p_{r_x}$; $k \leftarrow k+1$ | 50 |
| `RSTORE rx` | $p_{r_x} \leftarrow r_a$; $k \leftarrow k+1$ | 50 |
| `ADD x` | $r_a \leftarrow r_a + r_x$; $k \leftarrow k+1$ | 5 |
| `SUB x` | $r_a \leftarrow \max\{r_a - r_x, 0\}$; $k \leftarrow k+1$ | 5 |
| `SWP x` | $r_a \leftrightarrow r_x$; $k \leftarrow k+1$ | 5 |
| `RST x` | $r_x \leftarrow 0$; $k \leftarrow k+1$ | 1 |
| `INC x` | $r_x \leftarrow r_x + 1$; $k \leftarrow k+1$ | 1 |
| `DEC x` | $r_x \leftarrow \max\{r_x - 1, 0\}$; $k \leftarrow k+1$ | 1 |
| `SHL x` | $r_x \leftarrow 2 * r_x$; $k \leftarrow k+1$ | 1 |
| `SHR x` | $r_x \leftarrow \lfloor r_x / 2 \rfloor$; $k \leftarrow k+1$ | 1 |
| `JUMP j` | $k \leftarrow j$ | 1 |
| `JPOS j` | If $r_a > 0$ then $k \leftarrow j$, else $k \leftarrow k+1$ | 1 |
| `JZERO j` | If $r_a = 0$ then $k \leftarrow j$, else $k \leftarrow k+1$ | 1 |
| `CALL j` | $r_a \leftarrow k+1$; $k \leftarrow j$ | 1 |
| `RTRN` | $k \leftarrow r_a$ | 1 |
| `HALT` | Stop execution | 0 |



---

**Author**: Sara Żyndul
